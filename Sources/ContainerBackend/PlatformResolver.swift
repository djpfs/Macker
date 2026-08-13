//===----------------------------------------------------------------------===//
// PlatformResolver — locates the apple/container runtime installation.
//
// Resolution order (first match wins):
//   1. Explicit setting (user override, e.g. from Settings)
//   2. Managed install (the app's own bundled/vendored copy)
//   3. /usr/local/bin/container (the standard Homebrew/installer location)
//   4. PATH lookup
//===----------------------------------------------------------------------===//

import Foundation

/// The resolved location of the container runtime.
public struct ContainerInstallation: Sendable, Equatable {
    /// Path to the `container` CLI binary.
    public let containerPath: String
    /// Where the runtime was found.
    public let source: InstallSource

    public enum InstallSource: String, Sendable, Equatable {
        case userSetting
        case managed
        case standard
        case path
    }
}

/// Resolves the `container` binary across the four install tiers.
public struct PlatformResolver: Sendable {
    /// Standard install location for the container CLI.
    public static let standardContainerPath = "/usr/local/bin/container"

    private let userSetting: String?
    private let managedPath: String?

    public init(
        userSetting: String? = nil,
        managedPath: String? = nil
    ) {
        self.userSetting = userSetting
        self.managedPath = managedPath
    }

    /// Resolve the container binary, or throw if none is installed.
    public func resolve() throws -> ContainerInstallation {
        let fileManager = FileManager.default
        if let userSetting, fileManager.isExecutableFile(atPath: userSetting) {
            return ContainerInstallation(containerPath: userSetting, source: .userSetting)
        }
        if let managedPath, fileManager.isExecutableFile(atPath: managedPath) {
            return ContainerInstallation(containerPath: managedPath, source: .managed)
        }
        if fileManager.isExecutableFile(atPath: Self.standardContainerPath) {
            return ContainerInstallation(containerPath: Self.standardContainerPath, source: .standard)
        }
        if let fromPath = Self.lookupInPath() {
            return ContainerInstallation(containerPath: fromPath, source: .path)
        }
        throw BackendError.runtimeUnavailable(
            "apple/container runtime not found. Install it with `brew install apple/container/container` or point the app at the binary in Settings."
        )
    }

    /// Whether the runtime is installed at all.
    public func isInstalled() -> Bool {
        (try? resolve()) != nil
    }

    private static func lookupInPath() -> String? {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        let fileManager = FileManager.default
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("container").path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
