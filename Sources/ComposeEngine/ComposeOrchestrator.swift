//===----------------------------------------------------------------------===//
// ComposeOrchestrator — executes a ComposeProject against the runtime.
//
// `up` creates the project's volumes and containers, starts them in
// `depends_on` order, and syncs /etc/hosts so services resolve each other by
// name (the platform has no per-project DNS). `down` tears everything down.
//
// Container naming follows docker compose: `<project>-<service>-1`. Project
// identity is tracked with `com.docker.compose.*` labels so `ps`/`down` can
// find the project's containers without a sidecar state file.
//===----------------------------------------------------------------------===//

import Foundation
import CryptoKit
import ContainerBackend

/// Errors produced while orchestrating a compose project.
public enum ComposeOrchestratorError: Error, LocalizedError {
    case imageNotFound(String)
    case buildFailed(String, String)
    case containerNotFound(String)
    case unhealthy(String, String)

    public var errorDescription: String? {
        switch self {
        case .imageNotFound(let service):
            return "compose: service '\(service)' has no image and no build context"
        case .buildFailed(let service, let detail):
            return "compose: build failed for service '\(service)': \(detail)"
        case .containerNotFound(let name):
            return "compose: container '\(name)' not found"
        case .unhealthy(let service, let reason):
            return "compose: service '\(service)' did not become healthy: \(reason)"
        }
    }
}

/// Executes compose projects against the container runtime.
public struct ComposeOrchestrator: Sendable {
    private let service: ContainerService
    private let secretStore: KeychainSecretStore

    public init(service: ContainerService = ContainerService(), secretStore: KeychainSecretStore? = nil) {
        self.service = service
        self.secretStore = secretStore ?? service.secrets
    }

    /// An image's description plus its default process config, with the raw
    /// entrypoint and cmd kept separate so callers can apply Docker's
    /// command-override semantics (a command replaces Cmd, but is appended to
    /// an existing Entrypoint).
    struct ImageProcessInfo {
        let image: ImageDescription
        let process: ProcessConfiguration
        let entrypoint: [String]
        let cmd: [String]
    }

    // MARK: - Labels

    /// The label keys used to track compose project identity on containers.
    public enum ComposeLabel {
        public static let project = "com.docker.compose.project"
        public static let service = "com.docker.compose.service"
        public static let workingDir = "com.docker.compose.project.working_dir"
        public static let configFiles = "com.docker.compose.project.config_files"
        public static let containerNumber = "com.docker.compose.container-number"
        public static let oneoff = "com.docker.compose.oneoff"
        public static let configHash = "com.macker.compose.config-hash"
    }

    // MARK: - Naming

    /// The container name for a service, following docker compose's
    /// `<project>-<service>-1` convention, or the service's `container_name:`
    /// when set.
    public static func containerName(project: String, service: String, config: ServiceConfig? = nil) -> String {
        if let config, let custom = config.containerName {
            return custom
        }
        return "\(sanitize(project))-\(sanitize(service))-1"
    }

    /// The image reference for a service: its `image:` when present, otherwise
    /// the tag its `build:` context is built as (`<project>-<service>`).
    public static func imageRef(project: String, service: String) -> String {
        "\(sanitize(project))-\(sanitize(service))"
    }

    /// The platform network name for a compose network.
    public static func networkName(project: String, network: String) -> String {
        "\(sanitize(project))_\(sanitize(network))"
    }

    /// The platform volume name for a compose volume.
    public static func volumeName(project: String, volume: String) -> String {
        "\(sanitize(project))_\(sanitize(volume))"
    }

    /// A stable hash of a service's definition, used to detect config changes
    /// between `up` runs so changed services are recreated.
    static func configHash(for service: ServiceConfig) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(service) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Lowercase and replace characters that are invalid in container names.
    static func sanitize(_ name: String) -> String {
        let lower = name.lowercased()
        let allowed = lower.map { char -> Character in
            if char.isLetter || char.isNumber || char == "_" || char == "." || char == "-" {
                return char
            }
            return "-"
        }
        return String(allowed)
    }

    // MARK: - Up

