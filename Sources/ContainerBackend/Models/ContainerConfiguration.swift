//===----------------------------------------------------------------------===//
// ContainerConfiguration — the full configuration of a container.
//===----------------------------------------------------------------------===//

import Foundation

public struct ContainerConfiguration: Sendable, Codable {
    /// Identifier for the container.
    public var id: String
    /// Image used to create the container.
    public var image: ImageDescription
    /// External mounts to add to the container.
    public var mounts: [Filesystem]
    /// Ports to publish from container to host.
    public var publishedPorts: [PublishPort]
    /// Sockets to publish from container to host.
    public var publishedSockets: [PublishSocket]
    /// Key/Value labels for the container.
    public var labels: [String: String]
    /// System controls for the container.
    public var sysctls: [String: String]
    /// The networks the container will be added to.
    public var networks: [AttachmentConfiguration]
    /// The DNS configuration for the container.
    public var dns: DNSConfiguration?
    /// Whether to enable rosetta x86-64 translation for the container.
    public var rosetta: Bool
    /// Initial or main process of the container.
    public var initProcess: ProcessConfiguration
    /// Platform for the container.
    public var platform: Platform
    /// Resource values for the container.
    public var resources: Resources
    /// Name of the runtime that supports the container.
    public var runtimeHandler: String
    /// Configure exposing virtualization support in the container.
    public var virtualization: Bool
    /// Enable SSH agent socket forwarding from host to container.
    public var ssh: Bool
    /// Whether to mount the rootfs as read-only.
    public var readOnly: Bool
    /// Whether to use a minimal init process inside the container.
    public var useInit: Bool
    /// Linux capabilities to add (normalized CAP_* strings, or "ALL").
    public var capAdd: [String]
    /// Linux capabilities to drop (normalized CAP_* strings, or "ALL").
    public var capDrop: [String]
    /// Size of /dev/shm in bytes. When nil, the default size is used.
    public var shmSize: UInt64?
    /// Signal to send to the container process on stop (from image config).
    public var stopSignal: String?
    /// Paths inside the container to hide from the workload. When nil, the
    /// runtime's default set is used.
    public var maskedPaths: [String]?
    /// Paths inside the container to mark read-only. When nil, the runtime's
    /// default set is used.
    public var readonlyPaths: [String]?
    /// The time at which the container was created.
    public var creationDate: Date

    /// DNS configuration.
    public struct DNSConfiguration: Sendable, Codable {
        public static let defaultNameservers = ["1.1.1.1"]

        public let nameservers: [String]
        public let domain: String?
        public let searchDomains: [String]
        public let options: [String]

        public init(
            nameservers: [String] = defaultNameservers,
            domain: String? = nil,
            searchDomains: [String] = [],
            options: [String] = []
        ) {
            self.nameservers = nameservers
            self.domain = domain
            self.searchDomains = searchDomains
            self.options = options
        }
    }

    /// Resources like cpu, memory, and storage quota. `cpus` and
    /// `memoryInBytes` are optional: when nil they are omitted from the
    /// request and the platform applies its own defaults. This matters
    /// because setting explicit limits on a container that also mounts a
    /// named volume makes the VM configuration invalid (bootstrap fails with
    /// EOPNOTSUPP / "storage device attachment is invalid").
    public struct Resources: Sendable, Codable {
        /// Number of CPU cores allocated.
        public var cpus: Int?
        /// Memory in bytes allocated.
        public var memoryInBytes: UInt64?
        /// Storage quota/size in bytes.
        public var storage: UInt64?
        /// Additional CPU cores allocated for VM overhead (guest agent, etc).
        public var cpuOverhead: Int = 1

        public init() {}

        public init(cpus: Int? = nil, memoryInBytes: UInt64? = nil, storage: UInt64? = nil, cpuOverhead: Int = 1) {
            self.cpus = cpus
            self.memoryInBytes = memoryInBytes
            self.storage = storage
            self.cpuOverhead = cpuOverhead
        }

