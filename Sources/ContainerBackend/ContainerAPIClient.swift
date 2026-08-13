//===----------------------------------------------------------------------===//
// ContainerAPIClient — a single XPC-backed client for container-apiserver.
//
// Mirrors the operations of apple/container's ContainerClient + NetworkClient +
// ClientVolume + ClientHealthCheck over one reusable connection. Image
// operations go through the separate `container-core-images` service, which is
// provided by ImageService via the CLI fallback until the XPC protocol for it
// is stabilized.
//===----------------------------------------------------------------------===//

import Foundation

/// A client for interacting with the container API server over XPC.
///
/// Holds a reusable XPC connection. All methods that operate on a specific
/// container take an `id` parameter.
public struct ContainerAPIClient: Sendable {
    public static let serviceIdentifier = "com.apple.container.apiserver"
    /// The name of the default network created automatically on first use.
    public static let defaultNetworkName = "default"
    /// The reserved name that indicates a container should have no network.
    public static let noNetworkName = "none"

    private let xpcClient: XPCClient

    /// Creates a new client with a connection to the API server.
    public init() {
        self.xpcClient = XPCClient(service: Self.serviceIdentifier)
    }

    /// Creates a client connected to an alternate service (used in tests).
    public init(serviceIdentifier: String) {
        self.xpcClient = XPCClient(service: serviceIdentifier)
    }

    public func setDisconnectHandler(_ handler: @escaping @Sendable () -> Void) {
        xpcClient.setDisconnectHandler(handler)
    }

    public func close() {
        xpcClient.close()
    }

    @discardableResult
    private func send(
        _ message: XPCMessage,
        timeout: Duration? = XPCClient.registrationTimeout
    ) async throws -> XPCMessage {
        try await xpcClient.send(message, responseTimeout: timeout)
    }
}

// MARK: - Containers

extension ContainerAPIClient {
    /// Create a new container with the given configuration.
    ///
    /// If `kernel` is `nil`, the API server's default kernel for the
    /// configuration's platform is fetched first.
    public func create(
        configuration: ContainerConfiguration,
        options: ContainerCreateOptions = .default,
        kernel: Kernel? = nil,
        initImage: String? = nil,
        runtimeData: Data? = nil
    ) async throws {
        let request = XPCMessage(route: .containerCreate)
        try request.setJSON(configuration, key: .containerConfig)
        let resolvedKernel: Kernel
        if let kernel {
            resolvedKernel = kernel
        } else {
            // All containers on Apple Silicon boot linux/arm64. The server's
            // default kernel is authoritative; a caller-provided kernel wins.
            resolvedKernel = try await getDefaultKernel(for: .linuxArm)
        }
        try request.setJSON(resolvedKernel, key: .kernel)
        try request.setJSON(options, key: .containerOptions)
        if let initImage {
            request.set(key: .initImage, value: initImage)
        }
        if let runtimeData {
            request.set(key: .runtimeData, value: runtimeData)
        }
        try await send(request)
    }

    /// List containers matching the given filters.
    public func list(filters: ContainerListFilters = .all) async throws -> [ContainerSnapshot] {
        let request = XPCMessage(route: .containerList)
        try request.setJSON(filters, key: .listFilters)
        let response = try await send(request, timeout: .seconds(10))
        return try response.decodeJSON([ContainerSnapshot].self, key: .containers)
    }

    /// Get the container for the provided id.
    public func get(id: String) async throws -> ContainerSnapshot {
        let containers = try await list(filters: ContainerListFilters(ids: [id]))
        guard let container = containers.first else {
            throw BackendError.notFound("container \(id)")
        }
        return container
    }

    /// Bootstrap the container's init process.
    public func bootstrap(
        id: String,
        stdio: [FileHandle?] = [],
        dynamicEnv: [String: String] = [:]
    ) async throws {
        let request = XPCMessage(route: .containerBootstrap)
        for (index, handle) in stdio.enumerated() {
            if let handle {
                switch index {
                case 0: request.set(key: .stdin, value: handle)
                case 1: request.set(key: .stdout, value: handle)
                case 2: request.set(key: .stderr, value: handle)
                default: break
                }
            }
        }
        // Only send dynamicEnv when non-empty: an empty `{}` makes the server
        // fail bootstrap with EOPNOTSUPP.
        if !dynamicEnv.isEmpty {
            try request.setJSON(dynamicEnv, key: .dynamicEnv)
        }
        request.set(key: .id, value: id)
        try await send(request)
    }

    /// Start a process that was created inside a container. The init process
    /// is created by ``bootstrap(id:stdio:dynamicEnv:)`` and must be started
    /// explicitly before it runs.
    public func startProcess(containerId: String, processId: String) async throws {
        let request = XPCMessage(route: .containerStartProcess)
        request.set(key: .id, value: containerId)
        request.set(key: .processIdentifier, value: processId)
        try await send(request)
    }