    /// Create and start the project's containers in dependency order.
    ///
    /// - Parameters:
    ///   - project: the parsed project.
    ///   - filePath: the compose file path (stored in labels).
    ///   - detached: when false, attach to the first service's output.
    ///   - progress: optional stream that receives human-readable progress
    ///     messages (image pulls, container creation, startup) so callers can
    ///     show what's happening instead of a bare spinner.
    public func up(
        project: ComposeProject,
        filePath: String,
        detached: Bool = true,
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        defer { progress?.finish() }
        let order = try ServiceResolver.resolve(project)

        // 1. Ensure every service's image is present locally, building any
        //    service that has a `build:` context instead of an `image:`.
        for name in order {
            let serviceConfig = project.services[name]!
            if let image = serviceConfig.image {
                progress?.yield("Pulling \(image)...")
                try await ensureImage(image)
            } else if let build = serviceConfig.build {
                try await buildImage(
                    project: project,
                    serviceName: name,
                    build: build,
                    filePath: filePath,
                    progress: progress
                )
            }
        }

        // 2. Create the project's named volumes.
        progress?.yield("Creating volumes...")
        try await ensureVolumes(project)

        // 3. Create containers in dependency order, recreating any whose
        //    config hash changed since the last `up`.
        for name in order {
            let serviceConfig = project.services[name]!
            let containerName = Self.containerName(project: project.name, service: name, config: serviceConfig)
            let hash = Self.configHash(for: serviceConfig)
            if let existing = try? await service.getContainer(id: containerName) {
                let storedHash = existing.configuration.labels[ComposeLabel.configHash]
                if storedHash != hash {
                    progress?.yield("Recreating \(name)...")
                    try? await service.stopContainer(id: containerName)
                    try? await service.deleteContainer(id: containerName, force: true)
                    let config = try await buildConfiguration(
                        project: project,
                        serviceName: name,
                        service: serviceConfig,
                        filePath: filePath,
                        configHash: hash
                    )
                    try await service.createContainer(
                        configuration: config,
                        options: .default,
                        kernel: nil,
                        initImage: nil,
                        runtimeData: nil
                    )
                }
            } else {
                progress?.yield("Creating \(name)...")
                let config = try await buildConfiguration(
                    project: project,
                    serviceName: name,
                    service: serviceConfig,
                    filePath: filePath,
                    configHash: hash
                )
                try await service.createContainer(
                    configuration: config,
                    options: .default,
                    kernel: nil,
                    initImage: nil,
                    runtimeData: nil
                )
            }
        }

        // 4. Start containers in dependency order, honoring `service_healthy`.
        for name in order {
            let serviceConfig = project.services[name]!
            let containerName = Self.containerName(project: project.name, service: name, config: serviceConfig)

            // Wait for dependencies that must be healthy first.
            for (dep, condition) in serviceConfig.dependsOn where condition == .serviceHealthy {
                let depContainer = Self.containerName(project: project.name, service: dep, config: project.services[dep])
                let depConfig = project.services[dep]!
                if let healthcheck = depConfig.healthcheck {
                    progress?.yield("Waiting for \(dep) to be healthy...")
                    try await waitUntilHealthy(containerId: depContainer, healthcheck: healthcheck)
                }
            }

            let snapshot = try await service.getContainer(id: containerName)
            if snapshot.status == .running {
                continue
            }
            progress?.yield("Starting \(name)...")
            try await service.bootstrapContainer(id: containerName)
            try await service.startProcess(containerId: containerName, processId: containerName)
        }

        // 5. Sync /etc/hosts so services resolve each other by name.
        progress?.yield("Syncing /etc/hosts...")
        try await syncHosts(project: project)
    }

    // MARK: - Down

    /// Stop and remove the project's containers. When `removeVolumes` is true,
    /// the project's named volumes are deleted too.
    public func down(
        project: ComposeProject,
        removeVolumes: Bool = false,
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        defer { progress?.finish() }
        let containers = try await projectContainers(project: project)
        for container in containers {
            progress?.yield("Stopping \(container.id)...")
            if container.status == .running {
                try? await service.stopContainer(id: container.id)
            }
            progress?.yield("Removing \(container.id)...")
            try? await service.deleteContainer(id: container.id, force: true)
        }
        if removeVolumes {
            for (name, config) in project.volumes where !config.external {
                progress?.yield("Removing volume \(name)...")
                try? await service.deleteVolume(name: Self.volumeName(project: project.name, volume: name))
            }
        }
    }

    // MARK: - Ps

    /// The project's containers, in service order.
    public func ps(project: ComposeProject) async throws -> [ContainerSnapshot] {
        let containers = try await projectContainers(project: project)
        let order = try ServiceResolver.resolve(project)
        return order.compactMap { name in
            let containerName = Self.containerName(project: project.name, service: name, config: project.services[name])
            return containers.first { $0.id == containerName }
        }
    }

    // MARK: - Logs

    /// Stream logs for one service (or all services when `service` is nil).
    public func logs(project: ComposeProject, service serviceName: String?, follow: Bool, tail: Int?) async throws {
        let names: [String]
        if let serviceName {
            names = [serviceName]
        } else {
            names = try ServiceResolver.resolve(project)
        }
        let logService = LogService()
        for name in names {
            let containerName = Self.containerName(project: project.name, service: name, config: project.services[name])
            for try await line in logService.logs(for: containerName, follow: follow, tail: tail) {
                if names.count > 1 {
                    print("\(name) | \(line.text)")
                } else {
                    print(line.text)
                }
            }
        }
    }

    // MARK: - Stop / Start / Restart

