import AppKit
import ScreenCaptureKit

/// Window thumbnails through ScreenCaptureKit. One screenshot per window, taken only while the switcher opens;
/// nothing keeps running afterwards.
enum ThumbnailCapture {
    private struct Job: @unchecked Sendable {
        let windowID: CGWindowID
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
    }

    private struct Shot: @unchecked Sendable {
        let windowID: CGWindowID
        let image: CGImage
    }

    /// Captures the given windows concurrently and hands each image over as soon as it is ready.
    /// `maxPixelSize` bounds the captured size so large windows are not captured at full resolution.
    static func capture(
        windowIDs: [CGWindowID], maxPixelSize: CGSize,
        deliver: @MainActor @Sendable (CGWindowID, CGImage) -> Void
    ) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return }
        let wanted = Set(windowIDs)
        let targets = content.windows.filter { wanted.contains($0.windowID) }
        await withTaskGroup(of: Shot?.self) { group in
            for window in targets {
                let id = window.windowID
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                let scale = min(1, maxPixelSize.width / max(window.frame.width, 1), maxPixelSize.height / max(window.frame.height, 1))
                configuration.width = max(1, Int(window.frame.width * scale))
                configuration.height = max(1, Int(window.frame.height * scale))
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                let job = Job(windowID: id, filter: filter, configuration: configuration)
                group.addTask {
                    guard let image = try? await SCScreenshotManager.captureImage(contentFilter: job.filter, configuration: job.configuration)
                    else { return nil }
                    return Shot(windowID: job.windowID, image: image)
                }
            }
            for await shot in group {
                guard !Task.isCancelled else { return }
                if let shot { await deliver(shot.windowID, shot.image) }
            }
        }
    }
}
