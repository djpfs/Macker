//===----------------------------------------------------------------------===//
// ContainerTerminalSession — a persistent interactive shell for a container.
//
// Lives in AppState (keyed by container ID) so the terminal survives tab
// switches. The process is created once and kept alive; output is streamed on
// a background task and published back to the main actor.
//===----------------------------------------------------------------------===//

import Foundation
import Observation
import ContainerBackend

@MainActor
@Observable
final class ContainerTerminalSession {
    let containerID: String
    let sessionLabel: String
    /// Stable identity for use in `ForEach` and equality checks.
    let objectID = UUID()
    var output: [String] = []
    var isConnected = false
    private var stdinHandle: FileHandle?
    private var task: Task<Void, Never>?

    init(containerID: String, sessionLabel: String = "Session 1") {
        self.containerID = containerID
        self.sessionLabel = sessionLabel
    }

    /// Create and start the interactive shell, then stream its output.
    func connect() {
        guard !isConnected else { return }
        task?.cancel()
        let processID = "terminal-\(UUID().uuidString.prefix(8))"
        let containerID = self.containerID
        task = Task.detached { [weak self] in
            guard let self else { return }
            do {
                let (stdinRead, stdinWrite) = try Self.makePipe()
                let (stdoutRead, stdoutWrite) = try Self.makePipe()
                await MainActor.run { self.stdinHandle = stdinWrite }

                let config = ProcessConfiguration(
                    executable: "/bin/sh",
                    arguments: [],
                    environment: [],
                    workingDirectory: "/",
                    terminal: true
                )
                let service = ContainerService()
                // With `terminal: true` the runtime merges stderr into stdout
                // itself, so stderr must NOT be configured.
                try await service.createProcess(
                    containerId: containerID,
                    processId: processID,
                    configuration: config,
                    stdio: [stdinRead, stdoutWrite, nil]
                )
                try await service.startProcess(containerId: containerID, processId: processID)

                await MainActor.run {
                    self.isConnected = true
                    self.output.append("Connected to \(containerID). Type a command and press Enter.\n")
                }

                // Stream output continuously on this background task.
                while !Task.isCancelled {
                    let data = stdoutRead.availableData
                    if data.isEmpty { break }
                    if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                        // `clear` emits ESC[2J / ESC[3J (clear screen) — wipe the
                        // buffer instead of just stripping the escape codes.
                        if text.contains("\u{1B}[2J") || text.contains("\u{1B}[3J") {
                            await MainActor.run { self.output.removeAll() }
                        }
                        let clean = Self.stripANSI(text)
                        if !clean.isEmpty {
                            await MainActor.run { self.output.append(clean) }
                        }
                    }
                }
            } catch {
                await MainActor.run { self.output.append("[ERROR] \(error.localizedDescription)") }
            }
        }
    }

    /// Write a command to the shell's stdin and echo it locally.
    func sendCommand(_ command: String) {
        guard let stdinHandle, !command.isEmpty else { return }
        let line = command + "\n"
        if let data = line.data(using: .utf8) {
            try? stdinHandle.write(contentsOf: data)
        }
        output.append("$ \(command)")
    }

    /// Stop the shell and release resources.
    func disconnect() {
        task?.cancel()
        try? stdinHandle?.close()
        stdinHandle = nil
        isConnected = false
    }

    /// Remove ANSI escape sequences (colors, cursor moves, etc.) from a chunk
    /// of terminal output so it renders as plain readable text.
    private nonisolated static func stripANSI(_ text: String) -> String {
        // Matches CSI sequences like ESC[1;32m, ESC[2J, ESC[?25l, etc.
        let pattern = "\u{1B}\\[[0-9;?]*[A-Za-z]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private nonisolated static func makePipe() throws -> (FileHandle, FileHandle) {
        var fds: [Int32] = [0, 0]
        let result = pipe(&fds)
        guard result == 0 else {
            throw BackendError.operationFailed("failed to create pipe")
        }
        let readHandle = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true)
        let writeHandle = FileHandle(fileDescriptor: fds[1], closeOnDealloc: true)
        return (readHandle, writeHandle)
    }
}