    /// Stop the given services (or all when `services` is empty).
    public func stop(
        project: ComposeProject,
        services: [String],
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        defer { progress?.finish() }
        for name in resolveTargets(project, services) {
            let containerName = Self.containerName(project: project.name, service: name, config: project.services[name])
            progress?.yield("Stopping \(name)...")
            try await service.stopContainer(id: containerName)
        }
    }

    /// Start the given services (or all when `services` is empty).
    public func start(
        project: ComposeProject,
        services: [String],
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        defer { progress?.finish() }
        for name in resolveTargets(project, services) {
            let containerName = Self.containerName(project: project.name, service: name, config: project.services[name])
            progress?.yield("Starting \(name)...")
            try await service.bootstrapContainer(id: containerName)
            try await service.startProcess(containerId: containerName, processId: containerName)
        }
    }

    /// Restart the given services (or all when `services` is empty).
    public func restart(
        project: ComposeProject,
        services: [String],
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        defer { progress?.finish() }
        for name in resolveTargets(project, services) {
            let containerName = Self.containerName(project: project.name, service: name, config: project.services[name])
            progress?.yield("Restarting \(name)...")
            try await service.stopContainer(id: containerName)
            try await service.bootstrapContainer(id: containerName)
            try await service.startProcess(containerId: containerName, processId: containerName)
        }
    }


    /// Force-recreate the project: stop and delete every container, then run
    /// `up` again so all services are rebuilt from the current compose file.
    public func recreate(
        project: ComposeProject,
        filePath: String,
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        defer { progress?.finish() }
        let containers = try await projectContainers(project: project)
        for container in containers {
            progress?.yield("Removing \(container.id)...")
            if container.status == .running {
                try? await service.stopContainer(id: container.id)
            }
            try? await service.deleteContainer(id: container.id, force: true)
        }
        try await up(project: project, filePath: filePath, detached: true, progress: progress)
    }

    /// Pull the images for all services, building any that have a `build:`
    /// context instead of an `image:`.
    public func pull(
        project: ComposeProject,
        filePath: String? = nil,
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        defer { progress?.finish() }
        for (name, serviceConfig) in project.services {
            if let image = serviceConfig.image {
                progress?.yield("Pulling \(image)...")
                try await ensureImage(image)
            } else if let build = serviceConfig.build {
                try await buildImage(
                    project: project,
                    serviceName: name,
                    build: build,
                    filePath: filePath ?? ".",
                    progress: progress
                )
            }
        }
    }

    // MARK: - Build

    /// Build the images for all services that have a `build:` context.
    public func build(
        project: ComposeProject,
        filePath: String,
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        defer { progress?.finish() }
        for (name, serviceConfig) in project.services {
            if let build = serviceConfig.build {
                try await buildImage(
                    project: project,
                    serviceName: name,
                    build: build,
                    filePath: filePath,
                    progress: progress
                )
            }
        }
    }

    // MARK: - Create

    /// Create the project's containers without starting them (like `compose
    /// create`). Ensures images and volumes first, mirroring `up` steps 1-3.
    public func create(
        project: ComposeProject,
        filePath: String,
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        defer { progress?.finish() }
        let order = try ServiceResolver.resolve(project)
        for name in order {
            let serviceConfig = project.services[name]!
            if let image = serviceConfig.image {
                progress?.yield("Pulling \(image)...")
                try await ensureImage(image)
            } else if let build = serviceConfig.build {
                try await buildImage(
                    project: project,
                    serviceName: name,
                    build: build,
                    filePath: filePath,
                    progress: progress
                )
            }
        }
        try await ensureVolumes(project)
        for name in order {
            let serviceConfig = project.services[name]!
            let containerName = Self.containerName(project: project.name, service: name, config: serviceConfig)
            let hash = Self.configHash(for: serviceConfig)
            if let existing = try? await service.getContainer(id: containerName) {
                let storedHash = existing.configuration.labels[ComposeLabel.configHash]
                if storedHash != hash {
                    progress?.yield("Recreating \(name)...")
                    try? await service.stopContainer(id: containerName)
                    try? await service.deleteContainer(id: containerName, force: true)
                    let config = try await buildConfiguration(
                        project: project,
                        serviceName: name,
                        service: serviceConfig,
                        filePath: filePath,
                        configHash: hash
                    )
                    try await service.createContainer(
                        configuration: config,
                        options: .default,
                        kernel: nil,
                        initImage: nil,
                        runtimeData: nil
                    )
                }
            } else {
                progress?.yield("Creating \(name)...")
                let config = try await buildConfiguration(
                    project: project,
                    serviceName: name,
                    service: serviceConfig,
                    filePath: filePath,
                    configHash: hash
                )
                try await service.createContainer(
                    configuration: config,
                    options: .default,
                    kernel: nil,
                    initImage: nil,
                    runtimeData: nil
                )
            }
        }
    }

    // MARK: - Kill

