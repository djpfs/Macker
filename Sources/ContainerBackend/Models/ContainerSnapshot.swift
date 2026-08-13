//===----------------------------------------------------------------------===//
// ContainerSnapshot, RuntimeStatus, ContainerStatus, ContainerStats.
//===----------------------------------------------------------------------===//

import Foundation

/// Runtime status for a sandbox or container.
public enum RuntimeStatus: String, CaseIterable, Sendable, Codable {
    /// The object is in an unknown status.
    case unknown
    /// The object is currently stopped.
    case stopped
    /// The object is currently running.
    case running
    /// The object is currently stopping.
    case stopping
}

/// A snapshot of a container along with its configuration and runtime state.
public struct ContainerSnapshot: Sendable, Codable, Identifiable {
    /// The configuration of the container.
    public var configuration: ContainerConfiguration
    /// Identifier of the container.
    public var id: String { configuration.id }
    /// Configured platform for the container.
    public var platform: Platform { configuration.platform }
    /// The runtime status of the container.
    public var status: RuntimeStatus
    /// Network interfaces attached to the sandbox that are provided to the container.
    public var networks: [Attachment]
    /// When the container was started.
    public var startedDate: Date?

    public init(
        configuration: ContainerConfiguration,
        status: RuntimeStatus,
        networks: [Attachment],
        startedDate: Date? = nil
    ) {
        self.configuration = configuration
        self.status = status
        self.networks = networks
        self.startedDate = startedDate
    }
}

/// The runtime status of a container, identity-free.
public struct ContainerStatus: Codable, Sendable {
    /// The state-machine value for the container (running, stopped, …).
    public let state: RuntimeStatus
    /// Network attachments provided to the container.
    public let networks: [Attachment]
    /// When the container was started, if it has been.
    public let startedDate: Date?

    public init(state: RuntimeStatus, networks: [Attachment], startedDate: Date? = nil) {
        self.state = state
        self.networks = networks
        self.startedDate = startedDate
    }
}

/// Statistics for a container.
public struct ContainerStats: Sendable, Codable {
    /// Container ID.
    public var id: String
    /// Physical memory usage in bytes.
    public var memoryUsageBytes: UInt64?
    /// Memory limit in bytes.
    public var memoryLimitBytes: UInt64?
    /// CPU usage in microseconds.
    public var cpuUsageUsec: UInt64?
    /// Network received bytes (sum of all interfaces).
    public var networkRxBytes: UInt64?
    /// Network transmitted bytes (sum of all interfaces).
    public var networkTxBytes: UInt64?
    /// Block I/O read bytes (sum of all devices).
    public var blockReadBytes: UInt64?
    /// Block I/O write bytes (sum of all devices).
    public var blockWriteBytes: UInt64?
    /// Number of processes in the container.
    public var numProcesses: UInt64?

    public init(
        id: String,
        memoryUsageBytes: UInt64? = nil,
        memoryLimitBytes: UInt64? = nil,
        cpuUsageUsec: UInt64? = nil,
        networkRxBytes: UInt64? = nil,
        networkTxBytes: UInt64? = nil,
        blockReadBytes: UInt64? = nil,
        blockWriteBytes: UInt64? = nil,
        numProcesses: UInt64? = nil
    ) {
        self.id = id
        self.memoryUsageBytes = memoryUsageBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.cpuUsageUsec = cpuUsageUsec
        self.networkRxBytes = networkRxBytes
        self.networkTxBytes = networkTxBytes
        self.blockReadBytes = blockReadBytes
        self.blockWriteBytes = blockWriteBytes
        self.numProcesses = numProcesses
    }
}
