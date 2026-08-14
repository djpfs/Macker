//===----------------------------------------------------------------------===//
// ComposeModels — the Compose file model.
//
// These types decode directly from a docker-compose.yml via Yams' YAMLDecoder.
// Where the Compose spec allows two shapes for the same field (e.g.
// `depends_on` as a list or a map, `environment` as a list or a map) a custom
// decoder normalizes to a single Swift type.
//===----------------------------------------------------------------------===//

import Foundation

/// A parsed Compose project: the top-level `name`, `services`, `networks`,
/// `volumes`, `configs` and `secrets` sections.
public struct ComposeProject: Sendable, Codable, Equatable {
    /// The project name. Defaults to the directory name of the compose file.
    public var name: String
    /// The services defined in the file.
    public var services: [String: ServiceConfig]
    /// The networks defined in the file.
    public var networks: [String: NetworkConfig]
    /// The volumes defined in the file.
    public var volumes: [String: VolumeConfig]
    /// The configs defined in the file.
    public var configs: [String: ConfigConfig]
    /// The secrets defined in the file.
    public var secrets: [String: SecretConfig]

    public init(
        name: String,
        services: [String: ServiceConfig],
        networks: [String: NetworkConfig] = [:],
        volumes: [String: VolumeConfig] = [:],
        configs: [String: ConfigConfig] = [:],
        secrets: [String: SecretConfig] = [:]
    ) {
        self.name = name
        self.services = services
        self.networks = networks
        self.volumes = volumes
        self.configs = configs
        self.secrets = secrets
    }

    enum CodingKeys: String, CodingKey {
        case name
        case services
        case networks
        case volumes
        case configs
        case secrets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        services = try container.decodeIfPresent([String: ServiceConfig].self, forKey: .services) ?? [:]
        networks = try container.decodeIfPresent([String: NetworkConfig].self, forKey: .networks) ?? [:]
        volumes = try container.decodeIfPresent([String: VolumeConfig].self, forKey: .volumes) ?? [:]
        configs = try container.decodeIfPresent([String: ConfigConfig].self, forKey: .configs) ?? [:]
        secrets = try container.decodeIfPresent([String: SecretConfig].self, forKey: .secrets) ?? [:]
    }
}

/// A single service definition.
public struct ServiceConfig: Sendable, Codable, Equatable {
    /// The image to run, e.g. `nginx:latest`.
    public var image: String?
    /// Build context/configuration.
    public var build: BuildConfig?
    /// Override the image's default command.
    public var command: [String]?
    /// Override the image's default entrypoint.
    public var entrypoint: [String]?
    /// Environment variables, normalized to a dictionary.
    public var environment: [String: String]
    /// Environment files to load.
    public var envFile: [String]
    /// Port mappings, e.g. `"8080:80"`.
    public var ports: [String]
    /// Ports to expose without publishing.
    public var expose: [String]
    /// Volume mounts, e.g. `"./html:/usr/share/nginx/html:ro"`.
    public var volumes: [String]
    /// Named secrets referenced by this service.
    public var secrets: [String]
    /// Named configs referenced by this service.
    public var configs: [String]
    /// Networks this service joins.
    public var networks: [String]
    /// Services this service depends on, with their conditions.
    public var dependsOn: [String: DependsOnCondition]
    /// Health check configuration.
    public var healthcheck: HealthCheckConfig?
    /// Restart policy: `no`, `always`, `on-failure`, `unless-stopped`.
    public var restart: String?
    /// Labels applied to the container.
    public var labels: [String: String]
    /// A fixed container name (instead of `<project>-<service>-1`).
    public var containerName: String?
    /// The container hostname.
    public var hostname: String?
    /// User to run the process as, e.g. `"1000:1000"`.
    public var user: String?
    /// Working directory inside the container.
    public var workingDir: String?
    /// CPU limit (fractional cores).
    public var cpus: Double?
    /// Memory limit, e.g. `"512m"`.
    public var memory: String?
    /// Profiles that gate this service.
    public var profiles: [String]
    /// Run with elevated privileges.
    public var privileged: Bool
    /// Mount the rootfs read-only.
    public var readOnly: Bool
    /// Use an init process inside the container.
    public var initEnabled: Bool
    /// Signal to stop the container with.
    public var stopSignal: String?
    /// Extra hosts to add to /etc/hosts (`"host:ip"`).
    public var extraHosts: [String]
    /// DNS servers.
    public var dns: [String]
    /// Linux capabilities to add.
    public var capAdd: [String]
    /// Linux capabilities to drop.
    public var capDrop: [String]
    /// Size of /dev/shm.
    public var shmSize: String?
    /// Keep stdin open.
    public var stdinOpen: Bool
    /// Allocate a TTY.
    public var tty: Bool
    /// Number of replicas (only 1 is supported).
    public var scale: Int
    /// Deploy section (resources limits).
    public var deploy: DeployConfig?

