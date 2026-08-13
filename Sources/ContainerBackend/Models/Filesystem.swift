//===----------------------------------------------------------------------===//
// Filesystem — a host filesystem attached to a sandbox/container.
//===----------------------------------------------------------------------===//

import Foundation

/// Options passed to a mount call.
public typealias MountOptions = [String]

extension MountOptions {
    /// Returns true if the Filesystem should be consumed as read-only.
    public var readonly: Bool { contains("ro") }
}

/// A host filesystem that will be attached to the sandbox for use.
public struct Filesystem: Sendable, Codable, Equatable {
    /// Type of caching to perform at the host level.
    public enum CacheMode: Sendable, Codable {
        case on
        case off
        case auto
    }

    /// Sync mode to perform at the host level.
    public enum SyncMode: Sendable, Codable {
        case full
        case fsync
        case nosync
    }

    /// The type of filesystem attachment for the sandbox.
    public enum FSType: Sendable, Codable, Equatable {
        /// Virtiofs share type.
        public enum VirtiofsType: String, Sendable, Codable, Equatable {
            /// A virtiofs share for the rootfs of a sandbox.
            case rootfs
            /// Data share — everything besides the rootfs.
            case data
        }

        case block(format: String, cache: CacheMode, sync: SyncMode)
        case volume(name: String, format: String, cache: CacheMode, sync: SyncMode)
        case virtiofs
        case tmpfs
    }

    /// Type of the filesystem.
    public var type: FSType
    /// Source of the filesystem.
    public var source: String
    /// Destination where the filesystem should be mounted.
    public var destination: String
    /// Mount options applied when mounting the filesystem.
    public var options: MountOptions

    public init(type: FSType, source: String, destination: String, options: MountOptions) {
        self.type = type
        self.source = source
        self.destination = destination
        self.options = options
    }

    public static func block(
        format: String,
        source: String,
        destination: String,
        options: MountOptions,
        cache: CacheMode = .on,
        sync: SyncMode = .fsync
    ) -> Filesystem {
        .init(
            type: .block(format: format, cache: cache, sync: sync),
            source: absolute(source),
            destination: destination,
            options: options
        )
    }

    /// A named volume filesystem.
    public static func volume(
        name: String,
        format: String,
        source: String,
        destination: String,
        options: MountOptions,
        cache: CacheMode = .on,
        sync: SyncMode = .fsync
    ) -> Filesystem {
        .init(
            type: .volume(name: name, format: format, cache: cache, sync: sync),
            source: absolute(source),
            destination: destination,
            options: options
        )
    }

    /// A virtiofs-backed filesystem providing a directory.
    public static func virtiofs(source: String, destination: String, options: MountOptions) -> Filesystem {
        .init(
            type: .virtiofs,
            source: absolute(source),
            destination: destination,
            options: options
        )
    }

    public static func tmpfs(destination: String, options: MountOptions) -> Filesystem {
        .init(
            type: .tmpfs,
            source: "tmpfs",
            destination: destination,
            options: options
        )
    }

    public var isBlock: Bool {
        switch type {
        case .block: true
        case .volume: true
        default: false
        }
    }

    public var isVolume: Bool {
        if case .volume = type { return true }
        return false
    }

    public var volumeName: String? {
        switch type {
        case .volume(let name, _, _, _): name
        default: nil
        }
    }

    public var isTmpfs: Bool {
        if case .tmpfs = type { return true }
        return false
    }

    public var isVirtiofs: Bool {
        if case .virtiofs = type { return true }
        return false
    }

    private static func absolute(_ path: String) -> String {
        let resolved = NSString(string: path).expandingTildeInPath
        return (resolved as NSString).standardizingPath
    }
}
