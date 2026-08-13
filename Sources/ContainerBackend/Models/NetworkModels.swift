//===----------------------------------------------------------------------===//
// Network models — network resources, configurations, attachments.
//===----------------------------------------------------------------------===//

import Foundation

/// Networking mode that applies to client containers.
public enum NetworkMode: String, Codable, Sendable {
    /// NAT networking mode. Containers do not have routable IPs; the host
    /// performs network address translation to reach external services.
    case nat = "nat"
    /// Host-only networking mode. Containers can talk with each other in the
    /// same subnet only.
    case hostOnly = "hostOnly"

    public init() {
        self = .nat
    }
}

/// The status of a network at runtime.
public struct NetworkStatus: Codable, Sendable {
    /// The IPv4 subnet assigned to the network, if one was allocated.
    public var ipv4Subnet: String?
    /// The IPv6 subnet assigned to the network, if one was allocated.
    public var ipv6Subnet: String?
    /// The network's gateway address.
    public var gateway: String?
    /// The network's primary DNS address.
    public var dns: String?
    /// The network's domain name.
    public var domain: String?
    /// Whether the network is currently up.
    public var isUp: Bool?

    public init(
        ipv4Subnet: String? = nil,
        ipv6Subnet: String? = nil,
        gateway: String? = nil,
        dns: String? = nil,
        domain: String? = nil,
        isUp: Bool? = nil
    ) {
        self.ipv4Subnet = ipv4Subnet
        self.ipv6Subnet = ipv6Subnet
        self.gateway = gateway
        self.dns = dns
        self.domain = domain
        self.isUp = isUp
    }

    enum CodingKeys: String, CodingKey {
        case ipv4Subnet
        case ipv6Subnet
        case gateway
        case dns
        case domain
        case isUp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ipv4Subnet = try container.decodeIfPresent(String.self, forKey: .ipv4Subnet)
        ipv6Subnet = try container.decodeIfPresent(String.self, forKey: .ipv6Subnet)
        gateway = try container.decodeIfPresent(String.self, forKey: .gateway)
        dns = try container.decodeIfPresent(String.self, forKey: .dns)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        isUp = try container.decodeIfPresent(Bool.self, forKey: .isUp)
    }
}

/// Configuration parameters for network creation.
public struct NetworkConfiguration: Codable, Sendable, Identifiable {
    /// The name of the network.
    public let name: String
    /// The unique identifier for the network. Identical to ``name``.
    public var id: String { name }
    /// The network type.
    public let mode: NetworkMode
    /// When the network was created.
    public let creationDate: Date
    /// The preferred CIDR address for the IPv4 subnet, if specified.
    public let ipv4Subnet: String?
    /// The preferred CIDR address for the IPv6 subnet, if specified.
    public let ipv6Subnet: String?
    /// Key-value labels for the network.
    public let labels: [String: String]
    /// The network plugin that manages this network.
    public let plugin: String
    /// Plugin-specific options for this network.
    public let options: [String: String]

    public init(
        name: String,
        mode: NetworkMode = .nat,
        ipv4Subnet: String? = nil,
        ipv6Subnet: String? = nil,
        labels: [String: String] = [:],
        plugin: String,
        options: [String: String] = [:]
    ) {
        self.name = name
        self.mode = mode
        self.creationDate = Date()
        self.ipv4Subnet = ipv4Subnet
        self.ipv6Subnet = ipv6Subnet
        self.labels = labels
        self.plugin = plugin
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case name
        case id
        case creationDate
        case mode
        case ipv4Subnet
        case ipv6Subnet
        case labels
        case plugin
        case options
        case subnet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? container.decode(String.self, forKey: .id)
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate) ?? Date(timeIntervalSince1970: 0)
        mode = try container.decode(NetworkMode.self, forKey: .mode)
        ipv4Subnet = try container.decodeIfPresent(String.self, forKey: .ipv4Subnet)
            ?? container.decodeIfPresent(String.self, forKey: .subnet)
        ipv6Subnet = try container.decodeIfPresent(String.self, forKey: .ipv6Subnet)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        plugin = try container.decodeIfPresent(String.self, forKey: .plugin) ?? "vmnet"
        options = try container.decodeIfPresent([String: String].self, forKey: .options) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(ipv4Subnet, forKey: .ipv4Subnet)
        try container.encodeIfPresent(ipv6Subnet, forKey: .ipv6Subnet)
        try container.encode(labels, forKey: .labels)
        try container.encode(plugin, forKey: .plugin)
        try container.encode(options, forKey: .options)
    }
}