    public init(
        image: String? = nil,
        build: BuildConfig? = nil,
        command: [String]? = nil,
        entrypoint: [String]? = nil,
        environment: [String: String] = [:],
        envFile: [String] = [],
        ports: [String] = [],
        expose: [String] = [],
        volumes: [String] = [],
        secrets: [String] = [],
        configs: [String] = [],
        networks: [String] = [],
        dependsOn: [String: DependsOnCondition] = [:],
        healthcheck: HealthCheckConfig? = nil,
        restart: String? = nil,
        labels: [String: String] = [:],
        containerName: String? = nil,
        hostname: String? = nil,
        user: String? = nil,
        workingDir: String? = nil,
        cpus: Double? = nil,
        memory: String? = nil,
        profiles: [String] = [],
        privileged: Bool = false,
        readOnly: Bool = false,
        initEnabled: Bool = false,
        stopSignal: String? = nil,
        extraHosts: [String] = [],
        dns: [String] = [],
        capAdd: [String] = [],
        capDrop: [String] = [],
        shmSize: String? = nil,
        stdinOpen: Bool = false,
        tty: Bool = false,
        scale: Int = 1,
        deploy: DeployConfig? = nil
    ) {
        self.image = image
        self.build = build
        self.command = command
        self.entrypoint = entrypoint
        self.environment = environment
        self.envFile = envFile
        self.ports = ports
        self.expose = expose
        self.volumes = volumes
        self.secrets = secrets
        self.configs = configs
        self.networks = networks
        self.dependsOn = dependsOn
        self.healthcheck = healthcheck
        self.restart = restart
        self.labels = labels
        self.containerName = containerName
        self.hostname = hostname
        self.user = user
        self.workingDir = workingDir
        self.cpus = cpus
        self.memory = memory
        self.profiles = profiles
        self.privileged = privileged
        self.readOnly = readOnly
        self.initEnabled = initEnabled
        self.stopSignal = stopSignal
        self.extraHosts = extraHosts
        self.dns = dns
        self.capAdd = capAdd
        self.capDrop = capDrop
        self.shmSize = shmSize
        self.stdinOpen = stdinOpen
        self.tty = tty
        self.scale = scale
        self.deploy = deploy
    }