        enum CodingKeys: String, CodingKey {
            case cpus
            case memoryInBytes
            case storage
            case cpuOverhead
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cpus = try container.decodeIfPresent(Int.self, forKey: .cpus)
            memoryInBytes = try container.decodeIfPresent(UInt64.self, forKey: .memoryInBytes)
            storage = try container.decodeIfPresent(UInt64.self, forKey: .storage)
            cpuOverhead = try container.decodeIfPresent(Int.self, forKey: .cpuOverhead) ?? 1
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case image
        case mounts
        case publishedPorts
        case publishedSockets
        case labels
        case sysctls
        case networks
        case dns
        case rosetta
        case initProcess
        case platform
        case resources
        case runtimeHandler
        case virtualization
        case ssh
        case readOnly
        case useInit
        case capAdd
        case capDrop
        case shmSize
        case stopSignal
        case maskedPaths
        case readonlyPaths
        case creationDate
    }

    /// Create a configuration from the supplied Decoder, initializing missing
    /// values where possible to reasonable defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        image = try container.decode(ImageDescription.self, forKey: .image)
        mounts = try container.decodeIfPresent([Filesystem].self, forKey: .mounts) ?? []
        publishedPorts = try container.decodeIfPresent([PublishPort].self, forKey: .publishedPorts) ?? []
        publishedSockets = try container.decodeIfPresent([PublishSocket].self, forKey: .publishedSockets) ?? []
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        sysctls = try container.decodeIfPresent([String: String].self, forKey: .sysctls) ?? [:]
        networks = try container.decodeIfPresent([AttachmentConfiguration].self, forKey: .networks) ?? []
        dns = try container.decodeIfPresent(DNSConfiguration.self, forKey: .dns)
        rosetta = try container.decodeIfPresent(Bool.self, forKey: .rosetta) ?? false
        initProcess = try container.decode(ProcessConfiguration.self, forKey: .initProcess)
        platform = try container.decodeIfPresent(Platform.self, forKey: .platform) ?? .current
        resources = try container.decodeIfPresent(Resources.self, forKey: .resources) ?? .init()
        runtimeHandler = try container.decodeIfPresent(String.self, forKey: .runtimeHandler) ?? "container-runtime-linux"
        virtualization = try container.decodeIfPresent(Bool.self, forKey: .virtualization) ?? false
        ssh = try container.decodeIfPresent(Bool.self, forKey: .ssh) ?? false
        readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
        useInit = try container.decodeIfPresent(Bool.self, forKey: .useInit) ?? false
        capAdd = try container.decodeIfPresent([String].self, forKey: .capAdd) ?? []
        capDrop = try container.decodeIfPresent([String].self, forKey: .capDrop) ?? []
        shmSize = try container.decodeIfPresent(UInt64.self, forKey: .shmSize)
        stopSignal = try container.decodeIfPresent(String.self, forKey: .stopSignal)
        maskedPaths = try container.decodeIfPresent([String].self, forKey: .maskedPaths)
        readonlyPaths = try container.decodeIfPresent([String].self, forKey: .readonlyPaths)
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate) ?? Date(timeIntervalSince1970: 0)
    }

    public init(
        id: String,
        image: ImageDescription,
        process: ProcessConfiguration,
        mounts: [Filesystem] = [],
        publishedPorts: [PublishPort] = [],
        publishedSockets: [PublishSocket] = [],
        labels: [String: String] = [:],
        sysctls: [String: String] = [:],
        networks: [AttachmentConfiguration] = [],
        dns: DNSConfiguration? = nil,
        rosetta: Bool = false,
        platform: Platform = .current,
        resources: Resources = .init(),
        runtimeHandler: String = "container-runtime-linux",
        virtualization: Bool = false,
        ssh: Bool = false,
        readOnly: Bool = false,
        useInit: Bool = false,
        capAdd: [String] = [],
        capDrop: [String] = [],
        shmSize: UInt64? = nil,
        stopSignal: String? = nil,
        creationDate: Date = Date()
    ) {
        self.id = id
        self.image = image
        self.mounts = mounts
        self.publishedPorts = publishedPorts
        self.publishedSockets = publishedSockets
        self.labels = labels
        self.sysctls = sysctls
        self.networks = networks
        self.dns = dns
        self.rosetta = rosetta
        self.initProcess = process
        self.platform = platform
        self.resources = resources
        self.runtimeHandler = runtimeHandler
        self.virtualization = virtualization
        self.ssh = ssh
        self.readOnly = readOnly
        self.useInit = useInit
        self.capAdd = capAdd
        self.capDrop = capDrop
        self.shmSize = shmSize
        self.stopSignal = stopSignal
        self.maskedPaths = nil
        self.readonlyPaths = nil
        self.creationDate = creationDate
    }
}
