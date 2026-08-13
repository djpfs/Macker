//===----------------------------------------------------------------------===//
// Transports — how touch commands reach the guest.
//
// ExecTouchTransport runs `touch` through the container process API. It needs
// no guest-side tooling and is the default. SocketTouchTransport streams paths
// to the guest agent over a dialed connection, which is cheaper per batch once
// the agent is injected.
//===----------------------------------------------------------------------===//

import Foundation
import ContainerBackend

/// Runs `touch` inside the container via the process API. Works everywhere,
/// at the cost of one process spawn per batch.
public struct ExecTouchTransport: TouchTransport {
    private let service: ContainerService

    public init(service: ContainerService = ContainerService()) {
        self.service = service
    }

    public func touch(paths: [String], in containerID: String) async throws {
        guard !paths.isEmpty else { return }
        // Quote each path for the shell. Paths come from FSEvents so they are
        // already absolute and may contain spaces.
        let quoted = paths.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "touch " + quoted.joined(separator: " ")
        let processID = "macker-touch-\(UUID().uuidString.prefix(8))"
        let config = ProcessConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", command],
            environment: [],
            workingDirectory: "/",
            terminal: false,
            user: .id(uid: 0, gid: 0),
            supplementalGroups: [],
            rlimits: []
        )
        try await service.createProcess(containerId: containerID, processId: processID, configuration: config)
        try await service.startProcess(containerId: containerID, processId: processID)
        _ = try await service.waitForProcess(containerId: containerID, processId: processID)
    }
}

/// Streams container-relative paths to the guest agent over a dialed TCP
/// connection. The agent (a tiny Linux binary) touches each path and replies
/// `ok`. Cheaper than spawning a process per batch.
public struct SocketTouchTransport: TouchTransport {
    private let service: ContainerService
    /// The TCP port the guest agent listens on inside the container.
    public let port: UInt32

    public init(service: ContainerService = ContainerService(), port: UInt32 = 9000) {
        self.service = service
        self.port = port
    }

    public func touch(paths: [String], in containerID: String) async throws {
        guard !paths.isEmpty else { return }
        let handle = try await service.dialContainer(id: containerID, port: port)
        defer { try? handle.close() }

        // One path per line, NUL-terminated batch.
        let payload = paths.joined(separator: "\n") + "\n"
        try handle.write(contentsOf: Data(payload.utf8))

        // Read the agent's acknowledgement (a single line).
        var ack = Data()
        while ack.count < 2 {
            guard let byte = try handle.read(upToCount: 1) else { break }
            ack.append(byte)
        }
        guard String(data: ack, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" else {
            throw HotReloadError.agentRejected(paths: paths)
        }
    }
}