    enum CodingKeys: String, CodingKey {
        case image
        case build
        case command
        case entrypoint
        case environment
        case envFile = "env_file"
        case ports
        case expose
        case volumes
        case secrets
        case configs
        case networks
        case dependsOn = "depends_on"
        case healthcheck
        case restart
        case labels
        case containerName = "container_name"
        case hostname
        case user
        case workingDir = "working_dir"
        case cpus
        case memory
        case profiles
        case privileged
        case readOnly = "read_only"
        case initEnabled = "init"
        case stopSignal = "stop_signal"
        case extraHosts = "extra_hosts"
        case dns
        case capAdd = "cap_add"
        case capDrop = "cap_drop"
        case shmSize = "shm_size"
        case stdinOpen = "stdin_open"
        case tty
        case scale
        case deploy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        build = try c.decodeIfPresent(BuildConfig.self, forKey: .build)
        command = try c.decodeIfPresent(CommandList.self, forKey: .command)?.values
        entrypoint = try c.decodeIfPresent(CommandList.self, forKey: .entrypoint)?.values
        environment = try c.decodeIfPresent(EnvironmentMap.self, forKey: .environment)?.values ?? [:]
        envFile = try c.decodeIfPresent([String].self, forKey: .envFile) ?? []
        ports = try c.decodeIfPresent(PortList.self, forKey: .ports)?.values ?? []
        expose = try c.decodeIfPresent([String].self, forKey: .expose) ?? []
        volumes = try c.decodeIfPresent([String].self, forKey: .volumes) ?? []
        secrets = try c.decodeIfPresent(StringOrList.self, forKey: .secrets)?.values ?? []
        configs = try c.decodeIfPresent(StringOrList.self, forKey: .configs)?.values ?? []
        networks = try c.decodeIfPresent(NetworkList.self, forKey: .networks)?.names ?? []
        dependsOn = try c.decodeIfPresent(DependsOnMap.self, forKey: .dependsOn)?.conditions ?? [:]
        healthcheck = try c.decodeIfPresent(HealthCheckConfig.self, forKey: .healthcheck)
        restart = try c.decodeIfPresent(String.self, forKey: .restart)
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        containerName = try c.decodeIfPresent(String.self, forKey: .containerName)
        hostname = try c.decodeIfPresent(String.self, forKey: .hostname)
        user = try c.decodeIfPresent(String.self, forKey: .user)
        workingDir = try c.decodeIfPresent(String.self, forKey: .workingDir)
        cpus = try c.decodeIfPresent(Double.self, forKey: .cpus)
        memory = try c.decodeIfPresent(String.self, forKey: .memory)
        profiles = try c.decodeIfPresent([String].self, forKey: .profiles) ?? []
        privileged = try c.decodeIfPresent(Bool.self, forKey: .privileged) ?? false
        readOnly = try c.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
        initEnabled = try c.decodeIfPresent(Bool.self, forKey: .initEnabled) ?? false
        stopSignal = try c.decodeIfPresent(String.self, forKey: .stopSignal)
        extraHosts = try c.decodeIfPresent([String].self, forKey: .extraHosts) ?? []
        dns = try c.decodeIfPresent([String].self, forKey: .dns) ?? []
        capAdd = try c.decodeIfPresent([String].self, forKey: .capAdd) ?? []
        capDrop = try c.decodeIfPresent([String].self, forKey: .capDrop) ?? []
        shmSize = try c.decodeIfPresent(String.self, forKey: .shmSize)
        stdinOpen = try c.decodeIfPresent(Bool.self, forKey: .stdinOpen) ?? false
        tty = try c.decodeIfPresent(Bool.self, forKey: .tty) ?? false
        scale = try c.decodeIfPresent(Int.self, forKey: .scale) ?? 1
        deploy = try c.decodeIfPresent(DeployConfig.self, forKey: .deploy)
    }
}

/// Decodes a `command`/`entrypoint` value, which may be a list
/// (`["npm", "start"]`) or a string that is split with shell word-splitting
/// rules (`npm start` → `["npm", "start"]`), matching Docker's behavior.
/// Quotes are respected: `sh -c "npm install && npm run dev"` stays one arg.
struct CommandList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            values = Self.shellSplit(single)
        } else {
            values = try container.decode([String].self)
        }
    }

    /// Split a shell command string into words, respecting single/double
    /// quotes and backslash escapes. `sh -c "a && b"` → `["sh", "-c", "a && b"]`.
    static func shellSplit(_ input: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var escaped = false

        for char in input {
            if escaped {
                current.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if inSingle {
                if char == "'" {
                    inSingle = false
                } else {
                    current.append(char)
                }
            } else if inDouble {
                if char == "\"" {
                    inDouble = false
                } else {
                    current.append(char)
                }
            } else if char == "'" {
                inSingle = true
            } else if char == "\"" {
                inDouble = true
            } else if char.isWhitespace {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if escaped {
            current.append("\\")
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }
}

/// Decodes a value that may be a single string or an array of strings,
/// keeping a single string whole. Used for `healthcheck.test`, where a string
/// is a shell command (`curl -f http://localhost`) and must not be split.
struct StringOrList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            values = [single]
        } else {
            values = try container.decode([String].self)
        }
    }
}

/// Decodes a service's `networks` field, which may be a list of names
/// (`- default`) or a map of name → attachment config
/// (`default: {aliases: [web]}`). Only the names are kept.
struct NetworkList: Decodable {
    let names: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([String].self) {
            names = list
        } else {
            let map = try container.decode([String: NetworkAttachment].self)
            names = Array(map.keys)
        }
    }

    /// Attachment config for a network (may be empty).
    struct NetworkAttachment: Decodable {
        let aliases: [String]?
    }
}