    /// Wait for a process to exit and return its exit code. Blocks until the
    /// process completes.
    public func wait(containerId: String, processId: String) async throws -> Int32 {
        let request = XPCMessage(route: .containerWait)
        request.set(key: .id, value: containerId)
        request.set(key: .processIdentifier, value: processId)
        let reply = try await send(request)
        return Int32(reply.int64(key: .exitCode))
    }

    /// Send a signal to the container.
    public func kill(id: String, signal: String) async throws {
        let request = XPCMessage(route: .containerKill)
        request.set(key: .id, value: id)
        request.set(key: .processIdentifier, value: id)
        request.set(key: .signal, value: signal)
        try await send(request)
    }

    /// Stop the container and all processes currently executing inside.
    public func stop(id: String, opts: ContainerStopOptions = .default) async throws {
        let request = XPCMessage(route: .containerStop)
        request.set(key: .id, value: id)
        try request.setJSON(opts, key: .stopOptions)
        try await send(request)
    }

    /// Delete the container along with any resources.
    public func delete(id: String, force: Bool = false) async throws {
        let request = XPCMessage(route: .containerDelete)
        request.set(key: .id, value: id)
        request.set(key: .forceDelete, value: force)
        try await send(request)
    }

    /// Get the disk usage for a container.
    public func diskUsage(id: String) async throws -> UInt64 {
        let request = XPCMessage(route: .containerDiskUsage)
        request.set(key: .id, value: id)
        let reply = try await send(request)
        return reply.uint64(key: .containerSize)
    }

    /// Create a new process inside a running container. The process is in a
    /// created state and must still be started.
    public func createProcess(
        containerId: String,
        processId: String,
        configuration: ProcessConfiguration,
        stdio: [FileHandle?] = []
    ) async throws {
        let request = XPCMessage(route: .containerCreateProcess)
        request.set(key: .id, value: containerId)
        request.set(key: .processIdentifier, value: processId)
        try request.setJSON(configuration, key: .processConfig)
        for (index, handle) in stdio.enumerated() {
            if let handle {
                switch index {
                case 0: request.set(key: .stdin, value: handle)
                case 1: request.set(key: .stdout, value: handle)
                case 2: request.set(key: .stderr, value: handle)
                default: break
                }
            }
        }
        try await send(request)
    }

    /// Get the log file handles for a container.
    public func logs(id: String) async throws -> [FileHandle] {
        let request = XPCMessage(route: .containerLogs)
        request.set(key: .id, value: id)
        let response = try await send(request)
        guard let fds = response.fileHandles(key: .logs) else {
            throw BackendError.invalidResponse("no log file handles returned for \(id)")
        }
        return fds
    }

    /// Dial a port on the container via vsock.
    public func dial(id: String, port: UInt32) async throws -> FileHandle {
        let request = XPCMessage(route: .containerDial)
        request.set(key: .id, value: id)
        request.set(key: .port, value: UInt64(port))
        let response = try await send(request)
        guard let handle = response.fileHandle(key: .fd) else {
            throw BackendError.invalidResponse("failed to get vsock fd for port \(port)")
        }
        return handle
    }

    /// Copy a file or directory from the host into the container.
    public func copyIn(id: String, source: String, destination: String, mode: UInt32 = 0o644, createParents: Bool = true) async throws {
        let request = XPCMessage(route: .containerCopyIn)
        request.set(key: .id, value: id)
        request.set(key: .sourcePath, value: source)
        request.set(key: .destinationPath, value: destination)
        request.set(key: .fileMode, value: UInt64(mode))
        request.set(key: .createParents, value: createParents)
        try await send(request, timeout: .seconds(300))
    }

    /// Copy a file or directory from the container to the host.
    public func copyOut(id: String, source: String, destination: String, createParents: Bool = true) async throws {
        let request = XPCMessage(route: .containerCopyOut)
        request.set(key: .id, value: id)
        request.set(key: .sourcePath, value: source)
        request.set(key: .destinationPath, value: destination)
        request.set(key: .createParents, value: createParents)
        try await send(request, timeout: .seconds(300))
    }

    /// Get resource usage statistics for a container.
    public func stats(id: String) async throws -> ContainerStats {
        let request = XPCMessage(route: .containerStats)
        request.set(key: .id, value: id)
        let response = try await send(request)
        return try response.decodeJSON(ContainerStats.self, key: .statistics)
    }

    /// Export a container's rootfs to an archive.
    public func export(id: String, archive: URL) async throws {
        let request = XPCMessage(route: .containerExport)
        request.set(key: .id, value: id)
        request.set(key: .archive, value: archive.path)
        try await send(request)
    }
}

// MARK: - Kernels

extension ContainerAPIClient {
    /// Fetch the default kernel that the API server uses to boot a VM for the
    /// given platform.
    public func getDefaultKernel(for platform: SystemPlatform) async throws -> Kernel {
        let request = XPCMessage(route: .getDefaultKernel)
        try request.setJSON(platform, key: .systemPlatform)
        let reply = try await send(request)
        guard let data = reply.data(key: .kernel) else {
            throw BackendError.invalidResponse("no default kernel returned for \(platform)")
        }
        return try JSONDecoder().decode(Kernel.self, from: data)
    }
}

// MARK: - Networks

