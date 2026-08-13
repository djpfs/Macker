//===----------------------------------------------------------------------===//
// VolumeConfiguration — a named or anonymous volume.
//===----------------------------------------------------------------------===//

import Foundation

/// A named or anonymous volume that can be mounted in containers.
public struct VolumeConfiguration: Sendable, Equatable, Identifiable, Codable {
    /// The ID of the volume (identical to name).
    public var id: String { name }
    /// Name of the volume.
    public var name: String
    /// Driver used to create the volume.
    public var driver: String
    /// Filesystem format of the volume.
    public var format: String
    /// The mount point of the volume on the host.
    public var source: String
    /// Timestamp when the volume was created.
    public var creationDate: Date
    /// User-defined key/value metadata.
    public var labels: [String: String]
    /// Driver-specific options.
    public var options: [String: String]
    /// Size of the volume in bytes (optional).
    public var sizeInBytes: UInt64?

    public init(
        name: String,
        driver: String = "local",
        format: String = "ext4",
        source: String,
        creationDate: Date = Date(),
        labels: [String: String] = [:],
        options: [String: String] = [:],
        sizeInBytes: UInt64? = nil
    ) {
        self.name = name
        self.driver = driver
        self.format = format
        self.source = source
        self.creationDate = creationDate
        self.labels = labels
        self.options = options
        self.sizeInBytes = sizeInBytes
    }

    /// Reserved label key for marking anonymous volumes.
    public static let anonymousLabel = "com.apple.container.resource.anonymous"

    /// Whether this is an anonymous volume (detected via label).
    public var isAnonymous: Bool {
        labels[Self.anonymousLabel] != nil
    }

    enum CodingKeys: String, CodingKey {
        case name
        case driver
        case format
        case source
        case creationDate
        case labels
        case options
        case sizeInBytes
        // Legacy key retained for deserialization compatibility.
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        driver = try container.decode(String.self, forKey: .driver)
        format = try container.decode(String.self, forKey: .format)
        source = try container.decode(String.self, forKey: .source)
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate)
            ?? container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? Date(timeIntervalSince1970: 0)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        options = try container.decodeIfPresent([String: String].self, forKey: .options) ?? [:]
        sizeInBytes = try container.decodeIfPresent(UInt64.self, forKey: .sizeInBytes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(driver, forKey: .driver)
        try container.encode(format, forKey: .format)
        try container.encode(source, forKey: .source)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(labels, forKey: .labels)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(sizeInBytes, forKey: .sizeInBytes)
    }
}
