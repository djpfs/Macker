//===----------------------------------------------------------------------===//
// StorageLocation — where the container runtime keeps images, layers,
// containers, volumes and the build cache.
//
// The runtime uses one root directory (CONTAINER_APP_ROOT, default
// ~/Library/Application Support/com.apple.container). To move it, the data is
// copied to a new parent folder, verified, and the default path is replaced by
// a symlink to the copy. The original is kept as "<name>.bak" until the caller
// deletes it. The CLI and the daemon both follow the symlink, so no environment
// variable is needed for the CLI.
//
// This type only moves files. Stopping and starting the daemon is the caller's
// job, and must happen before `move` runs.
//===----------------------------------------------------------------------===//

import Foundation

public enum StorageLocationError: LocalizedError, Equatable {
    case alreadyRedirected(String)
    case destinationMissing(String)
    case destinationExists(String)
    case notEnoughSpace(needed: UInt64, available: UInt64)
    case backupExists(String)
    case copyFailed(String)
    case sizeMismatch(expected: UInt64, actual: UInt64)

    public var errorDescription: String? {
        switch self {
        case .alreadyRedirected(let target):
            "Storage already points to \(target). Restore the default location before moving it again."
        case .destinationMissing(let path):
            "The destination folder does not exist: \(path). If it is on an external disk, connect it first."
        case .destinationExists(let path):
            "Something already exists at \(path). Choose another folder."
        case .notEnoughSpace(let needed, let available):
            "Not enough free space at the destination: \(needed) bytes needed, \(available) available."
        case .backupExists(let path):
            "A backup already exists at \(path). Delete it before moving the storage again."
        case .copyFailed(let detail):
            "Copying the storage failed: \(detail)"
        case .sizeMismatch(let expected, let actual):
            "The copy is incomplete: expected \(expected) bytes, found \(actual)."
        }
    }
}

/// The result of a successful move.
public struct StorageMoveResult: Sendable, Equatable {
    /// Where the data lives now (the target of the symlink).
    public let newRoot: URL
    /// The original folder, kept until the caller removes it.
    public let backup: URL
}

public struct StorageLocation: Sendable {
    /// The path the runtime and the CLI use: the real folder, or a symlink to it.
    public let link: URL

    public init(link: URL) {
        self.link = link
    }

    /// The default runtime root.
    public static var standard: StorageLocation {
        StorageLocation(link: defaultRoot)
    }

    /// `~/Library/Application Support/com.apple.container`.
    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.apple.container", isDirectory: true)
    }

    /// True when the default path is a symlink to another folder. Asks the file
    /// manager directly: `URL.resourceValues` caches its answer on the URL instance.
    public var isRedirected: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil
    }

    /// The folder that actually holds the data.
    public var resolvedRoot: URL {
        link.resolvingSymlinksInPath()
    }

    /// Space used by each top-level folder of the store (allocated blocks, so
    /// sparse disk images count only what they occupy), largest first.
    public func sizes() -> [(name: String, bytes: UInt64)] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: resolvedRoot, includingPropertiesForKeys: nil)) ?? []
        return entries
            .map { (name: $0.lastPathComponent, bytes: Self.allocatedSize($0)) }
            .sorted { $0.bytes > $1.bytes }
    }

    /// The backup folder that `move` leaves behind, if one exists.
    public var backup: URL? {
        let url = link.deletingLastPathComponent().appendingPathComponent(link.lastPathComponent + ".bak", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Copies the store into `parent/<name>`, verifies the copy, and swaps the
    /// default path for a symlink to it. On any failure the original is put
    /// back and the partial copy is removed.
    public func move(
        toParent parent: URL,
        copy: (URL, URL) throws -> Void = StorageLocation.dittoCopy
    ) throws -> StorageMoveResult {
        let fm = FileManager.default
        if isRedirected {
            throw StorageLocationError.alreadyRedirected(resolvedRoot.path)
        }
        guard fm.fileExists(atPath: parent.path) else {
            throw StorageLocationError.destinationMissing(parent.path)
        }
        let destination = parent.appendingPathComponent(link.lastPathComponent, isDirectory: true)
        guard !fm.fileExists(atPath: destination.path) else {
            throw StorageLocationError.destinationExists(destination.path)
        }
        let backupURL = link.deletingLastPathComponent()
            .appendingPathComponent(link.lastPathComponent + ".bak", isDirectory: true)
        guard !fm.fileExists(atPath: backupURL.path) else {
            throw StorageLocationError.backupExists(backupURL.path)
        }

        let source = link
        let needed = Self.directorySize(source)
        let available = Self.availableCapacity(at: parent)
        // A safety margin: the copy also needs room for metadata.
        let required = needed + needed / 10
        guard available >= required else {
            throw StorageLocationError.notEnoughSpace(needed: required, available: available)
        }

        do {
            try copy(source, destination)
        } catch {
            try? fm.removeItem(at: destination)
            throw StorageLocationError.copyFailed(error.localizedDescription)
        }

        let copied = Self.directorySize(destination)
        guard copied == needed else {
            try? fm.removeItem(at: destination)
            throw StorageLocationError.sizeMismatch(expected: needed, actual: copied)
        }

        do {
            try fm.moveItem(at: source, to: backupURL)
        } catch {
            try? fm.removeItem(at: destination)
            throw StorageLocationError.copyFailed("could not set the original aside: \(error.localizedDescription)")
        }
        do {
            try fm.createSymbolicLink(at: link, withDestinationURL: destination)
        } catch {
            // Put the original back so the runtime still finds its data.
            try? fm.moveItem(at: backupURL, to: source)
            try? fm.removeItem(at: destination)
            throw StorageLocationError.copyFailed("could not create the link: \(error.localizedDescription)")
        }
        return StorageMoveResult(newRoot: destination, backup: backupURL)
    }

    /// Puts the original back: removes the symlink and renames the backup to the
    /// default path. Does nothing when the store is not redirected.
    public func restoreBackup() throws {
        guard isRedirected, let backup else { return }
        try FileManager.default.removeItem(at: link)
        try FileManager.default.moveItem(at: backup, to: link)
    }

    /// The environment variable the runtime reads for its root folder.
    public static let environmentName = "CONTAINER_APP_ROOT"

    /// Deletes the backup left by `move`. Only call this after the moved storage
    /// has been checked.
    public func deleteBackup() throws {
        guard let backup else { return }
        try FileManager.default.removeItem(at: backup)
    }

    /// Copies a folder with `ditto`, which keeps sparse files and attributes.
    public static func dittoCopy(from source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [source.path, destination.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw StorageLocationError.copyFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Space occupied on disk by the files under `url`.
    static func allocatedSize(_ url: URL) -> UInt64 {
        totalSize(url, keys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) { values in
            UInt64(values.totalFileAllocatedSize ?? 0)
        }
    }

    /// Logical size of the files under `url`, in bytes. Used to check a copy,
    /// since both sides of the comparison are counted the same way.
    static func directorySize(_ url: URL) -> UInt64 {
        totalSize(url, keys: [.fileSizeKey, .isRegularFileKey]) { values in
            UInt64(values.fileSize ?? 0)
        }
    }

    private static func totalSize(
        _ url: URL,
        keys: Set<URLResourceKey>,
        bytes: (URLResourceValues) -> UInt64
    ) -> UInt64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return bytes((try? url.resourceValues(forKeys: keys)) ?? URLResourceValues())
        }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += bytes(values)
        }
        return total
    }

    static func availableCapacity(at url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return UInt64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}