extension ContainerAPIClient {
    /// Create a new network with the given configuration.
    public func networkCreate(configuration: NetworkConfiguration) async throws -> NetworkResource {
        let request = XPCMessage(route: .networkCreate)
        request.set(key: .networkId, value: configuration.id)
        try request.setJSON(configuration, key: .networkConfig)
        let response = try await send(request)
        return try response.decodeJSON(NetworkResource.self, key: .networkResource)
    }

    /// List all networks known to the API server.
    public func networkList() async throws -> [NetworkResource] {
        let request = XPCMessage(route: .networkList)
        let response = try await send(request, timeout: .seconds(1))
        return try response.decodeJSON([NetworkResource].self, key: .networkResources)
    }

    /// Delete the network with the given identifier.
    public func networkDelete(id: String) async throws {
        let request = XPCMessage(route: .networkDelete)
        request.set(key: .networkId, value: id)
        try await send(request)
    }
}

// MARK: - Volumes

extension ContainerAPIClient {
    /// Create a new volume.
    public func volumeCreate(
        name: String,
        driver: String = "local",
        driverOpts: [String: String] = [:],
        labels: [String: String] = [:]
    ) async throws -> VolumeConfiguration {
        let request = XPCMessage(route: .volumeCreate)
        request.set(key: .volumeName, value: name)
        request.set(key: .volumeDriver, value: driver)
        try request.setJSON(driverOpts, key: .volumeDriverOpts)
        try request.setJSON(labels, key: .volumeLabels)
        let reply = try await send(request)
        return try reply.decodeJSON(VolumeConfiguration.self, key: .volume)
    }

    /// Delete a volume.
    public func volumeDelete(name: String) async throws {
        let request = XPCMessage(route: .volumeDelete)
        request.set(key: .volumeName, value: name)
        try await send(request)
    }

    /// List all volumes.
    public func volumeList() async throws -> [VolumeConfiguration] {
        let request = XPCMessage(route: .volumeList)
        let reply = try await send(request)
        return try reply.decodeJSON([VolumeConfiguration].self, key: .volumes)
    }

    /// Inspect a single volume.
    public func volumeInspect(_ name: String) async throws -> VolumeConfiguration {
        let request = XPCMessage(route: .volumeInspect)
        request.set(key: .volumeName, value: name)
        let reply = try await send(request)
        return try reply.decodeJSON(VolumeConfiguration.self, key: .volume)
    }

    /// Get the disk usage of a volume.
    public func volumeDiskUsage(name: String) async throws -> UInt64 {
        let request = XPCMessage(route: .volumeDiskUsage)
        request.set(key: .volumeName, value: name)
        let reply = try await send(request)
        return reply.uint64(key: .volumeSize)
    }
}

// MARK: - System

extension ContainerAPIClient {
    /// Ping the API server and return its health snapshot.
    public func ping(timeout: Duration? = nil) async throws -> SystemHealth {
        let request = XPCMessage(route: .ping)
        let reply = try await send(request, timeout: timeout)
        guard let appRoot = reply.string(key: .appRoot),
              let installRoot = reply.string(key: .installRoot),
              let apiServerVersion = reply.string(key: .apiServerVersion),
              let apiServerCommit = reply.string(key: .apiServerCommit),
              let apiServerBuild = reply.string(key: .apiServerBuild),
              let apiServerAppName = reply.string(key: .apiServerAppName) else {
            throw BackendError.invalidResponse("incomplete health check response")
        }
        return SystemHealth(
            appRoot: appRoot,
            installRoot: installRoot,
            logRoot: reply.string(key: .logRoot),
            apiServerVersion: apiServerVersion,
            apiServerCommit: apiServerCommit,
            apiServerBuild: apiServerBuild,
            apiServerAppName: apiServerAppName
        )
    }

    /// Get system disk usage.
    public func systemDiskUsage() async throws -> SystemDiskUsage {
        let request = XPCMessage(route: .systemDiskUsage)
        let reply = try await send(request)
        guard let data = reply.data(key: .diskUsageStats) else {
            return SystemDiskUsage()
        }
        return (try? JSONDecoder().decode(SystemDiskUsage.self, from: data)) ?? SystemDiskUsage()
    }
}

/// Aggregate disk usage across the system.
public struct SystemDiskUsage: Sendable, Codable {
    public var totalSize: UInt64?
    public var reclaimableSize: UInt64?
    /// Size of images (including the buildkit build cache).
    public var imagesSize: UInt64?
    /// Size of containers (writable layers + referenced image layers).
    public var containersSize: UInt64?
    /// Size of local volumes.
    public var volumesSize: UInt64?

    public init(
        totalSize: UInt64? = nil,
        reclaimableSize: UInt64? = nil,
        imagesSize: UInt64? = nil,
        containersSize: UInt64? = nil,
        volumesSize: UInt64? = nil
    ) {
        self.totalSize = totalSize
        self.reclaimableSize = reclaimableSize
        self.imagesSize = imagesSize
        self.containersSize = containersSize
        self.volumesSize = volumesSize
    }
}
