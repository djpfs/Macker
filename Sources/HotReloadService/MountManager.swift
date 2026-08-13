//===----------------------------------------------------------------------===//
// MountManager — wires FSEventWatcher + InotifyBridge for a set of mounts.
//
// Owns the watcher lifecycle: start() begins watching all mounts, stop()
// tears everything down. Changes flow host → bridge → transport → guest.
//===----------------------------------------------------------------------===//

import Foundation
import ContainerBackend

/// Coordinates hot reload for a set of bind mounts.
public final class MountManager: @unchecked Sendable {
    private let watcher: FSEventWatcher
    private let bridge: InotifyBridge
    private let queue: DispatchQueue

    /// Creates a manager for the given mounts.
    /// - Parameters:
    ///   - mounts: Host directories to watch, mapped to their containers.
    ///   - transport: How touches are delivered into the guest.
    public init(mounts: [InotifyBridge.Mount], transport: any TouchTransport) {
        self.bridge = InotifyBridge(mounts: mounts, transport: transport)
        self.queue = DispatchQueue(label: "macker.hot-reload", qos: .utility)
        self.watcher = FSEventWatcher(
            paths: mounts.map(\.hostPath),
            debounceWindow: 0.1
        ) { [bridge] changes in
            Task {
                do {
                    try await bridge.handle(changes)
                } catch {
                    // A failed touch is non-fatal: the next edit retries.
                    // Logging is left to the caller via the error handler.
                    Self.onError?(error)
                }
            }
        }
    }

    /// Optional hook for surfacing bridge errors (e.g. to the GUI).
    /// `nonisolated(unsafe)` because it is a plain callback hook; set it once
    /// at startup.
    public nonisolated(unsafe) static var onError: ((Error) -> Void)?

    /// Start watching all mounts.
    public func start() {
        watcher.start()
    }

    /// Stop watching all mounts.
    public func stop() {
        watcher.stop()
    }
}
