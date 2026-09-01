import CoreServices
import Foundation

/// Watches the screen-capture directory for new screenshots.
///
/// FSEvents is entirely event-driven, so this costs nothing while idle.
final class ScreenshotWatcher {

    private var stream: FSEventStreamRef?
    private let onNewFiles: ([URL]) -> Void

    init(onNewFiles: @escaping ([URL]) -> Void) {
        self.onNewFiles = onNewFiles
    }

    /// Where macOS is currently writing screenshots.
    ///
    /// Verified on this machine: `com.apple.screencapture location` is UNSET by
    /// default, so the absent-key case is the normal one, not an edge case.
    static func captureDirectory() -> URL {
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location"), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func start() {
        guard stream == nil else { return }
        let path = Self.captureDirectory().path

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            screenshotWatcherCallback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,                      // coalescing latency, not a poll interval
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func handle(paths: [String]) {
        let candidates = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { Self.isScreenshot($0) }
        guard !candidates.isEmpty else { return }
        onNewFiles(candidates)
    }

    /// Spotlight marks real screen captures with `kMDItemIsScreenCapture`, which
    /// is far more reliable than matching the filename — that string is
    /// localised and changes between releases.
    ///
    /// Spotlight can lag a moment behind the write, so a recent image file in
    /// the capture directory is accepted as a fallback.
    static func isScreenshot(_ url: URL) -> Bool {
        let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "pdf"]
        guard imageTypes.contains(url.pathExtension.lowercased()),
              FileManager.default.fileExists(atPath: url.path) else { return false }

        if let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
           let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool {
            return value
        }

        guard let created = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.creationDate] as? Date else { return false }
        return Date().timeIntervalSince(created) < 10
    }
}

private func screenshotWatcherCallback(stream: ConstFSEventStreamRef,
                                       info: UnsafeMutableRawPointer?,
                                       count: Int,
                                       paths: UnsafeMutableRawPointer,
                                       flags: UnsafePointer<FSEventStreamEventFlags>,
                                       ids: UnsafePointer<FSEventStreamEventId>) {
    guard let info, let cfPaths = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
    let watcher = Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()

    // Only files that were created or renamed into place.
    var interesting: [String] = []
    for index in 0..<count {
        let flag = flags[index]
        let created = flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0
        let renamed = flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0
        if created || renamed, index < cfPaths.count { interesting.append(cfPaths[index]) }
    }
    guard !interesting.isEmpty else { return }
    watcher.handle(paths: interesting)
}
