//===----------------------------------------------------------------------===//
// GuestAgent — injects and starts the hot-reload agent inside a container.
//
// The agent is a static aarch64 Linux binary (see Resources/guest-agent and
// Scripts/build-guest-agent.sh). This manager copies it into the container and
// starts it as a background process listening on a TCP port, so the host can
// stream touch commands to it via `dialContainer`.
//===----------------------------------------------------------------------===//

import Foundation
import ContainerBackend

/// Errors surfaced by the guest agent lifecycle.
public enum HotReloadError: Error, LocalizedError {
    case agentBinaryMissing(String)
    case agentRejected(paths: [String])

    public var errorDescription: String? {
        switch self {
        case .agentBinaryMissing(let path):
            return "Guest agent binary not found at \(path). Run Scripts/build-guest-agent.sh."
        case .agentRejected(let paths):
            return "Guest agent did not acknowledge touch for \(paths.count) path(s)."
        }
    }
}

/// Manages the guest agent lifecycle for a container.
public struct GuestAgent: Sendable {
    private let service: ContainerService
    /// Path to the pre-built agent binary on the host.
    public let binaryPath: String
    /// Where the agent is placed inside the container.
    public let guestPath: String
    /// The TCP port the agent listens on inside the container.
    public let port: UInt32

    public init(
        service: ContainerService = ContainerService(),
        binaryPath: String = defaultBinaryPath,
        guestPath: String = "/usr/local/bin/macker-guest-agent",
        port: UInt32 = 9000
    ) {
        self.service = service
        self.binaryPath = binaryPath
        self.guestPath = guestPath
        self.port = port
    }

    /// The default location of the pre-built agent binary.
    public static var defaultBinaryPath: String {
        // Prefer a bundled copy next to the executable, then the repo's
        // Resources directory (relative to the current working directory),
        // then a standard install location.
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("guest-agent").path
        if let bundled, FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
        let cwd = FileManager.default.currentDirectoryPath
        let repo = (cwd as NSString)
            .appendingPathComponent("Resources/guest-agent/guest-agent")
        if FileManager.default.fileExists(atPath: repo) {
            return repo
        }
        return "/usr/local/share/macker/guest-agent"
    }

    /// Copy the agent into the container and start it listening.
    public func install(in containerID: String) async throws {
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw HotReloadError.agentBinaryMissing(binaryPath)
        }
        try await service.copyIn(
            id: containerID,
            source: binaryPath,
            destination: guestPath,
            mode: 0o755,
            createParents: true
        )
        let processID = "macker-guest-agent"
        let config = ProcessConfiguration(
            executable: guestPath,
            arguments: ["\(port)"],
            environment: [],
            workingDirectory: "/",
            terminal: false,
            user: .id(uid: 0, gid: 0),
            supplementalGroups: [],
            rlimits: []
        )
        try await service.createProcess(containerId: containerID, processId: processID, configuration: config)
        try await service.startProcess(containerId: containerID, processId: processID)
    }
}
