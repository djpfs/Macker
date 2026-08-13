//===----------------------------------------------------------------------===//
// InotifyBridge — maps host FSEvents to guest `touch` commands.
//
// virtiofs does not propagate inotify events into the guest, so watch tools
// inside a container never see host-side edits. The bridge closes that gap:
// for each debounced host change it computes the corresponding path inside
// the container (relative to the mount root) and asks a transport to touch it.
// The Linux kernel then emits inotify ATTRIB, which is what Vite, webpack,
// nodemon, Air, etc. listen for.
//===----------------------------------------------------------------------===//

import Foundation
import ContainerBackend

/// Sends `touch` commands into a container. Two implementations exist:
/// ``ExecTouchTransport`` (runs `touch` via the process API — works without
/// any guest-side tooling) and ``SocketTouchTransport`` (streams paths to the
/// guest agent over a dialed connection).
public protocol TouchTransport: Sendable {
    /// Touch the given container-relative paths inside `containerID`.
    func touch(paths: [String], in containerID: String) async throws
}

/// Bridges host FSEvents to guest touches for a set of bind mounts.
public struct InotifyBridge: Sendable {
    /// A host directory mapped to a container mount point.
    public struct Mount: Sendable {
        /// Absolute host path, e.g. `/Users/me/project`.
        public let hostPath: String
        /// Container path the host directory is mounted at, e.g. `/app`.
        public let containerPath: String
        /// The container that owns this mount.
        public let containerID: String

        public init(hostPath: String, containerPath: String, containerID: String) {
            self.hostPath = hostPath
            self.containerPath = containerPath
            self.containerID = containerID
        }
    }

    let transport: any TouchTransport
    private let mounts: [Mount]

    /// Creates a bridge.
    /// - Parameters:
    ///   - mounts: The bind mounts to watch.
    ///   - transport: How touches are delivered into the guest.
    public init(mounts: [Mount], transport: any TouchTransport) {
        self.mounts = mounts
        self.transport = transport
    }

    /// Handle a batch of host changes, touching the corresponding guest paths.
    /// Paths that fall outside any watched mount are ignored.
    public func handle(_ changes: [FSEventWatcher.Change]) async throws {
        // Group container-relative paths by container so each container gets
        // one batched touch command.
        var byContainer: [String: [String]] = [:]
        for change in changes {
            // Only content changes are worth touching; pure metadata flips
            // (permissions, xattrs) would just churn the watchers.
            guard change.isContentChange else { continue }
            guard let (containerID, relative) = mapToContainer(change.path) else { continue }
            byContainer[containerID, default: []].append(relative)
        }
        for (containerID, paths) in byContainer {
            try await transport.touch(paths: paths, in: containerID)
        }
    }

    /// Map a host path to a (containerID, container-relative path) pair.
    private func mapToContainer(_ hostPath: String) -> (String, String)? {
        for mount in mounts {
            let host = (mount.hostPath as NSString).standardizingPath
            let path = (hostPath as NSString).standardizingPath
            if path == host {
                return (mount.containerID, mount.containerPath)
            }
            if path.hasPrefix(host + "/") {
                let suffix = String(path.dropFirst(host.count))
                return (mount.containerID, mount.containerPath + suffix)
            }
        }
        return nil
    }
}