    /// Kill the given services (or all when `services` is empty).
    public func kill(
        project: ComposeProject,
        services: [String],
        signal: String = "SIGKILL",
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        defer { progress?.finish() }
        for name in resolveTargets(project, services) {
            let containerName = Self.containerName(project: project.name, service: name, config: project.services[name])
            progress?.yield("Killing \(name)...")
            try await service.killContainer(id: containerName, signal: signal)
        }
    }

    // MARK: - Rm

    /// Remove the given services' containers (or all when `services` is empty).
    /// Only stopped containers are removed unless `force` is true.
    public func rm(
        project: ComposeProject,
        services: [String],
        force: Bool = false,
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        defer { progress?.finish() }
        for name in resolveTargets(project, services) {
            let containerName = Self.containerName(project: project.name, service: name, config: project.services[name])
            let snapshot = try? await service.getContainer(id: containerName)
            guard let snapshot else { continue }
            if snapshot.status == .running && !force {
                progress?.yield("Cannot remove running container \(name) (use --force)")
                continue
            }
            if snapshot.status == .running {
                try? await service.stopContainer(id: containerName)
            }
            progress?.yield("Removing \(name)...")
            try await service.deleteContainer(id: containerName, force: true)
        }
    }

    // MARK: - Port

    /// The published host port for a service's container port.
    public func port(project: ComposeProject, serviceName: String, containerPort: UInt16) async throws -> String? {
        let containerName = Self.containerName(project: project.name, service: serviceName, config: project.services[serviceName])
        let snapshot = try await service.getContainer(id: containerName)
        for p in snapshot.configuration.publishedPorts where p.containerPort == containerPort {
            return "\(p.hostAddress):\(p.hostPort)"
        }
        return nil
    }

    // MARK: - Images

    /// The image reference used by each service.
    public func images(project: ComposeProject) -> [(service: String, image: String)] {
        return project.services.map { (name, config) in
            let image = config.image ?? Self.imageRef(project: project.name, service: name)
            return (name, image)
        }.sorted { $0.service < $1.service }
    }

    // MARK: - Run

    /// Run a one-shot command in a service's container (like `compose run`).
    public func run(
        project: ComposeProject,
        serviceName: String,
        command: [String],
        filePath: String,
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws -> Int32 {
        defer { progress?.finish() }
        let serviceConfig = project.services[serviceName]!
        if let image = serviceConfig.image {
            try await ensureImage(image)
        } else if let build = serviceConfig.build {
            try await buildImage(
                project: project,
                serviceName: serviceName,
                build: build,
                filePath: filePath,
                progress: progress
            )
        }
        let containerName = Self.containerName(project: project.name, service: serviceName, config: serviceConfig)
        let snapshot = try? await service.getContainer(id: containerName)
        if snapshot?.status != .running {
            try await service.bootstrapContainer(id: containerName)
            try await service.startProcess(containerId: containerName, processId: containerName)
        }
        return try await runStreaming(containerId: containerName, command: command)
    }

    /// Run a command in a container, streaming its output to our own
    /// stdout/stderr, and return its exit code.
    private func runStreaming(containerId: String, command: [String]) async throws -> Int32 {
        guard let executable = command.first else { return 0 }
        let processId = UUID().uuidString.lowercased()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                FileHandle.standardOutput.write(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                FileHandle.standardError.write(data)
            }
        }
        let config = ProcessConfiguration(
            executable: executable,
            arguments: Array(command.dropFirst()),
            environment: [],
            workingDirectory: "/",
            terminal: false,
            user: .raw(userString: "root"),
            supplementalGroups: [],
            rlimits: []
        )
        try await service.createProcess(
            containerId: containerId,
            processId: processId,
            configuration: config,
            stdio: [nil, stdoutPipe.fileHandleForWriting, stderrPipe.fileHandleForWriting]
        )
        try await service.startProcess(containerId: containerId, processId: processId)
        let exitCode = try await service.waitForProcess(containerId: containerId, processId: processId)
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        return exitCode
    }

    // MARK: - Configuration

