import Darwin
import Foundation

/// An AI coding agent that is currently doing work on this Mac.
struct DetectedAgent: Hashable, Sendable {
    let name: String
}

/// Decides whether coding agents are actively working, without reading transcript contents.
///
/// - Paseo: per-agent state files (`~/.paseo/agents/*/*.json`) while the Paseo daemon is alive.
///   Working = `running`/`initializing`, or (optionally) blocked on a permission prompt.
///   Secret files in `~/.paseo` (config, credentials, keypair) are never read.
/// - Claude / Codex / Cursor: a transcript file modified within the freshness window (eclam's approach),
///   which also covers agents started outside Paseo.
struct AgentDetector: Sendable {
    enum Source: String, CaseIterable, Sendable {
        case claude, codex, cursor, paseo

        var displayName: String {
            switch self {
            case .claude: "Claude"
            case .codex: "Codex"
            case .cursor: "Cursor"
            case .paseo: "Paseo"
            }
        }
    }

    struct Trace: Sendable {
        let source: Source
        /// Relative to the home directory. POSIX glob: `*` and `?` only.
        let pattern: String
        let freshness: TimeInterval
    }

    static let traces: [Trace] = [
        Trace(source: .claude, pattern: ".claude/projects/*/*.jsonl", freshness: 60),
        Trace(source: .codex, pattern: ".codex/sessions/*/*/*/rollout-*.jsonl", freshness: 60),
        Trace(source: .cursor, pattern: ".cursor/projects/*/agent-transcripts/*/*.jsonl", freshness: 90),
    ]

    let home: URL
    var sources: Set<Source>
    /// Count Paseo agents waiting on a permission prompt as working.
    var countsPermissionWait: Bool

    func detect(now: Date = Date()) -> [DetectedAgent] {
        var agents: [DetectedAgent] = []
        var paseoProviders: Set<String> = []

        if sources.contains(.paseo) {
            for provider in workingPaseoProviders() {
                paseoProviders.insert(provider.lowercased())
                agents.append(DetectedAgent(name: "\(provider.capitalized) (Paseo)"))
            }
        }
        for trace in Self.traces where sources.contains(trace.source) {
            // Paseo already reported this provider more precisely.
            guard !paseoProviders.contains(trace.source.rawValue) else { continue }
            if hasFreshFile(matching: trace.pattern, within: trace.freshness, now: now) {
                agents.append(DetectedAgent(name: trace.source.displayName))
            }
        }
        return Array(Set(agents)).sorted { $0.name < $1.name }
    }

    // MARK: - Paseo

    private struct PaseoPID: Decodable {
        let pid: Int32
    }

    private struct PaseoAgent: Decodable {
        let provider: String?
        let lastStatus: String?
        let requiresAttention: Bool?
        let attentionReason: String?
    }

    private func workingPaseoProviders() -> [String] {
        let paseo = home.appendingPathComponent(".paseo")
        guard let data = try? Data(contentsOf: paseo.appendingPathComponent("paseo.pid")),
              let info = try? JSONDecoder().decode(PaseoPID.self, from: data),
              Self.isProcessAlive(info.pid) else { return [] }

        return Self.glob(paseo.appendingPathComponent("agents/*/*.json").path).compactMap { path in
            guard let data = FileManager.default.contents(atPath: path),
                  let agent = try? JSONDecoder().decode(PaseoAgent.self, from: data) else { return nil }
            let busy = agent.lastStatus == "running" || agent.lastStatus == "initializing"
            let awaitingPermission = countsPermissionWait
                && agent.requiresAttention == true
                && agent.attentionReason == "permission"
            return busy || awaitingPermission ? (agent.provider ?? "agent") : nil
        }
    }

    static func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Transcripts

    private func hasFreshFile(matching pattern: String, within freshness: TimeInterval, now: Date) -> Bool {
        Self.glob(home.appendingPathComponent(pattern).path).contains { path in
            var info = stat()
            guard stat(path, &info) == 0 else { return false }
            let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
            return now.timeIntervalSince(modified) < freshness
        }
    }

    static func glob(_ pattern: String) -> [String] {
        var result = glob_t()
        defer { globfree(&result) }
        guard Darwin.glob(pattern, 0, nil, &result) == 0 else { return [] }
        return (0..<Int(result.gl_pathc)).compactMap { index in
            result.gl_pathv[index].map { String(cString: $0) }
        }
    }
}
