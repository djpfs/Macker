//===----------------------------------------------------------------------===//
// DockerTranslator — maps parsed docker commands to ContainerService calls.
//
// Each docker subcommand is translated to one or more operations on the
// container runtime and its output is formatted to resemble docker's. Commands
// with no platform equivalent fail with an informative message rather than
// silently doing the wrong thing.
//===----------------------------------------------------------------------===//

import ArgumentParser
import Foundation
import ContainerBackend
import ComposeEngine

/// Translates docker commands into runtime operations.
public struct DockerTranslator: Sendable {
    private let service: ContainerService
    private let auditLogger: AuditLogger

    public init(
        service: ContainerService = ContainerService(),
        auditLogger: AuditLogger = .shared
    ) {
        self.service = service
        self.auditLogger = auditLogger
    }

    /// Execute a parsed docker command.
    public func execute(_ command: DockerCommand) async throws {
        switch command.subcommand {
        case "ps", "ls":
            try await ps(command)
        case "run":
            try await run(command)
        case "stop":
            try await stop(command)
        case "rm", "remove":
            try await rm(command)
        case "kill":
            try await kill(command)
        case "start":
            try await start(command)
        case "restart":
            try await restart(command)
        case "images", "image":
            try await images(command)
        case "rmi":
            // `docker rmi IMAGE...` — alias for image delete.
            let ids = command.arguments
            guard !ids.isEmpty else { throw DockerShimError.missingArgument("image") }
            try await service.images.delete(ids)
        case "pull":
            try await pull(command)
        case "logs":
            try await logs(command)
        case "exec":
            try await exec(command)
        case "inspect":
            try await inspect(command)
        case "cp":
            try await cp(command)
        case "stats":
            try await stats(command)
        case "port":
            try await port(command)
        case "wait":
            try await wait(command)
        case "network":
            try await network(command)
        case "volume":
            try await volume(command)
        case "system":
            try await system(command)
        case "version":
            try await version(command)
        case "info":
            try await info(command)
        case "build":
            try await build(command)
        case "create":
            try await create(command)
        case "prune":
            try await prune(command)
        case "tag":
            try await tag(command)
        case "push":
            try await push(command)
        case "load":
            try await load(command)
        case "save":
            try await save(command)
        case "rename":
            throw DockerShimError.unsupportedCommand("rename")
        case "pause":
            try await pause(command)
        case "unpause":
            try await unpause(command)
        case "top":
            try await top(command)
        case "update":
            throw DockerShimError.unsupportedCommand("update")
        case "events":
            try await events(command)
        case "attach":
            throw DockerShimError.unsupportedCommand("attach")
        case "history":
            throw DockerShimError.unsupportedCommand("history")
        case "scan":
            try await scan(command)
        case "secret":
            try await secret(command)
        case "compose":
            try await compose(command)
        default:
            throw DockerShimError.unsupportedCommand(command.subcommand)
        }
    }

    // MARK: - Containers

    private func ps(_ command: DockerCommand) async throws {
        let all = command.has("a") || command.has("all")
        let filters = ContainerListFilters(status: all ? nil : .running)
        var containers = try await service.listContainers(filters: filters)

        // Docker-style filters (`-f name=web`, `-f status=exited`, ...) are
        // applied client-side since the platform only filters by id/status/label.
        if let filterValue = command.value("f") ?? command.value("filter") {
            for filter in filterValue.split(separator: ",") {
                let parts = filter.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = String(parts[0])
                let value = String(parts[1])
                switch key {
                case "name":
                    containers = containers.filter { $0.configuration.id.contains(value) }
                case "id":
                    containers = containers.filter { $0.id.contains(value) }
                case "status":
                    // docker uses `exited`; the platform uses `stopped`.
                    let status = value == "exited" ? "stopped" : value
                    containers = containers.filter { $0.status.rawValue == status }
                case "label":
                    containers = containers.filter { c in
                        c.configuration.labels.contains { $0.key == value || "\($0.key)=\($0.value)" == value }
                    }
                case "ancestor":
                    containers = containers.filter { $0.configuration.image.reference.contains(value) }
                default:
                    break
                }
            }
        }

        let quiet = command.has("q") || command.has("quiet")
        if quiet {
            for c in containers {
                print(c.id.prefix(12))
            }
            return
        }

        // docker ps columns: CONTAINER ID, IMAGE, COMMAND, CREATED, STATUS, PORTS, NAMES
        let headers = ["CONTAINER ID", "IMAGE", "COMMAND", "CREATED", "STATUS", "PORTS", "NAMES"]
        var rows: [[String]] = []
        for c in containers {
            let id = String(c.id.prefix(12))
            let image = c.configuration.image.reference
            let command = Self.commandSummary(c.configuration.initProcess)
            let created = Self.relativeTime(c.configuration.creationDate)
            let status = Self.statusSummary(c)
            let ports = Self.portsSummary(c.configuration.publishedPorts)
            let name = c.configuration.id
            rows.append([id, image, command, created, status, ports, name])
        }
        Self.printTable(headers: headers, rows: rows)
    }

    /// Build a short command summary like docker ps (executable + first arg).
    private static func commandSummary(_ process: ProcessConfiguration) -> String {
        let exe = (process.executable as NSString).lastPathComponent
        if let first = process.arguments.first, !first.isEmpty {
            return "\(exe) \(first)"
        }
        return exe
    }

    /// Map a runtime status to a docker-style status string.
    private static func statusSummary(_ c: ContainerSnapshot) -> String {
        switch c.status {
        case .running:
            if let started = c.startedDate {
                return "Up \(Self.relativeTime(started))"
            }
            return "Up"
        case .stopped:
            return "Exited"
        case .stopping:
            return "Stopping"
        case .unknown:
            return "Unknown"
        }
    }

