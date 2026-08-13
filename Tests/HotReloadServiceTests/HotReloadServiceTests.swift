//===----------------------------------------------------------------------===//
// HotReloadServiceTests — path mapping, content filtering, batching.
//===----------------------------------------------------------------------===//

import XCTest
import CoreServices
@testable import HotReloadService

final class HotReloadServiceTests: XCTestCase {

    // MARK: - InotifyBridge path mapping

    func testMapHostPathToContainerPath() async throws {
        let mount = InotifyBridge.Mount(
            hostPath: "/Users/me/project",
            containerPath: "/app",
            containerID: "abc"
        )
        let bridge = InotifyBridge(mounts: [mount], transport: RecordingTransport())

        let changes = [
            FSEventWatcher.Change(path: "/Users/me/project/src/main.ts", isContentChange: true),
            FSEventWatcher.Change(path: "/Users/me/project/package.json", isContentChange: true),
        ]
        try await bridge.handle(changes)

        let recorded = await bridge.transport.recorded
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].containerID, "abc")
        XCTAssertEqual(Set(recorded[0].paths), ["/app/src/main.ts", "/app/package.json"])
    }

    func testMapMountRootItself() async throws {
        let mount = InotifyBridge.Mount(
            hostPath: "/Users/me/project",
            containerPath: "/app",
            containerID: "abc"
        )
        let bridge = InotifyBridge(mounts: [mount], transport: RecordingTransport())

        try await bridge.handle([
            FSEventWatcher.Change(path: "/Users/me/project", isContentChange: true)
        ])

        let recorded = await bridge.transport.recorded
        XCTAssertEqual(recorded.first?.paths, ["/app"])
    }

    func testIgnoresPathsOutsideMounts() async throws {
        let mount = InotifyBridge.Mount(
            hostPath: "/Users/me/project",
            containerPath: "/app",
            containerID: "abc"
        )
        let bridge = InotifyBridge(mounts: [mount], transport: RecordingTransport())

        try await bridge.handle([
            FSEventWatcher.Change(path: "/Users/me/other/file.txt", isContentChange: true)
        ])

        let recorded = await bridge.transport.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func testIgnoresMetadataOnlyChanges() async throws {
        let mount = InotifyBridge.Mount(
            hostPath: "/Users/me/project",
            containerPath: "/app",
            containerID: "abc"
        )
        let bridge = InotifyBridge(mounts: [mount], transport: RecordingTransport())

        try await bridge.handle([
            FSEventWatcher.Change(path: "/Users/me/project/file.txt", isContentChange: false)
        ])

        let recorded = await bridge.transport.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func testBatchesByContainer() async throws {
        let mounts = [
            InotifyBridge.Mount(hostPath: "/Users/me/a", containerPath: "/a", containerID: "one"),
            InotifyBridge.Mount(hostPath: "/Users/me/b", containerPath: "/b", containerID: "two"),
        ]
        let bridge = InotifyBridge(mounts: mounts, transport: RecordingTransport())

        try await bridge.handle([
            FSEventWatcher.Change(path: "/Users/me/a/x.txt", isContentChange: true),
            FSEventWatcher.Change(path: "/Users/me/b/y.txt", isContentChange: true),
        ])

        let recorded = await bridge.transport.recorded
        XCTAssertEqual(Set(recorded.map(\.containerID)), ["one", "two"])
    }

    // MARK: - FSEvent content detection

    func testContentChangeFlags() {
        // A modified event should be a content change.
        let modified = FSEvent(path: "/x", flags: UInt32(kFSEventStreamEventFlagItemModified))
        XCTAssertTrue(modified.isContentChange)

        // A pure metadata event (e.g. inode meta mod) should not be.
        let meta = FSEvent(path: "/x", flags: UInt32(kFSEventStreamEventFlagItemInodeMetaMod))
        XCTAssertFalse(meta.isContentChange)
    }
}

/// A transport that records what it was asked to touch.
private final class RecordingTransport: TouchTransport, @unchecked Sendable {
    struct Record: Sendable {
        let containerID: String
        let paths: [String]
    }

    private let lock = NSLock()
    private var _recorded: [Record] = []

    var recorded: [Record] {
        lock.lock()
        defer { lock.unlock() }
        return _recorded
    }

    func touch(paths: [String], in containerID: String) async throws {
        lock.lock()
        _recorded.append(Record(containerID: containerID, paths: paths))
        lock.unlock()
    }
}