    /// Build a ContainerConfiguration from a service definition.
    func buildConfiguration(
        project: ComposeProject,
        serviceName: String,
        service: ServiceConfig,
        filePath: String,
        configHash: String? = nil
    ) async throws -> ContainerConfiguration {
        let containerName = Self.containerName(project: project.name, service: serviceName, config: service)

        // Resolve the image and its default process config.
        let imageRef = service.image ?? Self.imageRef(project: project.name, service: serviceName)
        let imageConfig = try await inspectImage(imageRef)

        var process = imageConfig.process
        if let entrypoint = service.entrypoint {
            process.executable = entrypoint.first ?? process.executable
            process.arguments = Array(entrypoint.dropFirst())
        }
        if let command = service.command {
            if service.entrypoint == nil && imageConfig.entrypoint.isEmpty {
                // No entrypoint in effect — the command replaces the whole
                // process (Docker semantics: command overrides Cmd, and with
                // no Entrypoint the Cmd is the entire process).
                process.executable = command.first ?? "/bin/sh"
                process.arguments = Array(command.dropFirst())
            } else {
                // An entrypoint is in effect — preserve it and replace the
                // image's Cmd with the command args.
                process.arguments = command
            }
        }
        if let workingDir = service.workingDir {
            process.workingDirectory = workingDir
        }
        process.terminal = service.tty
        if let user = service.user {
            process.user = .raw(userString: user)
        }

        // Environment: image defaults + env_file + service environment.
        // Docker semantics: later entries override earlier ones (last wins),
        // so deduplicate by key. A duplicated key (e.g. PGDATA from both the
        // image and the compose file) otherwise breaks bootstrap.
        var env = process.environment
        for envFile in service.envFile {
            let resolved = Self.resolvePath(envFile, relativeTo: filePath)
            if let fileEnv = Self.loadEnvFile(at: resolved) {
                env.append(contentsOf: fileEnv.map { "\($0.key)=\($0.value)" })
            }
        }
        for (key, value) in service.environment {
            env.append("\(key)=\(value)")
        }
        process.environment = try secretStore.resolveEnvironment(Self.deduplicateEnv(env))

        // Mounts: named volumes, bind mounts, tmpfs.
        var mounts: [Filesystem] = []
        for spec in service.volumes {
            if let fs = Self.parseVolumeSpec(spec, project: project, basePath: filePath) {
                mounts.append(fs)
            }
        }
        // Resolve named volumes to their host paths: the server needs the
        // volume image path as the mount source, not the bare volume name
        // (a bare name makes bootstrap fail with EOPNOTSUPP).
        mounts = try await resolveVolumeSources(mounts)

        // Published ports.
        var publishedPorts: [PublishPort] = []
        for spec in service.ports {
            if let port = Self.parsePortSpec(spec) {
                publishedPorts.append(port)
            }
        }

        // Resources.
        var resources = ContainerConfiguration.Resources()
        if let cpus = service.cpus {
            resources.cpus = max(1, Int(cpus.rounded()))
        }
        if let memory = service.memory.flatMap(Self.parseMemory) {
            resources.memoryInBytes = memory
        }
        if let deployCpus = service.deploy?.resources?.limits?.cpus.flatMap(Double.init) {
            resources.cpus = max(1, Int(deployCpus.rounded()))
        }
        if let deployMemory = service.deploy?.resources?.limits?.memory.flatMap(Self.parseMemory) {
            resources.memoryInBytes = deployMemory
        }

        // Labels.
        var labels = service.labels
        labels[ComposeLabel.project] = project.name
        labels[ComposeLabel.service] = serviceName
        labels[ComposeLabel.workingDir] = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        labels[ComposeLabel.configFiles] = filePath
        labels[ComposeLabel.containerNumber] = "1"
        labels[ComposeLabel.oneoff] = "False"
        if let configHash {
            labels[ComposeLabel.configHash] = configHash
        }

        // Networks: attach to the platform's default network with a unique
        // hostname (the server rejects empty/duplicate hostnames). The MTU
        // must be set explicitly: the CLI defaults to 1280, and omitting it
        // makes bootstrap fail with EOPNOTSUPP.
        let hostname = service.hostname ?? containerName
        let networks = [AttachmentConfiguration(
            network: ContainerAPIClient.defaultNetworkName,
            options: AttachmentOptions(hostname: hostname, mtu: 1280)
        )]

        return ContainerConfiguration(
            id: containerName,
            image: imageConfig.image,
            process: process,
            mounts: mounts,
            publishedPorts: publishedPorts,
            labels: labels,
            networks: networks,
            dns: service.dns.isEmpty ? nil : .init(nameservers: service.dns),
            resources: resources,
            readOnly: service.readOnly,
            privileged: service.privileged,
            useInit: service.initEnabled,
            capAdd: service.capAdd,
            capDrop: service.capDrop,
            securityOptions: service.securityOpt,
            shmSize: service.shmSize.flatMap(Self.parseMemory),
            stopSignal: service.stopSignal
        )
    }

    // MARK: - Helpers

    /// Pull an image if it isn't present locally.
    private func ensureImage(_ reference: String) async throws {
        let images = try await service.images.list()
        let present = images.contains { $0.name.hasSuffix(reference) || $0.name.contains(reference) }
        if !present {
            try await service.images.pull(reference)
        }
    }

