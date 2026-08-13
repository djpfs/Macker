//===----------------------------------------------------------------------===//
// ContainerService — high-level facade over the container runtime.
//
// This is the single entry point used by the GUI and CLI. It composes the XPC
// client (containers, networks, volumes, system), the CLI-fallback image
// service, daemon lifecycle, and platform resolution. The protocol abstraction
// lets us swap the XPC implementation for Apple's ContainerClientKit when it
// ships, without touching callers.
//===----------------------------------------------------------------------===//

import Foundation

/// The operations the app needs from the container runtime.
public protocol ContainerServiceProtocol: Sendable {
    // Containers
    func listContainers(filters: ContainerListFilters) async throws -> [ContainerSnapshot]
    func getContainer(id: String) async throws -> ContainerSnapshot
    func createContainer(
        configuration: ContainerConfiguration,
        options: ContainerCreateOptions,
        kernel: Kernel?,
        initImage: String?,
        runtimeData: Data?
    ) async throws
    func bootstrapContainer(id: String, stdio: [FileHandle?], dynamicEnv: [String: String]) async throws
    func startProcess(containerId: String, processId: String) async throws
    func waitForProcess(containerId: String, processId: String) async throws -> Int32
    func killContainer(id: String, signal: String) async throws
    func stopContainer(id: String, opts: ContainerStopOptions) async throws
    func deleteContainer(id: String, force: Bool) async throws
    func containerDiskUsage(id: String) async throws -> UInt64
    func createProcess(
        containerId: String,
        processId: String,
        configuration: ProcessConfiguration,
        stdio: [FileHandle?]
    ) async throws
    func containerLogs(id: String) async throws -> [FileHandle]
    func dialContainer(id: String, port: UInt32) async throws -> FileHandle
    func copyIn(id: String, source: String, destination: String, mode: UInt32, createParents: Bool) async throws
    func copyOut(id: String, source: String, destination: String, createParents: Bool) async throws
    func containerStats(id: String) async throws -> ContainerStats
    func exportContainer(id: String, archive: URL) async throws

    // Networks
    func createNetwork(configuration: NetworkConfiguration) async throws -> NetworkResource
    func listNetworks() async throws -> [NetworkResource]
    func deleteNetwork(id: String) async throws

    // Volumes
    func createVolume(name: String, driver: String, driverOpts: [String: String], labels: [String: String]) async throws -> VolumeConfiguration
    func deleteVolume(name: String) async throws
    func listVolumes() async throws -> [VolumeConfiguration]
    func inspectVolume(_ name: String) async throws -> VolumeConfiguration
    func volumeDiskUsage(name: String) async throws -> UInt64

    // System
    func ping(timeout: Duration?) async throws -> SystemHealth
    func systemDiskUsage() async throws -> SystemDiskUsage
    func getDefaultKernel(for platform: SystemPlatform) async throws -> Kernel

    // Cleanup
    func deleteBuildkitBuilder() async throws

    // Builds
    func buildImage(
        context: String,
        tag: String?,
        dockerfile: String?,
        buildArgs: [String: String],
        noCache: Bool
    ) async throws -> String

    // Connection lifecycle
    func close()
}

/// XPC-backed implementation of ``ContainerServiceProtocol``.
public struct ContainerService: ContainerServiceProtocol, Sendable {
    private let client: ContainerAPIClient
    /// Image operations (CLI fallback).
    public let images: ImageService
    /// Daemon lifecycle.
    public let daemon: LaunchdManager
    /// Runtime install resolution.
    public let platform: PlatformResolver
    /// CLI fallback runner for operations without an XPC route.
    private let runner: ProcessRunner

    public init(
        client: ContainerAPIClient = ContainerAPIClient(),
        images: ImageService = ImageService(),
        daemon: LaunchdManager = LaunchdManager(),
        platform: PlatformResolver = PlatformResolver(),
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.client = client
        self.images = images
        self.daemon = daemon
        self.platform = platform
        self.runner = runner
    }

