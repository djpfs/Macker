//===----------------------------------------------------------------------===//
// AppleDockerCLI — root command for the headless CLI mode.
//
// This target is linked into the single macker binary. Main.swift
// inspects the arguments: with arguments it routes into `AppleDockerCLICommand`
// (ArgumentParser), without arguments it launches the SwiftUI app.
// Subcommands:
//   macker version                → client + daemon versions
//   macker selftest               → XPC connectivity + model round-trip check
//   macker system status          → daemon health snapshot
//   macker docker …               → Docker CLI shim (see DockerShim/)
//   macker compose …              → Compose engine front end
//   macker run …                  → docker run translation
//   macker exec …                 → docker exec translation
//===----------------------------------------------------------------------===//

import ArgumentParser
import Foundation
import ContainerBackend

public struct AppleDockerCLICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "macker",
        abstract: "Docker-compatible interface over Apple's native container runtime.",
        version: Self.clientVersion,
        subcommands: [
            VersionCommand.self,
            SelftestCommand.self,
            SystemCommand.self,
            DockerShimCommand.self,
        ]
    )

    /// Version of the macker client. The container protocol version is
    /// pinned in Package.swift (`containerVersion`) and must be bumped in
    /// lockstep with the apple/container runtime.
    public static let clientVersion = "macker 0.1.0 (container protocol 1.2.2)"

    public init() {}

    public func run() async throws {
        // No arguments → GUI mode is handled in Main.swift, so this is a
        // defensive no-op. With arguments, ArgumentParser dispatches.
        throw CleanExit.message(Self.helpMessage())
    }
}

/// Prints client and daemon version information.
struct VersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print macker and container runtime version information."
    )

    func run() async throws {
        print(AppleDockerCLICommand.clientVersion)
        do {
            let client = ContainerAPIClient()
            let health = try await client.ping()
            print("container-apiserver \(health.apiServerVersion) (\(health.apiServerCommit))")
            if let logRoot = health.logRoot {
                print("log root: \(logRoot)")
            }
        } catch {
            print("container-apiserver: unreachable (\(error.localizedDescription))")
        }
    }
}

/// Validates the XPC connection end-to-end and reports daemon health.
struct SelftestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "selftest",
        abstract: "Validate XPC connectivity to container-apiserver."
    )

    @Flag(name: .shortAndLong, help: "Fail with a non-zero exit code on any check failure.")
    var strict = false

    func run() async throws {
        var failures = 0

        func check(_ name: String, _ body: () async throws -> Void) async {
            do {
                try await body()
                print("[OK] \(name)")
            } catch {
                failures += 1
                print("[FAIL] \(name): \(error.localizedDescription)")
            }
        }

        let client = ContainerAPIClient()
        await check("XPC connection + ping") {
            let health = try await client.ping(timeout: .seconds(5))
            print("    → \(health.apiServerAppName) v\(health.apiServerVersion) build \(health.apiServerBuild)")
            print("    → appRoot \(health.appRoot)")
            print("    → installRoot \(health.installRoot)")
        }
        await check("default kernel (linux/arm64)") {
            let kernel = try await client.getDefaultKernel(for: .linuxArm)
            print("    → \(kernel.path.path)")
        }
        await check("network list") {
            let networks = try await client.networkList()
            print("    → \(networks.count) network(s)")
        }
        await check("container list") {
            let containers = try await client.list()
            print("    → \(containers.count) container(s)")
        }

        client.close()
        if strict && failures > 0 {
            throw ExitCode.failure
        }
    }
}

/// Daemon lifecycle and health commands.
struct SystemCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "system",
        abstract: "Manage the container-apiserver daemon.",
        subcommands: [StatusCommand.self, PruneCommand.self]
    )
}

/// Removes unused images and the buildkit builder cache.
struct PruneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Remove unused images and the buildkit builder cache."
    )

    @Flag(name: .shortAndLong, help: "Remove ALL images, not just unused (dangling) ones.")
    var all = false

    @Flag(name: .long, help: "Also delete the buildkit builder container (frees the build cache).")
    var builder = false

    func run() async throws {
        let service = ContainerService()
        if builder {
            print("==> Deleting buildkit builder...")
            try await service.deleteBuildkitBuilder()
            print("[OK] buildkit builder deleted")
        }
        print("==> Pruning images...")
        try await service.images.prune(all: all)
        print("[OK] images pruned")
        service.close()
    }
}

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Print daemon health."
    )

    func run() async throws {
        let client = ContainerAPIClient()
        do {
            let health = try await client.ping(timeout: .seconds(5))
            print("status: running")
            print("app: \(health.apiServerAppName)")
            print("version: \(health.apiServerVersion) (\(health.apiServerCommit))")
            print("build: \(health.apiServerBuild)")
            print("app root: \(health.appRoot)")
            print("install root: \(health.installRoot)")
            if let logRoot = health.logRoot {
                print("log root: \(logRoot)")
            }
        } catch {
            print("status: stopped (\(error.localizedDescription))")
            if Self.isStrictFailure(error) {
                throw error
            }
        }
        client.close()
    }

    private static func isStrictFailure(_ error: Error) -> Bool {
        // Connection refused / interrupted are "daemon not running", which is a
        // valid status, not a command failure.
        if case BackendError.connectionInterrupted = error { return false }
        if case BackendError.runtimeUnavailable = error { return false }
        return true
    }
}