    /// Build a service's image from its `build:` context using the platform's
    /// BuildKit (`container build`). The image is tagged `<project>-<service>`
    /// so `buildConfiguration` can find it by reference.
    private func buildImage(
        project: ComposeProject,
        serviceName: String,
        build: BuildConfig,
        filePath: String,
        progress: AsyncStream<String>.Continuation? = nil
    ) async throws {
        let tag = Self.imageRef(project: project.name, service: serviceName)
        let context = Self.resolvePath(build.context ?? ".", relativeTo: filePath)
        let dockerfile = build.dockerfile.map { Self.resolvePath($0, relativeTo: filePath) }

        var args = ["build", "-t", tag, "--progress", "plain"]
        if let dockerfile {
            args += ["-f", dockerfile]
        }
        for (key, value) in build.args {
            args += ["--build-arg", "\(key)=\(value)"]
        }
        args.append(context)

        progress?.yield("Building \(serviceName)...")
        let runner = ProcessRunner()
        let result = try await runner.run(args, timeout: .seconds(600))
        guard result.succeeded else {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw ComposeOrchestratorError.buildFailed(serviceName, detail)
        }
    }

    /// Create the project's named volumes that don't exist yet.
    private func ensureVolumes(_ project: ComposeProject) async throws {
        let existing = try await service.listVolumes()
        let existingNames = Set(existing.map(\.name))
        for (name, config) in project.volumes where !config.external {
            let platformName = Self.volumeName(project: project.name, volume: name)
            if !existingNames.contains(platformName) {
                _ = try await service.createVolume(name: platformName)
            }
        }
    }

    /// Replace the source of named-volume mounts with the volume's host path.
    /// The server rejects a bare volume name as a mount source (bootstrap
    /// fails with EOPNOTSUPP); the CLI always sends the resolved path.
    private func resolveVolumeSources(_ mounts: [Filesystem]) async throws -> [Filesystem] {
        var resolved: [Filesystem] = []
        for mount in mounts {
            if let name = mount.volumeName {
                if let volume = try? await service.inspectVolume(name) {
                    resolved.append(Filesystem(
                        type: mount.type,
                        source: volume.source,
                        destination: mount.destination,
                        options: mount.options
                    ))
                } else {
                    resolved.append(mount)
                }
            } else {
                resolved.append(mount)
            }
        }
        return resolved
    }

    /// The project's containers, found by the project label.
    private func projectContainers(project: ComposeProject) async throws -> [ContainerSnapshot] {
        let all = try await service.listContainers(filters: .all)
        return all.filter { $0.configuration.labels[ComposeLabel.project] == project.name }
    }

    /// Resolve the target services for stop/start/restart: the given list, or
    /// all services in dependency order when empty.
    private func resolveTargets(_ project: ComposeProject, _ services: [String]) -> [String] {
        if services.isEmpty {
            return (try? ServiceResolver.resolve(project)) ?? Array(project.services.keys)
        }
        return services
    }

    /// Inspect an image and extract the fields needed to build a container.
    private func inspectImage(_ reference: String) async throws -> ImageProcessInfo {
        let runner = ProcessRunner()
        let result = try await runner.run(["image", "inspect", reference], timeout: .seconds(30))
        guard result.succeeded else {
            throw BackendError.operationFailed("failed to inspect image \(reference)")
        }
        return try Self.parseImageInspect(result.stdout)
    }

    /// Parse `container image inspect` JSON into image + process config.
    static func parseImageInspect(_ json: String) throws -> ImageProcessInfo {
        struct RawInspect: Decodable {
            struct Configuration: Decodable {
                let name: String
                let descriptor: Descriptor
            }
            struct Descriptor: Decodable {
                let digest: String
                let mediaType: String?
                let size: Int64?
                let annotations: [String: String]?
            }
            struct Variant: Decodable {
                // `variants[0].config` is the OCI image config wrapper; the
                // container config (Cmd/Entrypoint/Env) is nested one level
                // deeper at `variants[0].config.config`.
                struct ImageConfig: Decodable {
                    struct Config: Decodable {
                        let Cmd: [String]?
                        let Entrypoint: [String]?
                        let Env: [String]?
                        let WorkingDir: String?
                    }
                    let config: Config
                }
                let config: ImageConfig
                let platform: Platform?
            }
            struct Platform: Decodable {
                let os: String?
                let architecture: String?
            }
            let configuration: Configuration
            let variants: [Variant]?
        }

        let decoder = JSONDecoder()
        let raw = try decoder.decode([RawInspect].self, from: Data(json.utf8))
        guard let image = raw.first else {
            throw BackendError.invalidResponse("empty image inspect output")
        }

        let descriptor = Descriptor(
            mediaType: image.configuration.descriptor.mediaType ?? "application/vnd.oci.image.index.v1+json",
            digest: image.configuration.descriptor.digest,
            size: image.configuration.descriptor.size ?? 0,
            urls: nil,
            annotations: image.configuration.descriptor.annotations,
            platform: nil,
            artifactType: nil
        )
        let imageDescription = ImageDescription(
            reference: image.configuration.name,
            descriptor: descriptor
        )

        let variant = image.variants?.first
        let entrypoint = variant?.config.config.Entrypoint ?? []
        let cmd = variant?.config.config.Cmd ?? []
        let env = variant?.config.config.Env ?? []
        let workingDir = variant?.config.config.WorkingDir

        // With an entrypoint, the process is `entrypoint + cmd`; without one,
        // the cmd alone is the process (its first element is the executable).
        let executable = entrypoint.first ?? cmd.first ?? "/bin/sh"
        let arguments = entrypoint.isEmpty ? Array(cmd.dropFirst()) : Array(entrypoint.dropFirst()) + cmd
        // Use the image's default user (empty string) rather than forcing
        // root: an explicit `user: root` combined with a named volume mount
        // makes bootstrap fail (EOPNOTSUPP / "storage device attachment is
        // invalid").
        let process = ProcessConfiguration(
            executable: executable,
            arguments: arguments,
            environment: env,
            workingDirectory: workingDir ?? "/",
            terminal: false,
            user: .raw(userString: ""),
            supplementalGroups: [],
            rlimits: []
        )

        return ImageProcessInfo(
            image: imageDescription,
            process: process,
            entrypoint: entrypoint,
            cmd: cmd
        )
    }

