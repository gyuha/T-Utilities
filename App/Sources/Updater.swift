import AppKit
import Foundation
import Security

/// Checks GitHub Releases for a newer build and, only when the user asks, installs it in place.
/// A downloaded app is accepted only if it satisfies this app's own designated requirement
/// (same bundle id + same "T-Utilities Dev" certificate), so permissions granted to us carry over.
@MainActor
@Observable
final class Updater {
    struct Release: Equatable {
        let version: String
        let zipURL: URL
        let pageURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(Release)
        case failed(String)
    }

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/mordol/T-Utilities/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "updater.lastCheck"

    private(set) var state: State = .idle
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    @ObservationIgnored private var scheduler: Task<Void, Never>?

    var isInstalling: Bool {
        if case .installing = state { return true }
        return false
    }

    var availableRelease: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// Checks at launch and then at most once a day while the app keeps running.
    func startSchedule() {
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkIfDue()
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    private func checkIfDue() async {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last >= Self.checkInterval else { return }
        await check()
    }

    func check() async {
        switch state {
        case .checking, .installing: return
        default: break
        }
        state = .checking
        do {
            var request = URLRequest(url: Self.latestReleaseAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError("릴리스 정보를 가져오지 못했습니다")
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            let release = try Self.parse(data)
            state = Self.isNewer(release.version, than: currentVersion) ? .available(release) : .upToDate
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func install() {
        guard let release = availableRelease else { return }
        state = .installing(release)
        Task {
            do {
                let newApp = try await Self.download(release)
                try Self.verify(newApp)
                try Self.replaceAndRelaunch(with: newApp)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Steps

    nonisolated static func parse(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let zip = payload.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            throw UpdateError("릴리스에 앱 파일이 없습니다")
        }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return Release(version: version, zipURL: zip.browser_download_url, pageURL: payload.html_url)
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let parts = { (version: String) in version.split(separator: ".").map { Int($0) ?? 0 } }
        let lhs = parts(candidate), rhs = parts(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func download(_ release: Release) async throws -> URL {
        let (zip, _) = try await URLSession.shared.download(from: release.zipURL)
        let dir = FileManager.default.temporaryDirectory.appending(path: "T-Utilities-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
        let app = dir.appending(path: "T-Utilities.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw UpdateError("압축 파일에 T-Utilities.app이 없습니다") }
        // Downloaded through URLSession, so normally not quarantined; strip it anyway to avoid Gatekeeper prompts.
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    /// The new app (including the embedded AwakeGuard) must be validly signed by the same certificate as this one.
    private static func verify(_ app: URL) throws {
        var selfCode: SecStaticCode?
        var requirement: SecRequirement?
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyDesignatedRequirement(selfCode, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode
        else { throw UpdateError("서명 정보를 읽지 못했습니다") }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw UpdateError("새 버전의 서명이 현재 앱과 일치하지 않아 설치하지 않았습니다")
        }
    }

    /// Swaps the bundle on disk, then a detached shell waits for this process to exit and opens the new app.
    private static func replaceAndRelaunch(with newApp: URL) throws {
        let target = Bundle.main.bundleURL
        _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
        let pid = ProcessInfo.processInfo.processIdentifier
        let relaunch = Process()
        relaunch.executableURL = URL(filePath: "/bin/sh")
        relaunch.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", target.path]
        try relaunch.run()
        // Not directly: we're inside a main-actor Task, and terminate's `.terminateLater` wait would block the
        // main actor that the module shutdown needs (deadlock). A run-loop perform behaves like Quit from a menu.
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError("\(tool) 실패 (\(process.terminationStatus))") }
    }
}

struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
