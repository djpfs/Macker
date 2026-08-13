//===----------------------------------------------------------------------===//
// Container operation option types: create, list filters, stop.
//===----------------------------------------------------------------------===//

import Foundation

/// Options for creating a container.
public struct ContainerCreateOptions: Codable, Sendable {
    /// Remove the container and wipe out its data on container stop.
    public let autoRemove: Bool
    /// Override the rootFs with this one other than the image-cloned version.
    public let rootFsOverride: Filesystem?

    public init(autoRemove: Bool, rootFsOverride: Filesystem? = nil) {
        self.autoRemove = autoRemove
        self.rootFsOverride = rootFsOverride
    }

    public static let `default` = ContainerCreateOptions(autoRemove: false)
}

/// Filters for listing containers.
public struct ContainerListFilters: Sendable, Codable {
    /// Filter by container IDs. If non-empty, only containers with matching IDs are returned.
    public var ids: [String]
    /// Filter by container status.
    public var status: RuntimeStatus?
    /// Filter by labels. All specified labels must match. Values are treated as
    /// regular expressions matched against the container's label value.
    public var labels: [String: String]

    /// No filters applied. Will return all containers.
    public static let all = ContainerListFilters()

    public init(
        ids: [String] = [],
        status: RuntimeStatus? = nil,
        labels: [String: String] = [:]
    ) {
        self.ids = ids
        self.status = status
        self.labels = labels
    }
}

/// Options for stopping a container.
public struct ContainerStopOptions: Sendable, Codable {
    public var timeoutInSeconds: Int32
    public var signal: String?

    public static let `default` = ContainerStopOptions(timeoutInSeconds: 5, signal: nil)

    public init(timeoutInSeconds: Int32, signal: String?) {
        self.timeoutInSeconds = timeoutInSeconds
        self.signal = signal
    }
}

/// Snapshot of the health of container services and resources (from the ping route).
public struct SystemHealth: Sendable, Codable {
    /// The full pathname of the application data root.
    public let appRoot: String
    /// The full pathname of the application install root.
    public let installRoot: String
    /// The full pathname of the log root.
    public let logRoot: String?
    /// The release version of the container services.
    public let apiServerVersion: String
    /// The Git commit ID for the container services.
    public let apiServerCommit: String
    /// The build type of the API server (debug|release).
    public let apiServerBuild: String
    /// The app name label returned by the server.
    public let apiServerAppName: String

    public init(
        appRoot: String,
        installRoot: String,
        logRoot: String?,
        apiServerVersion: String,
        apiServerCommit: String,
        apiServerBuild: String,
        apiServerAppName: String
    ) {
        self.appRoot = appRoot
        self.installRoot = installRoot
        self.logRoot = logRoot
        self.apiServerVersion = apiServerVersion
        self.apiServerCommit = apiServerCommit
        self.apiServerBuild = apiServerBuild
        self.apiServerAppName = apiServerAppName
    }
}