    /// Parse a compose port spec like `8080:80`, `127.0.0.1:8080:80`, `80`.
    static func parsePortSpec(_ spec: String) -> PublishPort? {
        let parts = spec.split(separator: ":").map(String.init)
        switch parts.count {
        case 1:
            guard let port = UInt16(parts[0]) else { return nil }
            return PublishPort(hostAddress: IPAddress("0.0.0.0"), hostPort: port, containerPort: port, proto: .tcp, count: 1)
        case 2:
            guard let host = UInt16(parts[0]), let container = UInt16(parts[1]) else { return nil }
            return PublishPort(hostAddress: IPAddress("0.0.0.0"), hostPort: host, containerPort: container, proto: .tcp, count: 1)
        case 3:
            guard let host = UInt16(parts[1]), let container = UInt16(parts[2]) else { return nil }
            return PublishPort(hostAddress: IPAddress(parts[0]), hostPort: host, containerPort: container, proto: .tcp, count: 1)
        default:
            return nil
        }
    }

    /// Parse a compose volume spec like `name:/path`, `/host:/container`,
    /// `/host:/container:ro`, or `name:/path:ro`.
    static func parseVolumeSpec(_ spec: String, project: ComposeProject, basePath: String) -> Filesystem? {
        let parts = spec.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return nil }
        let source = parts[0]
        let destination = parts[1]
        let options: MountOptions = (parts.count >= 3 && parts[2].contains("ro")) ? ["ro"] : []

