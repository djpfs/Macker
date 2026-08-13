//===----------------------------------------------------------------------===//
// FSEventWatcher — FSEventStreamCreate wrapper for host directory watching.
//
// Watches a set of host directories and delivers debounced change events.
// The FSEvents `latency` parameter already coalesces bursts; on top of that
// we collapse duplicate paths within a window so a single save (which can
// produce several events) yields exactly one touch.
//===----------------------------------------------------------------------===//

import Foundation
import CoreServices

/// A single filesystem change reported by FSEvents.
public struct FSEvent: Sendable {
    /// The absolute path that changed.
    public let path: String
    /// The raw FSEvents flags for this event.
    public let flags: FSEventStreamEventFlags

    /// Whether the event is a content modification (as opposed to a purely
    /// metadata change like a permission flip).
    public var isContentChange: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemModified) != 0
            || flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
            || flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
            || flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
    }
}

/// Watches host directories with FSEvents and delivers debounced, deduplicated
/// change events on a background queue.
public final class FSEventWatcher: @unchecked Sendable {
    /// A change event delivered to the handler: the path plus whether it is a
    /// content change (touch-worthy) or only a metadata change.
    public struct Change: Sendable {
        public let path: String
        public let isContentChange: Bool
    }

    private var stream: FSEventStreamRef?
    private let queue: DispatchQueue
    private let handler: @Sendable ([Change]) -> Void
    private let debounceWindow: TimeInterval

    /// Creates a watcher for the given paths.
    ///
    /// - Parameters:
    ///   - paths: Host directories to watch (absolute paths).
    ///   - debounceWindow: How long (seconds) to aggregate events before
    ///     delivering.
    ///   - handler: Called on a background queue with the debounced changes.
    public init(
        paths: [String],
        debounceWindow: TimeInterval = 0.1,
        handler: @escaping @Sendable ([Change]) -> Void
    ) {
        self.queue = DispatchQueue(label: "macker.fsevents", qos: .utility)
        self.handler = handler
        self.debounceWindow = debounceWindow
        self.stream = Self.makeStream(paths: paths, watcher: self)
    }

    /// Start delivering events.
    public func start() {
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    /// Stop delivering events. Safe to call multiple times.
    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    // MARK: - FSEvents plumbing

    private static func makeStream(paths: [String], watcher: FSEventWatcher) -> FSEventStreamRef? {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(watcher).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
        )
        return FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, numEvents, eventPaths, eventFlags, _ in
                guard let info else { return }
                let watcher = Unmanaged<FSEventWatcher>.fromOpaque(info).takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
                var events: [FSEvent] = []
                events.reserveCapacity(Int(numEvents))
                for index in 0..<Int(numEvents) {
                    events.append(FSEvent(path: paths[index], flags: eventFlags[index]))
                }
                watcher.received(events)
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            flags
        )
    }

    /// Called on the FSEvents queue with raw events. Debounces and dedupes,
    /// then forwards to the handler.
    private func received(_ events: [FSEvent]) {
        // Collapse duplicate paths, keeping the most "content-like" flag.
        var byPath: [String: Bool] = [:]
        for event in events {
            let resolved = (event.path as NSString).resolvingSymlinksInPath
            let isContent = event.isContentChange
            if let existing = byPath[resolved] {
                byPath[resolved] = existing || isContent
            } else {
                byPath[resolved] = isContent
            }
        }
        let changes = byPath.map { Change(path: $0.key, isContentChange: $0.value) }
        guard !changes.isEmpty else { return }

        // FSEvents latency already coalesces; a short extra window lets a
        // burst of events for the same file collapse into one delivery.
        queue.asyncAfter(deadline: .now() + debounceWindow) { [handler] in
            handler(changes)
        }
    }
}