/// Decodes a service's `ports` field, which may be a list of strings
/// (`- "8080:80"`) or a list of maps (`- target: 80, published: 8080`).
/// Map entries are normalized to the string form the orchestrator expects.
struct PortList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let entries = try container.decode([PortEntry].self)
        values = entries.map(\.stringValue)
    }

    struct PortEntry: Decodable {
        let stringValue: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let shorthand = try? container.decode(String.self) {
                stringValue = shorthand
                return
            }
            let map = try container.decode(PortMap.self)
            if let published = map.published {
                stringValue = "\(published):\(map.target)"
            } else {
                stringValue = "\(map.target)"
            }
        }
    }

    struct PortMap: Decodable {
        let target: Int
        let published: Int?
        let `protocol`: String?
        let mode: String?
    }
}

/// The condition under which a dependency is considered satisfied.
public enum DependsOnCondition: String, Sendable, Codable, Equatable {
    case serviceStarted = "service_started"
    case serviceHealthy = "service_healthy"
    case serviceCompletedSuccessfully = "service_completed_successfully"
}

/// Decodes `depends_on` in either its list form (`- db`) or map form
/// (`db: {condition: service_healthy}`), normalizing to a dictionary.
struct DependsOnMap: Codable {
    var conditions: [String: DependsOnCondition]

    init(from decoder: Decoder) throws {
        // List form: `- db` → all `service_started`.
        if var list = try? decoder.unkeyedContainer() {
            var result: [String: DependsOnCondition] = [:]
            while !list.isAtEnd {
                let name = try list.decode(String.self)
                result[name] = .serviceStarted
            }
            conditions = result
            return
        }
        // Map form: `db: {condition: service_healthy}` or `db: service_started`.
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var result: [String: DependsOnCondition] = [:]
        for key in container.allKeys {
            struct Entry: Decodable {
                let condition: DependsOnCondition?
            }
            if let entry = try? container.decode(Entry.self, forKey: key) {
                result[key.stringValue] = entry.condition ?? .serviceStarted
            } else if let condition = try? container.decode(DependsOnCondition.self, forKey: key) {
                result[key.stringValue] = condition
            }
        }
        conditions = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for (name, condition) in conditions {
            try container.encode(condition, forKey: DynamicKey(name))
        }
    }
}

/// Decodes `environment` in either its map form (`FOO: bar`) or list form
/// (`- FOO=bar`), normalizing to a dictionary.
struct EnvironmentMap: Codable {
    var values: [String: String]

    init(from decoder: Decoder) throws {
        // Map form (most common).
        if let dict = try? decoder.singleValueContainer().decode([String: String].self) {
            values = dict
            return
        }
        // List form: `- FOO=bar`.
        var list = try decoder.unkeyedContainer()
        var result: [String: String] = [:]
        while !list.isAtEnd {
            let entry = try list.decode(String.self)
            if let eq = entry.firstIndex(of: "=") {
                result[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
            } else {
                result[entry] = ""
            }
        }
        values = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

/// A coding key for dynamically-keyed maps.
struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }
}

/// A network definition.
public struct NetworkConfig: Sendable, Codable, Equatable {
    /// The driver to use.
    public var driver: String?
    /// Whether the network is external (pre-existing).
    public var external: Bool
    /// The external network's name.
    public var name: String?

    public init(driver: String? = nil, external: Bool = false, name: String? = nil) {
        self.driver = driver
        self.external = external
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case driver
        case external
        case name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        driver = try c.decodeIfPresent(String.self, forKey: .driver)
        // `external: true` or `external: {name: foo}`.
        if let externalBool = try? c.decodeIfPresent(Bool.self, forKey: .external) {
            external = externalBool
        } else {
            external = c.contains(.external)
        }
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }
}

/// A volume definition.
public struct VolumeConfig: Sendable, Codable, Equatable {
    /// The driver to use.
    public var driver: String?
    /// Whether the volume is external (pre-existing).
    public var external: Bool
    /// The external volume's name.
    public var name: String?

    public init(driver: String? = nil, external: Bool = false, name: String? = nil) {
        self.driver = driver
        self.external = external
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case driver
        case external
        case name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        driver = try c.decodeIfPresent(String.self, forKey: .driver)
        if let externalBool = try? c.decodeIfPresent(Bool.self, forKey: .external) {
            external = externalBool
        } else {
            external = c.contains(.external)
        }
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }
}

/// A config definition.
public struct ConfigConfig: Sendable, Codable, Equatable {
    public var file: String?
    public var external: Bool
    public var name: String?

