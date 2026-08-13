//===----------------------------------------------------------------------===//
// Networking types — port publishing, sockets, and small address wrappers.
//===----------------------------------------------------------------------===//

import Foundation

/// A network address. Encodes/decodes as a plain string (e.g. "0.0.0.0").
public struct IPAddress: Sendable, Codable, Equatable, Hashable, CustomStringConvertible {
    public let rawValue: String
    public var description: String { rawValue }

    public init(_ raw: String) {
        self.rawValue = raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// An IPv4 CIDR block. Encodes/decodes as a string like "10.0.0.0/24".
public struct CIDRv4: Sendable, Codable, Equatable, Hashable, CustomStringConvertible {
    public let rawValue: String
    public var description: String { rawValue }

    public init(_ raw: String) {
        self.rawValue = raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// An IPv6 CIDR block. Encodes/decodes as a string.
public struct CIDRv6: Sendable, Codable, Equatable, Hashable, CustomStringConvertible {
    public let rawValue: String
    public var description: String { rawValue }

    public init(_ raw: String) {
        self.rawValue = raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A MAC address. Encodes/decodes as a string like "aa:bb:cc:dd:ee:ff".
public struct MACAddress: Sendable, Codable, Equatable, Hashable, CustomStringConvertible {
    public let rawValue: String
    public var description: String { rawValue }

    public init(_ raw: String) {
        self.rawValue = raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The network protocols available for port forwarding.
public enum PublishProtocol: String, Sendable, Codable {
    case tcp = "tcp"
    case udp = "udp"

    public init() {
        self = .tcp
    }

    public init?(_ value: String) {
        switch value.lowercased() {
        case "tcp": self = .tcp
        case "udp": self = .udp
        default: return nil
        }
    }
}

/// Specifies internet port forwarding from host to container.
public struct PublishPort: Sendable, Codable {
    /// The IP address of the proxy listener on the host.
    public var hostAddress: IPAddress
    /// The port number of the proxy listener on the host.
    public var hostPort: UInt16
    /// The port number of the container listener.
    public var containerPort: UInt16
    /// The network protocol for the proxy.
    public var proto: PublishProtocol
    /// The number of ports to publish.
    public var count: UInt16

    public init(hostAddress: IPAddress, hostPort: UInt16, containerPort: UInt16, proto: PublishProtocol, count: UInt16) {
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.proto = proto
        self.count = count
    }
}

/// Represents a socket that should be published from container to host.
public struct PublishSocket: Sendable, Codable {
    /// Absolute path to the socket inside the container.
    public var containerPath: String
    /// Absolute path where the socket appears on the host.
    public var hostPath: String
    /// File permissions for the socket on the host.
    public var permissions: String?

    public init(containerPath: String, hostPath: String, permissions: String? = nil) {
        self.containerPath = containerPath
        self.hostPath = hostPath
        self.permissions = permissions
    }
}
