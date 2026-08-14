//===----------------------------------------------------------------------===//
// ProcessRunner — CLI fallback wrapper.
//
// XPC is the primary transport, but a few operations have no XPC equivalent
// (daemon lifecycle, image management, builder). Those shell out to the
// `container` CLI. This type is deliberately small: it captures stdout/stderr,
// returns the exit status, and never blocks the caller's actor.
//===----------------------------------------------------------------------===//

import Foundation

/// Result of a completed CLI invocation.
public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == 0 }
}

/// Runs `container` CLI subcommands as a fallback for operations without an
/// XPC route.
public struct ProcessRunner: Sendable {
    /// Path to the `container` binary.
    public let containerPath: String

    public init(containerPath: String = "/usr/local/bin/container") {
        self.containerPath = containerPath
    }

    /// Run a `container` subcommand with the given arguments.
    ///
    /// - Parameters:
    ///   - args: arguments after the `container` binary, e.g. `["image", "pull", "nginx"]`.
    ///   - environment: extra environment variables to set.
    ///   - timeout: maximum wall-clock time before the process is killed.
    public func run(
        _ args: [String],
        environment: [String: String] = [:],
        standardInput: Data? = nil,
        timeout: Duration = .seconds(300)
    ) async throws -> ProcessResult {
        try await runExecutable(containerPath, args: args, environment: environment, standardInput: standardInput, timeout: timeout)
    }

    /// Run an arbitrary executable (used for `container` discovery and tests).
    public func runExecutable(
        _ path: String,
        args: [String],
        environment: [String: String] = [:],
        standardInput: Data? = nil,
        timeout: Duration = .seconds(300)
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe: Pipe?
        if standardInput != nil {
            let pipe = Pipe()
            stdinPipe = pipe
            process.standardInput = pipe
        } else {
            stdinPipe = nil
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Read pipes on a background thread to avoid deadlock when the child
        // fills a pipe buffer while we wait for exit.
        let stdout = AsyncStream<String> { continuation in
            Task.detached {
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.yield(String(decoding: data, as: UTF8.self))
                continuation.finish()
            }
        }
        let stderr = AsyncStream<String> { continuation in
            Task.detached {
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.yield(String(decoding: data, as: UTF8.self))
                continuation.finish()
            }
        }

        try process.run()
        if let standardInput, let stdinPipe {
            stdinPipe.fileHandleForWriting.write(standardInput)
            stdinPipe.fileHandleForWriting.closeFile()
        }

        let deadline = ContinuousClock.now + timeout
        while process.isRunning {
            if ContinuousClock.now >= deadline {
                process.terminate()
                throw BackendError.timeout(route: args.joined(separator: " "))
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        var stdoutText = ""
        var stderrText = ""
        for await chunk in stdout { stdoutText += chunk }
        for await chunk in stderr { stderrText += chunk }

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdoutText,
            stderr: stderrText
        )
    }
}