        if source.hasPrefix("/") || source.hasPrefix("./") || source.hasPrefix("../")
            || source.hasPrefix("~/") || source == "." || source == ".." {
            // Bind mount (virtiofs), resolved against the compose file's
            // directory. A relative source (e.g. `./:/app:rw`) otherwise
            // mounts the wrong path read-only.
            return .virtiofs(source: resolvePath(source, relativeTo: basePath), destination: destination, options: options)
        } else if source == "tmpfs" {
            return .tmpfs(destination: destination, options: options)
        } else {
            // Named volume, namespaced by the project.
            let platformName = volumeName(project: project.name, volume: source)
            return .volume(name: platformName, format: "ext4", source: platformName, destination: destination, options: options)
        }
    }

    /// Parse a memory string like `512m`, `1g`, `256mb`.
    static func parseMemory(_ value: String) -> UInt64? {
        let lower = value.lowercased()
        let multipliers: [(String, UInt64)] = [
            ("g", 1024 * 1024 * 1024),
            ("m", 1024 * 1024),
            ("k", 1024),
            ("b", 1),
        ]
        for (suffix, multiplier) in multipliers {
            if lower.hasSuffix(suffix) {
                let number = lower.dropLast(suffix.count)
                guard let value = Double(number) else { return nil }
                return UInt64(value * Double(multiplier))
            }
        }
        return UInt64(lower)
    }

    /// Resolve a possibly-relative path against the compose file's directory.
    static func resolvePath(_ path: String, relativeTo filePath: String) -> String {
        if path.hasPrefix("/") { return path }
        let base = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        return base.appendingPathComponent(path).path
    }

    /// Load `KEY=VALUE` pairs from a `.env` file.
    static func loadEnvFile(at path: String) -> [String: String]? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var result: [String: String] = [:]
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.first == "\"", value.last == "\"" {
                value = String(value.dropFirst().dropLast())
            } else if value.count >= 2, value.first == "'", value.last == "'" {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    /// Merge "KEY=VALUE" environment entries, keeping the LAST value for each
    /// key (Docker semantics) while preserving first-appearance order.
    static func deduplicateEnv(_ entries: [String]) -> [String] {
        var order: [String] = []
        var values: [String: String] = [:]
        for entry in entries {
            let parts = entry.split(separator: "=", maxSplits: 1)
            let key = String(parts[0])
            let value = parts.count > 1 ? String(parts[1]) : ""
            if values[key] == nil { order.append(key) }
            values[key] = value
        }
        return order.map { "\($0)=\(values[$0]!)" }
    }

    /// Run a command inside a running container and return its exit code.
    private func runInContainer(containerId: String, command: [String]) async throws -> Int32 {
        guard let executable = command.first else { return 0 }
        let processId = UUID().uuidString.lowercased()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        let config = ProcessConfiguration(
            executable: executable,
            arguments: Array(command.dropFirst()),
            environment: [],
            workingDirectory: "/",
            terminal: false,
            user: .raw(userString: "root"),
            supplementalGroups: [],
            rlimits: []
        )
        try await service.createProcess(
            containerId: containerId,
            processId: processId,
            configuration: config,
            stdio: [nil, stdoutPipe.fileHandleForWriting, stderrPipe.fileHandleForWriting]
        )
        try await service.startProcess(containerId: containerId, processId: processId)
        let exitCode = try await service.waitForProcess(containerId: containerId, processId: processId)
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        return exitCode
    }

    /// The IPv4 address of a container's first network attachment.
    private func containerIP(_ snapshot: ContainerSnapshot) -> String? {
        guard let address = snapshot.networks.first?.ipv4Address else { return nil }
        return address.split(separator: "/").first.map(String.init)
    }

    /// Write `<service-name> <ip>` entries into every container's /etc/hosts so
    /// services resolve each other by name.
    private func syncHosts(project: ComposeProject) async throws {
        var ips: [String: String] = [:]
        for name in project.services.keys {
            let containerName = Self.containerName(project: project.name, service: name, config: project.services[name])
            if let snapshot = try? await service.getContainer(id: containerName),
               let ip = containerIP(snapshot) {
                ips[name] = ip
            }
        }
        guard !ips.isEmpty else { return }

        for name in project.services.keys {
            let containerName = Self.containerName(project: project.name, service: name, config: project.services[name])
            var entries = ""
            for (otherName, ip) in ips where otherName != name {
                entries += "\(ip) \(otherName)\n"
            }
            guard !entries.isEmpty else { continue }
            // Append to /etc/hosts via a shell command inside the container.
            let script = "printf '%s' '\(entries)' >> /etc/hosts"
            _ = try? await runInContainer(containerId: containerName, command: ["sh", "-c", script])
        }
    }

    /// Poll a container's healthcheck until it passes or the retries are
    /// exhausted.
    private func waitUntilHealthy(containerId: String, healthcheck: HealthCheckConfig) async throws {
        let interval = Self.parseDuration(healthcheck.interval) ?? 5
        let retries = healthcheck.retries ?? 3
        let startPeriod = Self.parseDuration(healthcheck.startPeriod) ?? 0

        if startPeriod > 0 {
            try await Task.sleep(for: .seconds(startPeriod))
        }

        for attempt in 0..<retries {
            let exitCode = try? await runHealthcheck(containerId: containerId, healthcheck: healthcheck)
            if exitCode == 0 {
                return
            }
            if attempt < retries - 1 {
                try await Task.sleep(for: .seconds(interval))
            }
        }
        throw ComposeOrchestratorError.unhealthy(containerId, "healthcheck failed after \(retries) attempts")
    }

    /// Run a healthcheck test command inside a container.
    private func runHealthcheck(containerId: String, healthcheck: HealthCheckConfig) async throws -> Int32 {
        let test = healthcheck.test
        guard let first = test.first else { return 1 }
        let command: [String]
        switch first.uppercased() {
        case "CMD":
            command = Array(test.dropFirst())
        case "CMD-SHELL":
            command = ["sh", "-c", test.dropFirst().joined(separator: " ")]
        default:
            // A single string is a shell command (Docker treats string
            // healthcheck tests as CMD-SHELL); a list is a direct command.
            if test.count == 1 {
                command = ["sh", "-c", first]
            } else {
                command = test
            }
        }
        return try await runInContainer(containerId: containerId, command: command)
    }

    /// Parse a compose duration like `30s`, `1m30s`, `500ms`, `1h`.
    static func parseDuration(_ value: String?) -> Double? {
        guard let value, !value.isEmpty else { return nil }
        // Milliseconds are a single unit; handle them first.
        if value.hasSuffix("ms"), let n = Double(value.dropLast(2)) {
            return n / 1000
        }
        var total: Double = 0
        var number = ""
        for char in value {
            if char.isNumber || char == "." {
                number.append(char)
            } else {
                guard let n = Double(number) else { return nil }
                switch char {
                case "h": total += n * 3600
                case "m": total += n * 60
                case "s": total += n
                default: return nil
                }
                number = ""
            }
        }
        // A trailing bare number is treated as seconds.
        if let n = Double(number) {
            total += n
        }
        return total
    }
}
