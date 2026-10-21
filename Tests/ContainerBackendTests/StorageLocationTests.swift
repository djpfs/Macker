//===----------------------------------------------------------------------===//
// StorageLocationTests — moving the runtime store, with temporary folders only.
//===----------------------------------------------------------------------===//

import XCTest
@testable import ContainerBackend

final class StorageLocationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A store at `root/home/com.apple.container` with a few files.
    private func makeStore() throws -> StorageLocation {
        let link = root.appendingPathComponent("home/com.apple.container", isDirectory: true)
        try FileManager.default.createDirectory(at: link.appendingPathComponent("content"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: link.appendingPathComponent("snapshots"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_000).write(to: link.appendingPathComponent("content/blob"))
        try Data(repeating: 2, count: 2_000).write(to: link.appendingPathComponent("snapshots/layer"))
        return StorageLocation(link: link)
    }

    private func makeDestinationParent() throws -> URL {
        let parent = root.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return parent
    }

    func testMoveCopiesVerifiesAndLeavesSymlinkAndBackup() throws {
        let store = try makeStore()
        let parent = try makeDestinationParent()

        let result = try store.move(toParent: parent)

        XCTAssertTrue(store.isRedirected)
        XCTAssertEqual(store.resolvedRoot.standardizedFileURL, result.newRoot.standardizedFileURL)
        XCTAssertEqual(
            try Data(contentsOf: store.link.appendingPathComponent("content/blob")).count, 4_000
        )
        XCTAssertNotNil(store.backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.backup.path))
    }

    func testDeleteBackupRemovesOnlyTheBackup() throws {
        let store = try makeStore()
        let parent = try makeDestinationParent()
        _ = try store.move(toParent: parent)

        try store.deleteBackup()

        XCTAssertNil(store.backup)
        XCTAssertTrue(store.isRedirected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.link.appendingPathComponent("content/blob").path))
    }

    func testFailedCopyRestoresTheOriginal() throws {
        let store = try makeStore()
        let parent = try makeDestinationParent()
        struct Boom: Error {}

        XCTAssertThrowsError(try store.move(toParent: parent, copy: { _, _ in throw Boom() })) { error in
            guard case StorageLocationError.copyFailed = error else {
                return XCTFail("expected copyFailed, got \(error)")
            }
        }

        XCTAssertFalse(store.isRedirected)
        XCTAssertNil(store.backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.link.appendingPathComponent("content/blob").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent("com.apple.container").path))
    }

    func testIncompleteCopyIsRejectedAndCleanedUp() throws {
        let store = try makeStore()
        let parent = try makeDestinationParent()

        // A copy that drops one file.
        let partial: (URL, URL) throws -> Void = { source, destination in
            try FileManager.default.createDirectory(at: destination.appendingPathComponent("content"), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 10).write(to: destination.appendingPathComponent("content/blob"))
        }

        XCTAssertThrowsError(try store.move(toParent: parent, copy: partial)) { error in
            guard case StorageLocationError.sizeMismatch = error else {
                return XCTFail("expected sizeMismatch, got \(error)")
            }
        }
        XCTAssertFalse(store.isRedirected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent("com.apple.container").path))
    }

    func testMissingDestinationIsRefused() throws {
        let store = try makeStore()
        let missing = root.appendingPathComponent("not-mounted", isDirectory: true)

        XCTAssertThrowsError(try store.move(toParent: missing)) { error in
            guard case StorageLocationError.destinationMissing = error else {
                return XCTFail("expected destinationMissing, got \(error)")
            }
        }
        XCTAssertFalse(store.isRedirected)
    }

    func testAlreadyRedirectedIsRefused() throws {
        let store = try makeStore()
        let parent = try makeDestinationParent()
        _ = try store.move(toParent: parent)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        XCTAssertThrowsError(try store.move(toParent: second)) { error in
            guard case StorageLocationError.alreadyRedirected = error else {
                return XCTFail("expected alreadyRedirected, got \(error)")
            }
        }
    }

    func testRestoreBackupPutsTheOriginalBack() throws {
        let store = try makeStore()
        let parent = try makeDestinationParent()
        _ = try store.move(toParent: parent)

        try store.restoreBackup()

        XCTAssertFalse(store.isRedirected)
        XCTAssertNil(store.backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.link.appendingPathComponent("content/blob").path))
    }

    func testSizesReportAllocatedSpacePerFolder() throws {
        let store = try makeStore()

        let sizes = Dictionary(uniqueKeysWithValues: store.sizes().map { ($0.name, $0.bytes) })

        // Allocated space is at least the logical size, and comes in whole blocks.
        XCTAssertGreaterThanOrEqual(sizes["content"] ?? 0, 4_000)
        XCTAssertGreaterThanOrEqual(sizes["snapshots"] ?? 0, 2_000)
        XCTAssertEqual(Set(sizes.keys), ["content", "snapshots"])
    }
}
