//===----------------------------------------------------------------------===//
// LaunchdManager — daemon lifecycle for container-apiserver.
//
// The container services (apiserver, core-images, etc.) are managed by launchd
// via the `container system` CLI. This type wraps start/stop/status so the GUI
// and CLI can bring the runtime up and down without shelling out ad hoc.
//===----------------------------------------------------------------------===//

import Foundation

/// The runtime state of the container services.
public enum DaemonState: Sendable, Equatable {
    case running
    case stopped
    case unknown(String)
}

/// Manages the lifecycle of the container-apiserver daemon.
public struct LaunchdManager: Sendable {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Start the container services. Idempotent: starting an already-running
    /// daemon is a no-op.
    public func start() async throws {
        let result = try await runner.run(["system", "start"])
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "failed to start container services: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }

    /// Stop the container services.
    public func stop() async throws {
        let result = try await runner.run(["system", "stop"])
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "failed to stop container services: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }

    /// Query the current daemon state.
    public func status() async -> DaemonState {
        do {
            let result = try await runner.run(["system", "status"], timeout: .seconds(10))
            let output = result.stdout + result.stderr
            if result.succeeded {
                return .running
            }
            let lower = output.lowercased()
            if lower.contains("not running") || lower.contains("stopped") || lower.contains("inactive") {
                return .stopped
            }
            return .unknown(output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .unknown(error.localizedDescription)
        }
    }
}
