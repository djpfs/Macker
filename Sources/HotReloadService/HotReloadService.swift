//===----------------------------------------------------------------------===//
// HotReloadService — FSEvents → synthetic inotify bridge for virtiofs mounts.
//
// virtiofs does not propagate inotify events to the guest, so watch tools
// (Vite, webpack, nodemon, Air) never see host-side changes. Following the
// Colima/Lima `--mount-inotify` pattern, this module:
//   1. watches host directories with FSEvents (debounced, 100ms windows)
//   2. forwards changed paths to a small guest agent inside the container
//   3. the guest agent `touch`es the corresponding file
//   4. the Linux kernel emits inotify ATTRIB → watch tools rebuild
//
// Components:
//   • FSEventWatcher   — FSEventStreamCreate wrapper (debounce + dedup)
//   • InotifyBridge    — host→container path mapping, batching
//   • Transports       — ExecTouchTransport (default) / SocketTouchTransport
//   • GuestAgent       — Linux aarch64 binary + injection/start
//   • MountManager     — wires watcher + bridge for a set of mounts
//
// Known limitations (same as Colima/Lima):
//   • Only ATTRIB events are synthesized — no MODIFY/CREATE/DELETE.
//   • Deletions on the host do not propagate (the file no longer exists to
//     touch).
//   • Events are debounced to 100ms windows to avoid storms.
//===----------------------------------------------------------------------===//

import Foundation

public enum HotReloadService {
    /// Debounce window for FSEvents aggregation.
    public static let debounceWindow: Duration = .milliseconds(100)
}