    public init(file: String? = nil, external: Bool = false, name: String? = nil) {
        self.file = file
        self.external = external
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case file
        case external
        case name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decodeIfPresent(String.self, forKey: .file)
        if let externalBool = try? c.decodeIfPresent(Bool.self, forKey: .external) {
            external = externalBool
        } else {
            external = c.contains(.external)
        }
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }
}

/// A secret definition.
public struct SecretConfig: Sendable, Codable, Equatable {
    public var file: String?
    public var external: Bool
    public var name: String?

    public init(file: String? = nil, external: Bool = false, name: String? = nil) {
        self.file = file
        self.external = external
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case file
        case external
        case name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decodeIfPresent(String.self, forKey: .file)
        if let externalBool = try? c.decodeIfPresent(Bool.self, forKey: .external) {
            external = externalBool
        } else {
            external = c.contains(.external)
        }
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }
}

/// A build configuration.
public struct BuildConfig: Sendable, Codable, Equatable {
    /// The build context directory.
    public var context: String?
    /// The Dockerfile to use.
    public var dockerfile: String?
    /// Build arguments.
    public var args: [String: String]

    public init(context: String? = nil, dockerfile: String? = nil, args: [String: String] = [:]) {
        self.context = context
        self.dockerfile = dockerfile
        self.args = args
    }

    enum CodingKeys: String, CodingKey {
        case context
        case dockerfile
        case args
    }

    public init(from decoder: Decoder) throws {
        // `build` may be a shorthand string (the context) or a dict.
        if let single = try? decoder.singleValueContainer(),
           let shorthand = try? single.decode(String.self) {
            context = shorthand
            dockerfile = nil
            args = [:]
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        context = try c.decodeIfPresent(String.self, forKey: .context)
        dockerfile = try c.decodeIfPresent(String.self, forKey: .dockerfile)
        args = try c.decodeIfPresent([String: String].self, forKey: .args) ?? [:]
    }
}

/// A health check configuration.
public struct HealthCheckConfig: Sendable, Codable, Equatable {
    /// The test command. `["CMD", "curl", "-f", "http://localhost"]` or
    /// `["CMD-SHELL", "curl -f http://localhost"]`.
    public var test: [String]
    /// Interval between checks.
    public var interval: String?
    /// Timeout for a single check.
    public var timeout: String?
    /// Number of retries before marking unhealthy.
    public var retries: Int?
    /// Grace period before starting checks.
    public var startPeriod: String?

    public init(test: [String], interval: String? = nil, timeout: String? = nil, retries: Int? = nil, startPeriod: String? = nil) {
        self.test = test
        self.interval = interval
        self.timeout = timeout
        self.retries = retries
        self.startPeriod = startPeriod
    }

    enum CodingKeys: String, CodingKey {
        case test
        case interval
        case timeout
        case retries
        case startPeriod = "start_period"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        test = try c.decodeIfPresent(StringOrList.self, forKey: .test)?.values ?? []
        interval = try c.decodeIfPresent(String.self, forKey: .interval)
        timeout = try c.decodeIfPresent(String.self, forKey: .timeout)
        retries = try c.decodeIfPresent(Int.self, forKey: .retries)
        startPeriod = try c.decodeIfPresent(String.self, forKey: .startPeriod)
    }
}

/// The deploy section (only resource limits are honored).
public struct DeployConfig: Sendable, Codable, Equatable {
    public var resources: DeployResources?

    public init(resources: DeployResources? = nil) {
        self.resources = resources
    }

    enum CodingKeys: String, CodingKey {
        case resources
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resources = try c.decodeIfPresent(DeployResources.self, forKey: .resources)
    }
}

public struct DeployResources: Sendable, Codable, Equatable {
    public var limits: ResourceLimits?

    public init(limits: ResourceLimits? = nil) {
        self.limits = limits
    }

    enum CodingKeys: String, CodingKey {
        case limits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        limits = try c.decodeIfPresent(ResourceLimits.self, forKey: .limits)
    }
}

public struct ResourceLimits: Sendable, Codable, Equatable {
    public var cpus: String?
    public var memory: String?

    public init(cpus: String? = nil, memory: String? = nil) {
        self.cpus = cpus
        self.memory = memory
    }

    enum CodingKeys: String, CodingKey {
        case cpus
        case memory
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cpus = try c.decodeIfPresent(String.self, forKey: .cpus)
        memory = try c.decodeIfPresent(String.self, forKey: .memory)
    }
}