/// A network resource: its persistent configuration plus runtime status.
public struct NetworkResource: Codable, Sendable, Identifiable {
    /// The network's configuration.
    public let configuration: NetworkConfiguration
    /// The network's runtime status.
    public let status: NetworkStatus

    public var id: String { configuration.name }
    public var name: String { configuration.name }
    public var creationDate: Date { configuration.creationDate }
    public var labels: [String: String] { configuration.labels }

    public init(configuration: NetworkConfiguration, status: NetworkStatus) {
        self.configuration = configuration
        self.status = status
    }
}

/// A snapshot of a network interface for a sandbox.
public struct Attachment: Codable, Sendable {
    /// The network ID associated with the attachment.
    public let network: String
    /// The hostname associated with the attachment.
    public let hostname: String
    /// The CIDR address describing the interface IPv4 address.
    public let ipv4Address: String
    /// The IPv4 gateway address.
    public let ipv4Gateway: String
    /// The CIDR address describing the interface IPv6 address, if any.
    public let ipv6Address: String?
    /// The MAC address associated with the attachment, if any.
    public let macAddress: String?
    /// The MTU for the network interface.
    public let mtu: UInt32?
    /// The network plugin variant.
    public let variant: String?

    public init(
        network: String,
        hostname: String,
        ipv4Address: String,
        ipv4Gateway: String,
        ipv6Address: String? = nil,
        macAddress: String? = nil,
        mtu: UInt32? = nil,
        variant: String? = nil
    ) {
        self.network = network
        self.hostname = hostname
        self.ipv4Address = ipv4Address
        self.ipv4Gateway = ipv4Gateway
        self.ipv6Address = ipv6Address
        self.macAddress = macAddress
        self.mtu = mtu
        self.variant = variant
    }

    enum CodingKeys: String, CodingKey {
        case network
        case hostname
        case ipv4Address
        case ipv4Gateway
        case ipv6Address
        case macAddress
        case mtu
        case variant
        // Legacy keys retained for deserialization compatibility.
        case address
        case gateway
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network = try container.decode(String.self, forKey: .network)
        hostname = try container.decode(String.self, forKey: .hostname)
        ipv4Address = try container.decodeIfPresent(String.self, forKey: .ipv4Address)
            ?? container.decode(String.self, forKey: .address)
        ipv4Gateway = try container.decodeIfPresent(String.self, forKey: .ipv4Gateway)
            ?? container.decode(String.self, forKey: .gateway)
        ipv6Address = try container.decodeIfPresent(String.self, forKey: .ipv6Address)
        macAddress = try container.decodeIfPresent(String.self, forKey: .macAddress)
        mtu = try container.decodeIfPresent(UInt32.self, forKey: .mtu)
        variant = try container.decodeIfPresent(String.self, forKey: .variant)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network, forKey: .network)
        try container.encode(hostname, forKey: .hostname)
        try container.encode(ipv4Address, forKey: .ipv4Address)
        try container.encode(ipv4Gateway, forKey: .ipv4Gateway)
        try container.encodeIfPresent(ipv6Address, forKey: .ipv6Address)
        try container.encodeIfPresent(macAddress, forKey: .macAddress)
        try container.encodeIfPresent(mtu, forKey: .mtu)
        try container.encodeIfPresent(variant, forKey: .variant)
    }
}

/// A request to attach a container to a network.
public struct AttachmentConfiguration: Codable, Sendable {
    /// The network to attach to.
    public let network: String
    /// The option information for the attachment.
    public let options: AttachmentOptions

    public init(network: String, options: AttachmentOptions = .init()) {
        self.network = network
        self.options = options
    }
}

/// Option information for a network attachment.
public struct AttachmentOptions: Codable, Sendable {
    /// The hostname associated with the attachment.
    public let hostname: String
    /// The MAC address associated with the attachment (optional).
    public let macAddress: MACAddress?
    /// The MTU for the network interface.
    public let mtu: UInt32?

    public init(hostname: String = "", macAddress: MACAddress? = nil, mtu: UInt32? = nil) {
        self.hostname = hostname
        self.macAddress = macAddress
        self.mtu = mtu
    }
}
