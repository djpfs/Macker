//===----------------------------------------------------------------------===//
// ProcessConfiguration — the initial or main process of a container, and the
// config for additional processes created with createProcess.
//===----------------------------------------------------------------------===//

import Foundation

/// Configuration data for an executable Process.
public struct ProcessConfiguration: Sendable, Codable {
    /// The on disk path to the executable binary.
    public var executable: String
    /// Arguments passed to the Process.
    public var arguments: [String]
    /// Environment variables for the Process ("KEY=VALUE" strings).
    public var environment: [String]
    /// The current working directory (cwd) for the Process.
    public var workingDirectory: String
    /// Whether a TTY/PTY should be attached to the Process's stdio.
    public var terminal: Bool
    /// The User a Process should execute under.
    public var user: User
    /// Supplemental groups for the Process.
    public var supplementalGroups: [UInt32]
    /// Rlimits for the Process.
    public var rlimits: [Rlimit]

    /// Rlimits for Processes.
    public struct Rlimit: Sendable, Codable {
        public let limit: String
        public let soft: UInt64
        public let hard: UInt64

        public init(limit: String, soft: UInt64, hard: UInt64) {
            self.limit = limit
            self.soft = soft
            self.hard = hard
        }
    }

    /// The User information for a Process.
    public enum User: Sendable, Codable, CustomStringConvertible, Equatable {
        /// Look up the raw user string (e.g. "user:group") within the container
        /// before setting it for the Process.
        case raw(userString: String)
        /// Set the provided uid/gid for the Process.
        case id(uid: UInt32, gid: UInt32)

        public var description: String {
            switch self {
            case .id(let uid, let gid):
                return "\(uid):\(gid)"
            case .raw(let name):
                return name
            }
        }
    }

    public init(
        executable: String,
        arguments: [String],
        environment: [String],
        workingDirectory: String = "/",
        terminal: Bool = false,
        user: User = .id(uid: 0, gid: 0),
        supplementalGroups: [UInt32] = [],
        rlimits: [Rlimit] = []
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.terminal = terminal
        self.user = user
        self.supplementalGroups = supplementalGroups
        self.rlimits = rlimits
    }
}
