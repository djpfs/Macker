//===----------------------------------------------------------------------===//
// Kernel + SystemPlatform — reimplementations of the Containerization types.
// JSON-compatible with the originals so container creation works.
//===----------------------------------------------------------------------===//

import Foundation

/// Describes an operating system and architecture pair. Used to choose what
/// kind of OCI image to pull and which kernel to boot.
public struct SystemPlatform: Sendable, Codable, Equatable {
    public enum OS: String, CaseIterable, Sendable, Codable {
        case linux
        case darwin
    }
    public let os: OS

    public enum Architecture: String, CaseIterable, Sendable, Codable {
        case arm64
        case amd64
    }
    public let architecture: Architecture

    public var ociPlatform: Platform {
        Platform(arch: architecture.rawValue, os: os.rawValue)
    }

    public static let linuxArm = SystemPlatform(os: .linux, architecture: .arm64)
    public static let linuxAmd = SystemPlatform(os: .linux, architecture: .amd64)

    public init(os: OS, architecture: Architecture) {
        self.os = os
        self.architecture = architecture
    }
}

/// An object representing a Linux kernel used to boot a virtual machine.
/// In addition to a path to the kernel itself, this type stores the kernel
/// commandline and init arguments.
public struct Kernel: Sendable, Codable, Equatable {
    /// The command line arguments passed to the kernel on boot.
    public struct CommandLine: Sendable, Codable, Equatable {
        public static let kernelDefaults = [
            "console=hvc0",
            "tsc=reliable",
        ]

        /// Additional kernel arguments.
        public var kernelArgs: [String]
        /// Additional arguments passed to the Initial Process / Agent.
        public var initArgs: [String]

        public init(
            kernelArgs: [String] = kernelDefaults,
            initArgs: [String] = []
        ) {
            self.kernelArgs = kernelArgs
            self.initArgs = initArgs
        }
    }

    /// Path on disk to the kernel binary.
    public var path: URL
    /// Platform for the kernel.
    public var platform: SystemPlatform
    /// Kernel and init process command line.
    public var commandLine: CommandLine

    /// Kernel command line arguments.
    public var kernelArgs: [String] { commandLine.kernelArgs }
    /// Init process arguments.
    public var initArgs: [String] { commandLine.initArgs }

    public init(path: URL, platform: SystemPlatform, commandLine: CommandLine = .init()) {
        self.path = path
        self.platform = platform
        self.commandLine = commandLine
    }
}
