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
    /// daemon is a no-op. `environment` is passed to `container system start`,
    /// which records it for the daemon (for example CONTAINER_APP_ROOT).
    public func start(environment: [String: String] = [:]) async throws {
        let result = try await runner.run(["system", "start"], environment: environment)
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

    /// Query the current daemon state from `container system status --format json`.
    /// The CLI exits non-zero when the services are down but still prints the
    /// JSON payload, so the exit code is ignored and only the payload is read.
    public func status() async -> DaemonState {
        do {
            let result = try await runner.run(["system", "status", "--format", "json"], timeout: .seconds(10))
            return Self.parseStatus(result.stdout, fallback: result.stderr)
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    /// Maps the `status` field of the CLI JSON payload to a `DaemonState`.
    /// `fallback` (stderr) is used as the reason when the payload is unreadable.
    static func parseStatus(_ stdout: String, fallback: String) -> DaemonState {
        guard let report = try? JSONDecoder().decode(StatusReport.self, from: Data(stdout.utf8)) else {
            let reason = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            return .unknown(reason.isEmpty ? "unreadable system status output" : reason)
        }
        switch report.status {
        case "running":
            return .running
        case "not running", "unregistered":
            return .stopped
        default:
            return .unknown(report.status)
        }
    }

    private struct StatusReport: Decodable {
        let status: String
    }
}