    // MARK: Containers

    public func listContainers(filters: ContainerListFilters = .all) async throws -> [ContainerSnapshot] {
        try await client.list(filters: filters)
    }

    public func getContainer(id: String) async throws -> ContainerSnapshot {
        try await client.get(id: id)
    }

    public func createContainer(
        configuration: ContainerConfiguration,
        options: ContainerCreateOptions = .default,
        kernel: Kernel? = nil,
        initImage: String? = nil,
        runtimeData: Data? = nil
    ) async throws {
        try await client.create(
            configuration: configuration,
            options: options,
            kernel: kernel,
            initImage: initImage,
            runtimeData: runtimeData
        )
    }

    public func bootstrapContainer(id: String, stdio: [FileHandle?] = [], dynamicEnv: [String: String] = [:]) async throws {
        try await client.bootstrap(id: id, stdio: stdio, dynamicEnv: dynamicEnv)
    }

    public func startProcess(containerId: String, processId: String) async throws {
        try await client.startProcess(containerId: containerId, processId: processId)
    }

    public func waitForProcess(containerId: String, processId: String) async throws -> Int32 {
        try await client.wait(containerId: containerId, processId: processId)
    }

    public func killContainer(id: String, signal: String = "SIGTERM") async throws {
        try await client.kill(id: id, signal: signal)
    }

    public func stopContainer(id: String, opts: ContainerStopOptions = .default) async throws {
        try await client.stop(id: id, opts: opts)
    }

    public func deleteContainer(id: String, force: Bool = false) async throws {
        try await client.delete(id: id, force: force)
    }

    public func containerDiskUsage(id: String) async throws -> UInt64 {
        try await client.diskUsage(id: id)
    }

    public func createProcess(
        containerId: String,
        processId: String,
        configuration: ProcessConfiguration,
        stdio: [FileHandle?] = []
    ) async throws {
        try await client.createProcess(
            containerId: containerId,
            processId: processId,
            configuration: configuration,
            stdio: stdio
        )
    }

    public func containerLogs(id: String) async throws -> [FileHandle] {
        try await client.logs(id: id)
    }

    public func dialContainer(id: String, port: UInt32) async throws -> FileHandle {
        try await client.dial(id: id, port: port)
    }

    public func copyIn(id: String, source: String, destination: String, mode: UInt32 = 0o644, createParents: Bool = true) async throws {
        try await client.copyIn(id: id, source: source, destination: destination, mode: mode, createParents: createParents)
    }

    public func copyOut(id: String, source: String, destination: String, createParents: Bool = true) async throws {
        try await client.copyOut(id: id, source: source, destination: destination, createParents: createParents)
    }

    public func containerStats(id: String) async throws -> ContainerStats {
        try await client.stats(id: id)
    }

    public func exportContainer(id: String, archive: URL) async throws {
        try await client.export(id: id, archive: archive)
    }

    // MARK: Networks

    public func createNetwork(configuration: NetworkConfiguration) async throws -> NetworkResource {
        try await client.networkCreate(configuration: configuration)
    }

    public func listNetworks() async throws -> [NetworkResource] {
        try await client.networkList()
    }

    public func deleteNetwork(id: String) async throws {
        try await client.networkDelete(id: id)
    }

    // MARK: Volumes

    public func createVolume(
        name: String,
        driver: String = "local",
        driverOpts: [String: String] = [:],
        labels: [String: String] = [:]
    ) async throws -> VolumeConfiguration {
        try await client.volumeCreate(name: name, driver: driver, driverOpts: driverOpts, labels: labels)
    }

    public func deleteVolume(name: String) async throws {
        try await client.volumeDelete(name: name)
    }

    public func listVolumes() async throws -> [VolumeConfiguration] {
        try await client.volumeList()
    }