    /// Render published ports like docker ps ("0.0.0.0:3333->3333/tcp").
    private static func portsSummary(_ ports: [PublishPort]) -> String {
        let parts = ports.map { p -> String in
            let host = p.hostAddress.rawValue
            let hostPort = p.hostPort
            let containerPort = p.containerPort
            let proto = p.proto.rawValue
            return "\(host):\(hostPort)->\(containerPort)/\(proto)"
        }
        return parts.joined(separator: ", ")
    }

    /// Human-friendly relative time ("2 days ago", "3 hours ago", "Just now").
    private static func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s") ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hour\(hours == 1 ? "" : "s") ago" }
        let days = hours / 24
        if days < 30 { return "\(days) day\(days == 1 ? "" : "s") ago" }
        let months = days / 30
        if months < 12 { return "\(months) month\(months == 1 ? "" : "s") ago" }
        let years = months / 12
        return "\(years) year\(years == 1 ? "" : "s") ago"
    }

    /// Print a column-aligned table with a header row and padded values.
    private static func printTable(headers: [String], rows: [[String]]) {
        var widths = headers.map { $0.count }
        for row in rows {
            for (i, cell) in row.enumerated() where i < widths.count {
                widths[i] = max(widths[i], cell.count)
            }
        }
        func pad(_ s: String, _ w: Int) -> String {
            s.padding(toLength: w, withPad: " ", startingAt: 0)
        }
        let headerLine = headers.enumerated().map { pad($0.element, widths[$0.offset]) }.joined(separator: "   ")
        print(headerLine)
        for row in rows {
            let line = row.enumerated().map { pad($0.element, widths[$0.offset]) }.joined(separator: "   ")
            print(line)
        }
    }

    private func run(_ command: DockerCommand) async throws {
        let (config, autoRemove) = try await makeRunConfig(command)
        let name = config.id

        try await service.createContainer(
            configuration: config,
            options: ContainerCreateOptions(autoRemove: autoRemove),
            kernel: nil,
            initImage: nil,
            runtimeData: nil
        )

        if command.has("d") || command.has("detach") {
            // Detached: bootstrap and start without stdio, print the name.
            try await service.bootstrapContainer(id: name)
            try await service.startProcess(containerId: name, processId: name)
            print(name)
        } else {
            // Attached: pipe the init process stdout/stderr to our own, start
            // it, and wait for it to exit (like `docker run`).
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
            try await service.bootstrapContainer(
                id: name,
                stdio: [nil, stdoutPipe.fileHandleForWriting, stderrPipe.fileHandleForWriting]
            )
            try await service.startProcess(containerId: name, processId: name)
            let exitCode = try await service.waitForProcess(containerId: name, processId: name)
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            if exitCode != 0 {
                throw ExitCode(exitCode)
            }
        }
    }

    /// `docker create` — build the same config as `run` but do not start it.
    private func create(_ command: DockerCommand) async throws {
        let (config, autoRemove) = try await makeRunConfig(command)
        try await service.createContainer(
            configuration: config,
            options: ContainerCreateOptions(autoRemove: autoRemove),
            kernel: nil,
            initImage: nil,
            runtimeData: nil
        )
        print(config.id)
    }

    /// Build a container configuration from a `run`/`create` command.
    private func makeRunConfig(_ command: DockerCommand) async throws -> (ContainerConfiguration, Bool) {
        guard let imageRef = command.arguments.first else {
            throw DockerShimError.missingArgument("image")
        }
        let imageArgs = Array(command.arguments.dropFirst())

        // Pull the image if it isn't present.
        let images = try await service.images.list()
        let present = images.contains { $0.name.hasSuffix(imageRef) || $0.name.contains(imageRef) }
        if !present {
            print("Unable to find image '\(imageRef)' locally")
            try await service.images.pull(imageRef)
        }

        // Inspect the image to recover its default config.
        let imageConfig = try await inspectImage(imageRef)

        let name = command.value("name") ?? Self.randomName()

        var config = ContainerConfiguration(
            id: name,
            image: imageConfig.image,
            process: imageConfig.process,
            mounts: [],
            publishedPorts: [],
            labels: ["com.macker.shim": "true"],
            networks: [AttachmentConfiguration(
                network: ContainerAPIClient.defaultNetworkName,
                options: AttachmentOptions(hostname: name, mtu: 1280)
            )],
            resources: .init()
        )

        // -p / --publish
        for portSpec in command.value(short: "p", long: "publish")?.split(separator: ",") ?? [] {
            if let port = Self.parsePortSpec(String(portSpec)) {
                config.publishedPorts.append(port)
            }
        }

        // -v / --volume
        for volumeSpec in command.value(short: "v", long: "volume")?.split(separator: ",") ?? [] {
            if let fs = Self.parseVolumeSpec(String(volumeSpec)) {
                config.mounts.append(fs)
            }
        }

        // -e / --env (deduplicated by key, last wins — Docker semantics)
        var env = imageConfig.process.environment
        for envSpec in command.value(short: "e", long: "env")?.split(separator: ",") ?? [] {
            env.append(String(envSpec))
        }
        config.initProcess.environment = try service.secrets.resolveEnvironment(Self.deduplicateEnv(env))

        // --cpus / --memory
        if let cpus = command.value("cpus").flatMap(Int.init) {
            config.resources.cpus = cpus
        }
        if let memory = command.value("memory").flatMap(Self.parseMemory) {
            config.resources.memoryInBytes = memory
        }

        // Security-related runtime options.
        config.readOnly = command.has("read-only")
        config.privileged = command.has("privileged")
        config.capAdd = Self.parseCapabilities(command.value("cap-add"))
        config.capDrop = Self.parseCapabilities(command.value("cap-drop"))
        config.securityOptions = command.value("security-opt")?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        if let shmSize = command.value("shm-size").flatMap(Self.parseMemory) {
            config.shmSize = shmSize
        }
        if let stopSignal = command.value("stop-signal"), !stopSignal.isEmpty {
            config.stopSignal = stopSignal
        }

        // --rm
        let autoRemove = command.has("rm")

        // Command override: `docker run image cmd args`
        if !imageArgs.isEmpty {
            if imageConfig.entrypoint.isEmpty {
                // No entrypoint in the image — the command replaces the whole
                // process (Docker semantics: command overrides Cmd, and with
                // no Entrypoint the Cmd is the entire process).
                config.initProcess.executable = imageArgs[0]
                config.initProcess.arguments = Array(imageArgs.dropFirst())
            } else {
                // Image has an entrypoint — preserve it and replace the image's
                // Cmd with the command args (Docker semantics).
                config.initProcess.arguments = imageArgs
            }
        }

        // Resolve named volumes to their host paths: the server needs the
        // volume image path as the mount source, not the bare volume name
        // (a bare name makes bootstrap fail with EOPNOTSUPP).
        config.mounts = try await resolveVolumeSources(config.mounts)

        return (config, autoRemove)
    }

    private static func parseCapabilities(_ input: String?) -> [String] {
        guard let input, !input.isEmpty else { return [] }
        return input
            .split(separator: ",")
            .map { cap in
                let upper = cap.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if upper.isEmpty || upper == "ALL" || upper.hasPrefix("CAP_") {
                    return upper
                }
                return "CAP_\(upper)"
            }
            .filter { !$0.isEmpty }
    }

    /// Run a `container` CLI subcommand, streaming its stdout to our own and
    /// throwing on failure. Used for operations with no XPC route (build,
    /// image tag/push/load/save, network/volume prune).
    private func runCLI(_ args: [String]) async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(args, timeout: .seconds(600))
        if !result.stdout.isEmpty {
            print(result.stdout, terminator: "")
        }
        if !result.stderr.isEmpty {
            FileHandle.standardError.write(Data(result.stderr.utf8))
        }
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "container \(args.joined(separator: " ")) failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }

    /// `docker build` — build an image from a Dockerfile/Containerfile.
    private func build(_ command: DockerCommand) async throws {
        let context = command.arguments.first ?? "."
        var args = ["build", "--progress", "plain"]
        if let tag = command.value("t") ?? command.value("tag") {
            args += ["-t", tag]
        }
        if let file = command.value("f") ?? command.value("file") {
            args += ["-f", file]
        }
        for arg in command.value("build-arg")?.split(separator: ",") ?? [] {
            args += ["--build-arg", String(arg)]
        }
        if command.has("no-cache") { args += ["--no-cache"] }
        if let platform = command.value("platform") { args += ["--platform", platform] }
        args.append(context)
        try await runCLI(args)
    }

    /// `docker prune` — remove all stopped containers.
    private func prune(_ command: DockerCommand) async throws {
        let containers = try await service.listContainers(filters: .all)
        var removed = 0
        for c in containers where c.status == .stopped {
            try await service.deleteContainer(id: c.id, force: true)
            print("Deleted container \(c.configuration.id)")
            removed += 1
        }
        print("Total reclaimed space: \(removed) container(s)")
    }

    /// `docker tag` — create a new reference for an existing image.
    private func tag(_ command: DockerCommand) async throws {
        guard command.arguments.count >= 2 else {
            throw DockerShimError.missingArgument("SOURCE_IMAGE[:TAG] TARGET_IMAGE[:TAG]")
        }
        try await runCLI(["image", "tag", command.arguments[0], command.arguments[1]])
    }

    /// `docker push` — push an image to a registry.
    private func push(_ command: DockerCommand) async throws {
        guard let ref = command.arguments.first else {
            throw DockerShimError.missingArgument("NAME[:TAG]")
        }
        try await runCLI(["image", "push", ref])
    }

    /// `docker load` — load an image from a tar archive.
    private func load(_ command: DockerCommand) async throws {
        guard let file = command.value("i") ?? command.value("input") else {
            throw DockerShimError.missingArgument("input file (-i)")
        }
        try await runCLI(["image", "load", "-i", file])
    }

    /// `docker save` — save one or more images to a tar archive.
    private func save(_ command: DockerCommand) async throws {
        guard !command.arguments.isEmpty else {
            throw DockerShimError.missingArgument("IMAGE")
        }
        var args = ["image", "save"]
        if let out = command.value("o") ?? command.value("output") {
            args += ["-o", out]
        }
        args += command.arguments
        try await runCLI(args)
    }

    /// `docker scan` — scan image vulnerabilities using Trivy.
    private func scan(_ command: DockerCommand) async throws {
        guard let reference = command.arguments.first else {
            throw DockerShimError.missingArgument("IMAGE")
        }
        let severities = command.value("severity")?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty } ?? ["CRITICAL", "HIGH", "MEDIUM", "LOW"]

        let report = try await service.images.scan(reference: reference, severities: severities)
        if (command.value("format") ?? "").lowercased() == "json" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Image: \(report.imageReference)")
        print("Scanned at: \(ISO8601DateFormatter().string(from: report.scannedAt))")
        for severity in ["CRITICAL", "HIGH", "MEDIUM", "LOW"] {
            let count = report.totalBySeverity[severity, default: 0]
            print("\(severity): \(count)")
        }
        if report.findings.isEmpty {
            print("No vulnerabilities found.")
            return
        }
        print("")
        let headers = ["VulnerabilityID", "Severity", "Package", "Installed", "Fixed"]
        let rows = report.findings.prefix(200).map { finding in
            [finding.vulnerabilityID, finding.severity, finding.packageName, finding.installedVersion ?? "-", finding.fixedVersion ?? "-"]
        }
        Self.printTable(headers: headers, rows: rows)
    }

    /// `docker secret` — Keychain-backed secret management.
    private func secret(_ command: DockerCommand) async throws {
        let action = "secret.\(command.subSubcommand ?? "unknown")"
        do {
            switch command.subSubcommand {
            case "ls":
                let names = try service.secrets.listSecretNames()
                print("NAME")
                for name in names {
                    print(name)
                }
            case "create":
                guard let name = command.arguments.first else {
                    throw DockerShimError.missingArgument("SECRET_NAME")
                }
                let source = command.arguments.dropFirst().first
                let value: String
                if let source, source != "-" {
                    value = try String(contentsOfFile: source, encoding: .utf8)
                } else {
                    let data = FileHandle.standardInput.readDataToEndOfFile()
                    value = String(decoding: data, as: UTF8.self)
                }
                try service.secrets.setSecret(name: name, value: value.trimmingCharacters(in: .newlines))
                print(name)
            case "inspect":
                let names = command.arguments
                guard !names.isEmpty else { throw DockerShimError.missingArgument("SECRET_NAME") }
                let existing = Set(try service.secrets.listSecretNames())
                for name in names where !existing.contains(name) {
                    throw BackendError.notFound("secret '\(name)'")
                }
                let payload = names.map { ["Name": $0] }
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            case "rm", "remove":
                let names = command.arguments
                guard !names.isEmpty else { throw DockerShimError.missingArgument("SECRET_NAME") }
                for name in names {
                    try service.secrets.deleteSecret(named: name)
                    print(name)
                }
            default:
                throw DockerShimError.unsupportedCommand("secret \(command.subSubcommand ?? "")")
            }
            await auditLogger.record(action: action, target: command.arguments.first, succeeded: true)
        } catch {
            await auditLogger.record(action: action, target: command.arguments.first, succeeded: false, detail: error.localizedDescription)
            throw error
        }
    }

    /// Recreate a container with a modified configuration (stop, delete,
    /// recreate, start). Used by `network connect`/`disconnect` since the
    /// runtime does not support live network mutation.
    private func recreateContainer(id: String, configuration: ContainerConfiguration) async throws {
        try await service.stopContainer(id: id)
        try await service.deleteContainer(id: id, force: true)
        try await service.createContainer(configuration: configuration)
        try await service.bootstrapContainer(id: id)
        try await service.startProcess(containerId: id, processId: id)
    }

    /// `docker network connect` — attach a container to a network.
    private func networkConnect(_ command: DockerCommand) async throws {
        guard command.arguments.count >= 2 else {
            throw DockerShimError.missingArgument("NETWORK CONTAINER")
        }
        let network = command.arguments[0]
        let containerID = command.arguments[1]
        let resolved = try await resolveContainerID(containerID)
        let container = try await service.getContainer(id: resolved)
        var config = container.configuration
        let already = config.networks.contains { $0.network == network }
        if !already {
            config.networks.append(AttachmentConfiguration(
                network: network,
                options: AttachmentOptions(hostname: config.id, mtu: 1280)
            ))
        }
        try await recreateContainer(id: resolved, configuration: config)
        print(resolved)
    }

    /// `docker network disconnect` — detach a container from a network.
    private func networkDisconnect(_ command: DockerCommand) async throws {
        guard command.arguments.count >= 2 else {
            throw DockerShimError.missingArgument("NETWORK CONTAINER")
        }
        let network = command.arguments[0]
        let containerID = command.arguments[1]
        let resolved = try await resolveContainerID(containerID)
        let container = try await service.getContainer(id: resolved)
        var config = container.configuration
        config.networks.removeAll { $0.network == network }
        try await recreateContainer(id: resolved, configuration: config)
        print(resolved)
    }

    /// `docker network prune` — remove networks with no container connections.
    private func networkPrune() async throws {
        try await runCLI(["network", "prune"])
    }

    /// `docker volume prune` — remove volumes with no container references.
    private func volumePrune() async throws {
        try await runCLI(["volume", "prune"])
    }

    /// `docker system prune` — remove unused containers, images, networks and
    /// volumes (extended with `--builder` to also delete the buildkit cache).
    private func systemPrune(_ command: DockerCommand) async throws {
        let all = command.has("a") || command.has("all")
        if command.has("builder") {
            try await service.deleteBuildkitBuilder()
        }
        try await service.images.prune(all: all)
        // Remove stopped containers.
        let containers = try await service.listContainers(filters: .all)
        for c in containers where c.status == .stopped {
            try? await service.deleteContainer(id: c.id, force: true)
        }
    }

    private func stop(_ command: DockerCommand) async throws {
        let ids = command.arguments
        guard !ids.isEmpty else { throw DockerShimError.missingArgument("container") }
        for id in ids {
            let resolved = try await resolveContainerID(id)
            try await service.stopContainer(id: resolved)
            print(resolved.prefix(12))
        }
    }

    private func rm(_ command: DockerCommand) async throws {
        let ids = command.arguments
        guard !ids.isEmpty else { throw DockerShimError.missingArgument("container") }
        let force = command.has("f") || command.has("force")
        for id in ids {
            let resolved = try await resolveContainerID(id)
            if force {
                try? await service.killContainer(id: resolved, signal: "SIGKILL")
            }
            try await service.deleteContainer(id: resolved, force: force)
            print(resolved.prefix(12))
        }
    }

    private func kill(_ command: DockerCommand) async throws {
        let ids = command.arguments
        guard !ids.isEmpty else { throw DockerShimError.missingArgument("container") }
        let signal = command.value("signal") ?? "SIGKILL"
        for id in ids {
            let resolved = try await resolveContainerID(id)
            try await service.killContainer(id: resolved, signal: signal)
            print(resolved.prefix(12))
        }
    }

    private func start(_ command: DockerCommand) async throws {
        let ids = command.arguments
        guard !ids.isEmpty else { throw DockerShimError.missingArgument("container") }
        for id in ids {
            let resolved = try await resolveContainerID(id)
            try await service.bootstrapContainer(id: resolved)
            try await service.startProcess(containerId: resolved, processId: resolved)
            print(resolved.prefix(12))
        }
    }

    private func restart(_ command: DockerCommand) async throws {
        let ids = command.arguments
        guard !ids.isEmpty else { throw DockerShimError.missingArgument("container") }
        for id in ids {
            let resolved = try await resolveContainerID(id)
            try await service.stopContainer(id: resolved)
            try await service.bootstrapContainer(id: resolved)
            try await service.startProcess(containerId: resolved, processId: resolved)
            print(resolved.prefix(12))
        }
    }

    // MARK: - Images

    private func images(_ command: DockerCommand) async throws {
        // `docker images` and `docker image ls`
        if command.subSubcommand == "pull" {
            try await pull(command)
            return
        }
        if command.subSubcommand == "rm" || command.subSubcommand == "delete" {
            let ids = command.arguments
            guard !ids.isEmpty else { throw DockerShimError.missingArgument("image") }
            try await service.images.delete(ids)
            return
        }
        if command.subSubcommand == "tag" {
            guard command.arguments.count >= 2 else { throw DockerShimError.missingArgument("source and target") }
            try await service.images.tag(command.arguments[0], command.arguments[1])
            return
        }
        if command.subSubcommand == "inspect" {
            guard let reference = command.arguments.first else { throw DockerShimError.missingArgument("image") }
            let info = try await inspectImage(reference)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload: [String: Any] = [
                "reference": info.image.reference,
                "digest": info.image.digest,
                "entrypoint": info.process.executable,
                "cmd": info.process.arguments,
                "env": info.process.environment,
                "workingDir": info.process.workingDirectory,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return
        }

        let images = try await service.images.list()
        let quiet = command.has("q") || command.has("quiet")
        if quiet {
            for image in images {
                print(image.id)
            }
            return
        }
        let headers = ["REPOSITORY", "TAG", "IMAGE ID", "CREATED", "SIZE"]
        var rows: [[String]] = []
        for image in images {
            let repo = image.repository
            let tag = image.tag ?? "<none>"
            let id = String(image.id.prefix(12))
            let size = Self.formatBytes(image.size)
            let created = Self.relativeTime(image.creationDate)
            rows.append([repo, tag, id, created, size])
        }
        Self.printTable(headers: headers, rows: rows)
    }

    private func pull(_ command: DockerCommand) async throws {
        guard let reference = command.arguments.first else {
            throw DockerShimError.missingArgument("image")
        }
        try await service.images.pull(reference)
        print("\(reference): Pulled")
    }

    // MARK: - Logs

    private func logs(_ command: DockerCommand) async throws {
        guard let id = command.arguments.first else {
            throw DockerShimError.missingArgument("container")
        }
        let resolved = try await resolveContainerID(id)
        let follow = command.has("f") || command.has("follow")
        let tail = command.value("tail").flatMap(Int.init)
        try await streamLogs(id: resolved, follow: follow, tail: tail)
    }

    private func streamLogs(id: String, follow: Bool, tail: Int? = nil) async throws {
        let logService = LogService()
        let stream = logService.logs(for: id, follow: follow, tail: tail)
        if !follow {
            for try await line in stream {
                print(line.text)
            }
            return
        }
        // Follow mode: print logs until the container exits, then stop — the
        // log handles stay open after exit, so race the log stream against a
        // poller on the container state (like `docker run` attached mode).
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await line in stream {
                    print(line.text)
                }
            }
            group.addTask {
                while true {
                    try await Task.sleep(for: .milliseconds(500))
                    let containers = try await service.listContainers(filters: .all)
                    guard let container = containers.first(where: { $0.id == id }) else {
                        return // container removed (e.g. --rm)
                    }
                    if container.status != .running {
                        return
                    }
                }
            }
            // Whichever finishes first (logs exhausted or container stopped)
            // ends the other.
            try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Exec

    private func exec(_ command: DockerCommand) async throws {
        guard let id = command.arguments.first else {
            throw DockerShimError.missingArgument("container")
        }
        let execArgs = Array(command.arguments.dropFirst())
        let resolved = try await resolveContainerID(id)
        let exitCode = try await execInContainer(
            id: resolved,
            args: execArgs,
            terminal: command.has("t") || command.has("tty")
        )
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }

    /// Run a command inside a container, streaming its output to our own
    /// stdout/stderr, and return its exit code.
    private func execInContainer(id: String, args: [String], terminal: Bool = false) async throws -> Int32 {
        guard let executable = args.first else {
            throw DockerShimError.missingArgument("command")
        }
        let processConfig = ProcessConfiguration(
            executable: executable,
            arguments: Array(args.dropFirst()),
            environment: [],
            workingDirectory: "/",
            terminal: terminal,
            user: .raw(userString: "root"),
            supplementalGroups: [],
            rlimits: []
        )
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
        try await service.createProcess(
            containerId: id,
            processId: processId,
            configuration: processConfig,
            stdio: [nil, stdoutPipe.fileHandleForWriting, stderrPipe.fileHandleForWriting]
        )
        try await service.startProcess(containerId: id, processId: processId)
        let exitCode = try await service.waitForProcess(containerId: id, processId: processId)
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        return exitCode
    }

    /// `docker top` — list the processes running inside a container. The
    /// runtime has no process-listing API, so this runs `ps` inside the
    /// container (best-effort; requires `ps` to be present in the image).
    private func top(_ command: DockerCommand) async throws {
        guard let id = command.arguments.first else {
            throw DockerShimError.missingArgument("container")
        }
        let resolved = try await resolveContainerID(id)
        let psArgs = command.arguments.dropFirst().first ?? "aux"
        let exitCode = try await execInContainer(id: resolved, args: ["ps", psArgs])
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }

    /// `docker pause` — freeze a container's processes. The runtime has no
    /// process-freeze API, so this sends SIGSTOP to the container (best-effort
    /// approximation of docker's pause).
    private func pause(_ command: DockerCommand) async throws {
        guard let id = command.arguments.first else {
            throw DockerShimError.missingArgument("container")
        }
        let resolved = try await resolveContainerID(id)
        try await service.killContainer(id: resolved, signal: "SIGSTOP")
        print(resolved)
    }

    /// `docker unpause` — resume a paused container (SIGCONT).
    private func unpause(_ command: DockerCommand) async throws {
        guard let id = command.arguments.first else {
            throw DockerShimError.missingArgument("container")
        }
        let resolved = try await resolveContainerID(id)
        try await service.killContainer(id: resolved, signal: "SIGCONT")
        print(resolved)
    }

    /// `docker events` — stream container lifecycle events. The runtime has no
    /// event stream, so this polls the container list and emits docker-style
    /// events when state changes (create/start/stop/die/destroy).
    private func events(_ command: DockerCommand) async throws {
        // Optional `--filter type=container` / `--filter container=NAME`.
        var typeFilter: String?
        var containerFilter: String?
        if let filterValue = command.value("f") ?? command.value("filter") {
            for filter in filterValue.split(separator: ",") {
                let parts = filter.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = String(parts[0])
                let value = String(parts[1])
                if key == "type" { typeFilter = value }
                if key == "container" { containerFilter = value }
            }
        }
        if let typeFilter, typeFilter != "container" {
            // Only container events are supported.
            return
        }

        var previous: [String: RuntimeStatus] = [:]
        while true {
            let containers = try await service.listContainers(filters: .all)
            var current: [String: RuntimeStatus] = [:]
            for c in containers {
                current[c.id] = c.status
            }

            // New containers.
            for (id, status) in current where previous[id] == nil {
                if let containerFilter, !id.contains(containerFilter) { continue }
                emitEvent(action: "create", id: id)
                if status == .running {
                    emitEvent(action: "start", id: id)
                }
            }
            // Status changes.
            for (id, status) in current {
                guard let old = previous[id], old != status else { continue }
                if let containerFilter, !id.contains(containerFilter) { continue }
                switch status {
                case .running:
                    emitEvent(action: "start", id: id)
                case .stopped:
                    emitEvent(action: "die", id: id)
                case .stopping:
                    emitEvent(action: "stop", id: id)
                case .unknown:
                    break
                }
            }
            // Removed containers.
            for id in previous.keys where current[id] == nil {
                if let containerFilter, !id.contains(containerFilter) { continue }
                emitEvent(action: "destroy", id: id)
            }

            previous = current
            try await Task.sleep(for: .seconds(1))
        }
    }

    /// Print a docker-style event line.
    private func emitEvent(action: String, id: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("\(timestamp) container \(action) \(id)")
    }

    // MARK: - Copy

    private func cp(_ command: DockerCommand) async throws {
        guard command.arguments.count == 2 else {
            throw DockerShimError.missingArgument("SRC_PATH and DEST_PATH")
        }
        let src = command.arguments[0]
        let dest = command.arguments[1]
        // `docker cp CONTAINER:SRC DEST` copies out; `docker cp SRC CONTAINER:DEST`
        // copies in.
        if let (container, path) = Self.splitContainerPath(src) {
            let resolved = try await resolveContainerID(container)
            try await service.copyOut(id: resolved, source: path, destination: dest)
        } else if let (container, path) = Self.splitContainerPath(dest) {
            let resolved = try await resolveContainerID(container)
            try await service.copyIn(id: resolved, source: src, destination: path)
        } else {
            throw DockerShimError.missingArgument("CONTAINER:PATH")
        }
    }

    /// Split `CONTAINER:PATH` into its two parts.
    private static func splitContainerPath(_ spec: String) -> (String, String)? {
        guard let colon = spec.firstIndex(of: ":") else { return nil }
        let container = String(spec[..<colon])
        let path = String(spec[spec.index(after: colon)...])
        guard !container.isEmpty, !path.isEmpty else { return nil }
        return (container, path)
    }

    // MARK: - Stats

    private func stats(_ command: DockerCommand) async throws {
        let ids = command.arguments
        guard !ids.isEmpty else { throw DockerShimError.missingArgument("container") }
        let statsService = StatsService()
        print("CONTAINER ID   CPU %   MEM USAGE / LIMIT   NET I/O   BLOCK I/O   PIDS")
        for id in ids {
            let resolved = try await resolveContainerID(id)
            for try await s in statsService.stats(for: resolved, interval: .seconds(2)) {
                let cpu = s.cpuUsageUsec.map { String(format: "%.2f", Double($0) / 1_000_000) } ?? "-"
                let mem = s.memoryUsageBytes.map(Self.formatBytes) ?? "-"
                let memLimit = s.memoryLimitBytes.map(Self.formatBytes) ?? "-"
                let net = "\(s.networkRxBytes.map(Self.formatBytes) ?? "-") / \(s.networkTxBytes.map(Self.formatBytes) ?? "-")"
                let block = "\(s.blockReadBytes.map(Self.formatBytes) ?? "-") / \(s.blockWriteBytes.map(Self.formatBytes) ?? "-")"
                let pids = s.numProcesses.map(String.init) ?? "-"
                print("\(resolved.prefix(12))   \(cpu)   \(mem) / \(memLimit)   \(net)   \(block)   \(pids)")
            }
        }
    }

    // MARK: - Port

    private func port(_ command: DockerCommand) async throws {
        guard let id = command.arguments.first else {
            throw DockerShimError.missingArgument("container")
        }
        let resolved = try await resolveContainerID(id)
        let container = try await service.getContainer(id: resolved)
        for p in container.configuration.publishedPorts {
            print("\(p.containerPort)/\(p.proto.rawValue) -> \(p.hostAddress):\(p.hostPort)")
        }
    }

    // MARK: - Wait

    private func wait(_ command: DockerCommand) async throws {
        let ids = command.arguments
        guard !ids.isEmpty else { throw DockerShimError.missingArgument("container") }
        for id in ids {
            let resolved = try await resolveContainerID(id)
            let code = try await service.waitForProcess(containerId: resolved, processId: resolved)
            print(code)
        }
    }

    // MARK: - Compose

    private func compose(_ command: DockerCommand) async throws {
        // `docker compose version` and `docker compose ls` do not need a
        // compose file, so handle them before parsing.
        if command.subSubcommand == "version" {
            print("Docker Compose version v2.24.0 (macker)")
            return
        }
        if command.subSubcommand == "top" {
            throw DockerShimError.unsupportedCommand("compose top")
        }
        if command.subSubcommand == "ls" {
            let containers = try await service.listContainers(filters: .all)
            var projects: [String: [String]] = [:]
            for container in containers {
                if let projectName = container.configuration.labels[ComposeOrchestrator.ComposeLabel.project] {
                    projects[projectName, default: []].append(container.id)
                }
            }
            print("NAME   SERVICES   STATUS")
            for (name, containers) in projects.sorted(by: { $0.key < $1.key }) {
                print("\(name)   \(containers.count)   running")
            }
            return
        }

        // `docker compose -f file.yml up -d` — the file may come from `-f`
        // (or `--file`) or default to `./docker-compose.yml`.
        let file = command.value("f") ?? command.value("file") ?? "docker-compose.yml"
        let parser = ComposeParser()
        let project = try parser.parse(fileAt: file)
        let orchestrator = ComposeOrchestrator(service: service)

        switch command.subSubcommand {
        case "up":
            let detached = command.has("d") || command.has("detach")
            try await orchestrator.up(project: project, filePath: file, detached: detached)
            if detached {
                for name in try ServiceResolver.resolve(project) {
                    let containerName = ComposeOrchestrator.containerName(
                        project: project.name,
                        service: name,
                        config: project.services[name]
                    )
                    print("Container \(containerName)  Started")
                }
            }
        case "down":
            let removeVolumes = command.has("v") || command.has("volumes")
            try await orchestrator.down(project: project, removeVolumes: removeVolumes)
        case "ps":
            let containers = try await orchestrator.ps(project: project)
            print("NAME   SERVICE   STATUS")
            for container in containers {
                let serviceName = container.configuration.labels[ComposeOrchestrator.ComposeLabel.service] ?? "-"
                print("\(container.id)   \(serviceName)   \(container.status.rawValue)")
            }
        case "logs":
            let follow = command.has("f") || command.has("follow")
            let tail = command.value("tail").flatMap(Int.init)
            let serviceName = command.arguments.first
            try await orchestrator.logs(project: project, service: serviceName, follow: follow, tail: tail)
        case "stop":
            try await orchestrator.stop(project: project, services: command.arguments)
        case "start":
            try await orchestrator.start(project: project, services: command.arguments)
        case "restart":
            try await orchestrator.restart(project: project, services: command.arguments)
        case "pull":
            try await orchestrator.pull(project: project)
        case "config":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(project)
            print(String(decoding: data, as: UTF8.self))
        case "build":
            try await orchestrator.build(project: project, filePath: file)
        case "create":
            try await orchestrator.create(project: project, filePath: file)
        case "exec":
            guard let serviceName = command.arguments.first else {
                throw DockerShimError.missingArgument("SERVICE COMMAND")
            }
            let execArgs = Array(command.arguments.dropFirst())
            let containerName = ComposeOrchestrator.containerName(
                project: project.name,
                service: serviceName,
                config: project.services[serviceName]
            )
            let exitCode = try await execInContainer(
                id: containerName,
                args: execArgs,
                terminal: command.has("T") || command.has("tty")
            )
            if exitCode != 0 {
                throw ExitCode(exitCode)
            }
        case "images":
            let images = orchestrator.images(project: project)
            print("SERVICE   IMAGE")
            for (service, image) in images {
                print("\(service)   \(image)")
            }
        case "kill":
            let signal = command.value("s") ?? command.value("signal") ?? "SIGKILL"
            try await orchestrator.kill(project: project, services: command.arguments, signal: signal)
        case "port":
            guard let serviceName = command.arguments.first, let portStr = command.arguments.dropFirst().first else {
                throw DockerShimError.missingArgument("SERVICE PRIVATE_PORT")
            }
            guard let port = UInt16(portStr) else {
                throw DockerShimError.missingArgument("PRIVATE_PORT must be a number")
            }
            if let host = try await orchestrator.port(project: project, serviceName: serviceName, containerPort: port) {
                print(host)
            }
        case "rm":
            let force = command.has("f") || command.has("force")
            try await orchestrator.rm(project: project, services: command.arguments, force: force)
        case "run":
            guard let serviceName = command.arguments.first else {
                throw DockerShimError.missingArgument("SERVICE COMMAND")
            }
            let runArgs = Array(command.arguments.dropFirst())
            let exitCode = try await orchestrator.run(
                project: project,
                serviceName: serviceName,
                command: runArgs,
                filePath: file
            )
            if exitCode != 0 {
                throw ExitCode(exitCode)
            }
        default:
            throw DockerShimError.unsupportedCommand("compose \(command.subSubcommand ?? "")")
        }
    }

    // MARK: - Inspect

    private func inspect(_ command: DockerCommand) async throws {
        guard let id = command.arguments.first else {
            throw DockerShimError.missingArgument("container")
        }
        let resolved = try await resolveContainerID(id)
        let container = try await service.getContainer(id: resolved)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(container)
        print(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Networks

    private func network(_ command: DockerCommand) async throws {
        switch command.subSubcommand {
        case "ls":
            let networks = try await service.listNetworks()
            print("NETWORK ID   NAME   DRIVER   SCOPE")
            for network in networks {
                print("\(network.id.prefix(12))   \(network.name)   \(network.configuration.plugin)   local")
            }
        case "create":
            guard let name = command.arguments.first else {
                throw DockerShimError.missingArgument("network name")
            }
            let config = NetworkConfiguration(name: name, plugin: "vmnet")
            let resource = try await service.createNetwork(configuration: config)
            print(resource.id)
        case "rm", "remove":
            let ids = command.arguments
            guard !ids.isEmpty else { throw DockerShimError.missingArgument("network") }
            for id in ids {
                try await service.deleteNetwork(id: id)
                print(id)
            }
        case "inspect":
            let networks = try await service.listNetworks()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            for id in command.arguments {
                if let network = networks.first(where: { $0.id == id || $0.name == id }) {
                    let data = try encoder.encode(network)
                    print(String(decoding: data, as: UTF8.self))
                }
            }
        case "connect":
            try await networkConnect(command)
        case "disconnect":
            try await networkDisconnect(command)
        case "prune":
            try await networkPrune()
        default:
            throw DockerShimError.unsupportedCommand("network \(command.subSubcommand ?? "")")
        }
    }

    // MARK: - Volumes

    private func volume(_ command: DockerCommand) async throws {
        switch command.subSubcommand {
        case "ls":
            let volumes = try await service.listVolumes()
            print("DRIVER   VOLUME NAME")
            for volume in volumes {
                print("\(volume.driver)   \(volume.name)")
            }
        case "create":
            let name = command.arguments.first ?? Self.randomName()
            let volume = try await service.createVolume(name: name)
            print(volume.name)
        case "rm", "remove":
            let ids = command.arguments
            guard !ids.isEmpty else { throw DockerShimError.missingArgument("volume") }
            for id in ids {
                try await service.deleteVolume(name: id)
                print(id)
            }
        case "inspect":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            for id in command.arguments {
                let volume = try await service.inspectVolume(id)
                let data = try encoder.encode(volume)
                print(String(decoding: data, as: UTF8.self))
            }
        case "prune":
            try await volumePrune()
        default:
            throw DockerShimError.unsupportedCommand("volume \(command.subSubcommand ?? "")")
        }
    }

    // MARK: - System

    private func system(_ command: DockerCommand) async throws {
        switch command.subSubcommand {
        case "df":
            let usage = try await service.systemDiskUsage()
            print("TYPE   TOTAL   ACTIVE   SIZE   RECLAIMABLE")
            if let total = usage.totalSize {
                print("Images   \(Self.formatBytes(total))")
            }
            if let reclaimable = usage.reclaimableSize {
                print("Containers   \(Self.formatBytes(reclaimable))")
            }
        case "prune":
            try await systemPrune(command)
        default:
            throw DockerShimError.unsupportedCommand("system \(command.subSubcommand ?? "")")
        }
    }

    private func version(_ command: DockerCommand) async throws {
        print(AppleDockerCLICommand.clientVersion)
        do {
            let health = try await service.ping()
            print("container-apiserver \(health.apiServerVersion)")
        } catch {
            print("container-apiserver: unreachable")
        }
    }

    private func info(_ command: DockerCommand) async throws {
        let health = try await service.ping()
        print("Server Version: \(health.apiServerVersion)")
        print("Operating System: macOS")
        print("Architecture: arm64")
        print("App Root: \(health.appRoot)")
        print("Install Root: \(health.installRoot)")
    }

    // MARK: - Helpers

    /// Resolve a container name or short ID to a full ID.
    private func resolveContainerID(_ id: String) async throws -> String {
        let containers = try await service.listContainers()
        if let exact = containers.first(where: { $0.id == id || $0.configuration.id == id }) {
            return exact.id
        }
        if let prefix = containers.first(where: { $0.id.hasPrefix(id) }) {
            return prefix.id
        }
        throw BackendError.notFound("container \(id)")
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

    /// Inspect an image and extract the fields needed to build a container.
    private func inspectImage(_ reference: String) async throws -> ImageProcessInfo {
        // Use the CLI inspect to get the image's default config.
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
                let size: UInt64?
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
            size: Int64(image.configuration.descriptor.size ?? 0),
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

    /// Parse a docker port spec like `8080:80`, `127.0.0.1:8080:80`, `80`.
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

    /// Parse a docker volume spec like `name:/path`, `/host:/container`, `/host:/container:ro`.
    static func parseVolumeSpec(_ spec: String) -> Filesystem? {
        let parts = spec.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return nil }
        let source = parts[0]
        let destination = parts[1]
        let options: MountOptions = (parts.count >= 3 && parts[2].contains("ro")) ? ["ro"] : []

        if source.hasPrefix("/") {
            // Bind mount (virtiofs).
            return .virtiofs(source: source, destination: destination, options: options)
        } else {
            // Named volume. The daemon resolves the volume's host path from its
            // name; pass the name as the source.
            return .volume(name: source, format: "ext4", source: source, destination: destination, options: options)
        }
    }

    /// Resolve named-volume mounts to their host paths. The server needs the
    /// volume image path as the mount source; a bare volume name makes
    /// bootstrap fail with EOPNOTSUPP. Named volumes that don't exist yet are
    /// created (Docker auto-creates them), and bind-mount host directories
    /// that don't exist are created too.
    private func resolveVolumeSources(_ mounts: [Filesystem]) async throws -> [Filesystem] {
        var resolved: [Filesystem] = []
        for mount in mounts {
            if let name = mount.volumeName {
                let volume: VolumeConfiguration
                if let existing = try? await service.inspectVolume(name) {
                    volume = existing
                } else {
                    volume = try await service.createVolume(name: name)
                }
                resolved.append(Filesystem(
                    type: mount.type,
                    source: volume.source,
                    destination: mount.destination,
                    options: mount.options
                ))
            } else if mount.isVirtiofs {
                // Docker creates the host directory for a bind mount if it
                // doesn't exist; virtiofs needs the source to exist.
                try FileManager.default.createDirectory(
                    atPath: mount.source,
                    withIntermediateDirectories: true
                )
                resolved.append(mount)
            } else {
                resolved.append(mount)
            }
        }
        return resolved
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

    static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Generate a docker-style random container name.
    static func randomName() -> String {
        let adjectives = ["admiring", "angry", "brave", "clever", "cool", "dazzling", "eager", "elastic", "focused", "gallant"]
        let nouns = ["albatross", "badger", "camel", "dolphin", "eagle", "falcon", "gazelle", "heron", "ibis", "jaguar"]
        let a = adjectives.randomElement() ?? "clever"
        let n = nouns.randomElement() ?? "badger"
        return "\(a)_\(n)"
    }
}
