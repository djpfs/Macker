//===----------------------------------------------------------------------===//
// Platform + Descriptor — lightweight reimplementations of the OCI types from
// apple/containerization (ContainerizationOCI). JSON-compatible with the
// originals so decoding daemon payloads works.
//===----------------------------------------------------------------------===//

import Foundation

/// Platform describes the platform which the image in the manifest runs on.
/// Encodes as `{ "os": ..., "architecture": ..., "variant": ... }`.
public struct Platform: Sendable, Equatable, Hashable, Codable {
    public var architecture: String
    public var os: String
    public var osVersion: String?
    public var osFeatures: [String]?
    public var variant: String?

    public init(
        arch: String,
        os: String,
        osVersion: String? = nil,
        osFeatures: [String]? = nil,
        variant: String? = nil
    ) {
        self.architecture = Platform.normalizeArch(arch).arch
        self.os = os
        self.osVersion = osVersion
        self.osFeatures = osFeatures
        self.variant = variant ?? Platform.normalizeArch(arch).variant
    }

    /// The current machine's platform (arm64/linux on Apple Silicon).
    public static var current: Platform {
        var systemInfo = utsname()
        uname(&systemInfo)
        let arch = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return .init(arch: arch, os: "linux")
    }

    public var description: String {
        if let variant, !Self.isRedundantVariant(variant, for: architecture) {
            return "\(os)/\(architecture)/\(variant)"
        }
        return "\(os)/\(architecture)"
    }

    private static func isRedundantVariant(_ variant: String, for architecture: String) -> Bool {
        architecture == "arm64" && variant == "v8"
    }

    private static func normalizeArch(_ raw: String) -> (arch: String, variant: String?) {
        switch raw {
        case "aarch64", "arm64":
            return ("arm64", "v8")
        case "x86_64", "x86-64", "amd64":
            return ("amd64", nil)
        case "arm", "armhf", "armel":
            return ("arm", "v7")
        default:
            return (raw, nil)
        }
    }

    enum CodingKeys: String, CodingKey {
        case os
        case architecture
        case variant
        case osVersion
        case osFeatures
    }
}

/// OCI content descriptor.
public struct Descriptor: Codable, Sendable, Equatable {
    public let mediaType: String
    public let digest: String
    public let size: Int64
    public let urls: [String]?
    public var annotations: [String: String]?
    public var platform: Platform?
    public let artifactType: String?

    public init(
        mediaType: String,
        digest: String,
        size: Int64,
        urls: [String]? = nil,
        annotations: [String: String]? = nil,
        platform: Platform? = nil,
        artifactType: String? = nil
    ) {
        self.mediaType = mediaType
        self.digest = digest
        self.size = size
        self.urls = urls
        self.annotations = annotations
        self.platform = platform
        self.artifactType = artifactType
    }
}

/// A type that represents an OCI image reference usable with containers.
public struct ImageDescription: Sendable, Codable {
    /// The public reference/name of the image (e.g. "nginx:latest").
    public let reference: String
    /// The descriptor of the image.
    public let descriptor: Descriptor

    public var digest: String { descriptor.digest }
    public var mediaType: String { descriptor.mediaType }

    public init(reference: String, descriptor: Descriptor) {
        self.reference = reference
        self.descriptor = descriptor
    }
}