    public func inspectVolume(_ name: String) async throws -> VolumeConfiguration {
        try await client.volumeInspect(name)
    }

    public func volumeDiskUsage(name: String) async throws -> UInt64 {
        try await client.volumeDiskUsage(name: name)
    }

    // MARK: System

    public func ping(timeout: Duration? = nil) async throws -> SystemHealth {
        try await client.ping(timeout: timeout)
    }

    public func systemDiskUsage() async throws -> SystemDiskUsage {
        // XPC-first: the apiserver returns real values when it implements the
        // route. Older/server builds may reply with no payload.
        let viaXPC = try await client.systemDiskUsage()
        if viaXPC.totalSize != nil || viaXPC.reclaimableSize != nil {
            return viaXPC
        }
        // CLI fallback: `container system df --format json` is authoritative
        // and always available. On failure return an empty report rather than
        // breaking the whole refresh.
        if let cli = try? await cliDiskUsage() {
            return cli
        }
        return SystemDiskUsage()
    }

    /// Parse disk usage from `container system df --format json`.
    private func cliDiskUsage() async throws -> SystemDiskUsage {
        let result = try await runner.run(["system", "df", "--format", "json"], timeout: .seconds(30))
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "container system df failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        guard let report = try? JSONDecoder().decode(CLIDiskUsageReport.self, from: Data(result.stdout.utf8)) else {
            throw BackendError.invalidResponse("could not parse container system df output")
        }
        let total = [report.containers?.sizeInBytes, report.images?.sizeInBytes, report.volumes?.sizeInBytes]
            .compactMap { $0 }
            .reduce(0, +)
        let reclaimable = [report.containers?.reclaimable, report.images?.reclaimable, report.volumes?.reclaimable]
            .compactMap { $0 }
            .reduce(0, +)
        return SystemDiskUsage(
            totalSize: total,
            reclaimableSize: reclaimable,
            imagesSize: report.images?.sizeInBytes,
            containersSize: report.containers?.sizeInBytes,
            volumesSize: report.volumes?.sizeInBytes
        )
    }

    public func getDefaultKernel(for platform: SystemPlatform) async throws -> Kernel {
        try await client.getDefaultKernel(for: platform)
    }

    // MARK: Cleanup

    /// Delete the buildkit builder container if present. The builder holds the
    /// BuildKit cache (snapshots from `container build`), which can consume
    /// tens of GB; deleting it frees that space. It is recreated on the next
    /// build.
    public func deleteBuildkitBuilder() async throws {
        let containers = try await listContainers(filters: .all)
        if let builder = containers.first(where: { $0.id == "buildkit" }) {
            try await deleteContainer(id: builder.id, force: true)
        }
    }

    /// Build an image from a context directory via the `container build` CLI.
    /// Returns the captured build output (stdout, or stderr on failure).
    public func buildImage(
        context: String,
        tag: String?,
        dockerfile: String?,
        buildArgs: [String: String],
        noCache: Bool
    ) async throws -> String {
        var args = ["build", "--progress", "plain"]
        if let tag, !tag.isEmpty { args += ["-t", tag] }
        if let dockerfile, !dockerfile.isEmpty { args += ["-f", dockerfile] }
        for (key, value) in buildArgs { args += ["--build-arg", "\(key)=\(value)"] }
        if noCache { args += ["--no-cache"] }
        args.append(context)
        let result = try await runner.run(args, timeout: .seconds(1800))
        if !result.stdout.isEmpty { return result.stdout }
        if !result.stderr.isEmpty { return result.stderr }
        return ""
    }

    public func close() {
        client.close()
    }
}


/// Decodable shape of `container system df --format json`.
private struct CLIDiskUsageReport: Sendable, Codable {
    struct Category: Sendable, Codable {
        var active: UInt64?
        var reclaimable: UInt64?
        var sizeInBytes: UInt64?
        var total: UInt64?
    }
    var containers: Category?
    var images: Category?
    var volumes: Category?
}
