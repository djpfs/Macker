//===----------------------------------------------------------------------===//
// DockerCommand — parses docker-style command lines.
//
// The shim receives the raw arguments that would have gone to `docker` and
// parses them into a structured command. Docker's CLI grammar is loose (flags
// can appear before or after the subcommand, `--flag=value` and `--flag value`
// both work), so this parser is deliberately tolerant. Each subcommand carries
// a flag spec so boolean flags (like `--rm`) are not mistaken for value-taking
// flags (like `--name`).
//===----------------------------------------------------------------------===//

import Foundation

/// A parsed docker command.
public struct DockerCommand: Sendable, Equatable {
    /// The subcommand, e.g. `ps`, `run`, `images`, `compose`.
    public let subcommand: String
    /// The sub-subcommand for grouped commands, e.g. `compose up` → `up`.
    public let subSubcommand: String?
    /// Positional arguments (image refs, container names, etc.).
    public let arguments: [String]
    /// Parsed flags keyed by long/short name (without dashes).
    public let flags: [String: String]
    /// Flags that were present without a value (booleans).
    public let booleanFlags: Set<String>

    public init(
        subcommand: String,
        subSubcommand: String? = nil,
        arguments: [String] = [],
        flags: [String: String] = [:],
        booleanFlags: Set<String> = []
    ) {
        self.subcommand = subcommand
        self.subSubcommand = subSubcommand
        self.arguments = arguments
        self.flags = flags
        self.booleanFlags = booleanFlags
    }

    /// Whether a boolean flag was present.
    public func has(_ flag: String) -> Bool {
        booleanFlags.contains(flag)
    }

    /// Whether a boolean flag was present, checking both its short and long
    /// forms (e.g. `-d` and `--detach`).
    public func has(short: String, long: String) -> Bool {
        booleanFlags.contains(short) || booleanFlags.contains(long)
    }

    /// The value of a flag, or `nil` if absent.
    public func value(_ flag: String) -> String? {
        flags[flag]
    }

    /// The value of a flag, checking both its short and long forms (e.g. `-v`
    /// and `--volume`). The parser stores flags keyed by their literal name
    /// without dashes, so `-v` lands under `"v"` and `--volume` under
    /// `"volume"` — callers must check both.
    public func value(short: String, long: String) -> String? {
        flags[short] ?? flags[long]
    }

    /// The value of a flag, or a default if absent.
    public func value(_ flag: String, default defaultValue: String) -> String {
        flags[flag] ?? defaultValue
    }
}

/// Parses docker-style arguments into a ``DockerCommand``.
public enum DockerCommandParser {
    /// The set of docker subcommands that have a nested subcommand.
    private static let groupedCommands: Set<String> = [
        "compose", "network", "volume", "image", "container", "system", "context", "plugin", "secret", "config", "service", "stack", "swarm", "node", "buildx",
    ]

    /// Flags that take a value, per subcommand.
    private static let valueFlagSpecs: [String: Set<String>] = [
        "run": ["p", "publish", "v", "volume", "e", "env", "name", "network", "restart", "cpus", "memory", "signal", "workdir", "w", "user", "u", "entrypoint", "hostname", "h", "platform", "label", "l", "add-host", "cap-add", "cap-drop", "device", "dns", "dns-search", "dns-option", "ip", "ip6", "mac-address", "memory-swap", "memory-reservation", "pid", "security-opt", "shm-size", "stop-signal", "stop-timeout", "sysctl", "tmpfs", "ulimit", "userns", "uts", "cgroup-parent", "cpuset-cpus", "cpuset-mems", "health-cmd", "health-interval", "health-retries", "health-start-period", "health-timeout", "pids-limit", "pull", "env-file", "mount", "volume-driver", "volumes-from", "ipc", "log-driver", "log-opt", "runtime", "storage-opt", "attach", "detach-keys", "expose", "init-path", "kernel-memory", "oom-score-adj", "cpu-shares", "cpu-period", "cpu-quota", "cpu-rt-period", "cpu-rt-runtime", "device-cgroup-rule", "blkio-weight", "blkio-weight-device", "device-read-bps", "device-read-iops", "device-write-bps", "device-write-iops", "group-add", "cgroupns", "network-alias", "stop-signal", "stop-timeout", "volume-driver", "volumes-from", "workdir", "user", "label", "network-alias", "ipc", "log-driver", "log-opt", "runtime", "storage-opt", "attach", "detach-keys", "expose", "health-cmd", "health-interval", "health-retries", "health-start-period", "health-timeout", "init-path", "kernel-memory", "oom-score-adj", "pids-limit", "pull", "stop-signal", "stop-timeout", "volume-driver", "volumes-from", "workdir", "user", "label", "network-alias", "ipc", "log-driver", "log-opt", "runtime", "storage-opt", "attach", "detach-keys", "expose"],
        "ps": ["filter", "f", "format", "since", "before", "label", "l"],
        "logs": ["tail", "since", "until", "format"],
        "exec": ["user", "u", "workdir", "w", "env", "e", "detach-keys"],
        "stop": ["time", "t", "signal", "s"],
        "rm": ["filter", "label", "l"],
        "kill": ["signal", "s"],
        "images": ["filter", "f", "format", "since", "before", "label", "l"],
        "pull": ["platform", "arch", "a", "os", "scheme", "progress", "max-concurrent-downloads"],
        "network": ["driver", "d", "subnet", "gateway", "ip-range", "label", "l", "opt", "o", "config-from", "driver-opt", "scope"],
        "volume": ["driver", "d", "label", "l", "opt", "o", "name", "n", "type", "device", "volume-driver", "volume-opt"],
        "system": ["filter", "f", "format"],
        "inspect": ["format", "f", "size", "s", "type", "t"],
        "scan": ["severity", "format"],
        "secret": ["label", "l", "driver", "template-driver"],
        "start": ["attach", "a", "detach-keys"],
        "restart": ["time", "t"],
        "version": ["format", "f"],
        "info": ["format", "f"],
    ]

    /// Flags that take no value, per subcommand.
    private static let booleanFlagSpecs: [String: Set<String>] = [
        "run": ["d", "detach", "i", "interactive", "t", "tty", "rm", "privileged", "read-only", "init", "oom-kill-disable", "sig-proxy", "publish-all", "P", "no-healthcheck", "help", "h"],
        "ps": ["a", "all", "q", "quiet", "no-trunc", "n", "help", "h"],
        "logs": ["f", "follow", "t", "timestamps", "help", "h"],
        "exec": ["i", "interactive", "t", "tty", "d", "detach", "help", "h"],
        "stop": ["help", "h"],
        "rm": ["f", "force", "v", "volumes", "help", "h"],
        "kill": ["help", "h"],
        "images": ["a", "all", "q", "quiet", "no-trunc", "help", "h"],
        "pull": ["help", "h", "quiet", "q"],
        "network": ["help", "h", "internal", "ipv6", "attachable", "ingress", "encrypted"],
        "volume": ["help", "h"],
        "system": ["help", "h", "a", "all", "v", "volumes", "i", "images", "c", "containers", "b", "build-cache", "builder"],
        "inspect": ["help", "h"],
        "scan": ["help", "h"],
        "secret": ["help", "h"],
        "start": ["help", "h"],
        "restart": ["help", "h"],
        "version": ["help", "h"],
        "info": ["help", "h"],
    ]

    /// Parse the arguments that follow `docker`.
    public static func parse(_ args: [String]) throws -> DockerCommand {
        var tokens = args
        var subcommand: String?
        var subSubcommand: String?
        var positionals: [String] = []
        var flags: [String: String] = [:]
        var booleanFlags: Set<String> = []

        // Docker allows global flags before the subcommand (e.g. `docker -H tcp://... ps`).
        // We skip known global flags and treat the first non-flag token as the subcommand.
        while let token = tokens.first {
            if token.hasPrefix("-") {
                let (name, inlineValue) = splitFlag(token)
                tokens.removeFirst()
                if inlineValue == nil && !isBooleanGlobalFlag(name) {
                    if !tokens.isEmpty {
                        tokens.removeFirst()
                    }
                }
            } else {
                subcommand = token
                tokens.removeFirst()
                break
            }
        }

        guard let subcommand else {
            throw DockerShimError.missingSubcommand
        }

        // For grouped commands, the next non-flag token is the sub-subcommand.
        // Flags before it (e.g. `compose -f file.yml up`) are preserved.
        if groupedCommands.contains(subcommand) {
            while let token = tokens.first, token.hasPrefix("-") {
                let (name, inlineValue) = splitFlag(token)
                tokens.removeFirst()
                if let inlineValue {
                    flags[name] = inlineValue
                } else if !isBooleanGlobalFlag(name) {
                    if let next = tokens.first {
                        flags[name] = next
                        tokens.removeFirst()
                    } else {
                        booleanFlags.insert(name)
                    }
                } else {
                    booleanFlags.insert(name)
                }
            }
            if let token = tokens.first, !token.hasPrefix("-") {
                subSubcommand = token
                tokens.removeFirst()
            }
        }

        let valueSet = valueFlagSpecs[subcommand] ?? []
        let boolSet = booleanFlagSpecs[subcommand] ?? []

        // Commands whose trailing arguments are a command line, not docker
        // flags: `docker run IMAGE [CMD...]` and `docker exec CONTAINER [CMD...]`.
        // Once the first positional (image/container) is seen, everything after
        // is passed through verbatim — `sh -c '...'` must not be parsed as flags.
        let passthroughAfterFirstPositional = subcommand == "run" || subcommand == "exec"

        // Remaining tokens: flags and positionals, in any order.
        while !tokens.isEmpty {
            let token = tokens.removeFirst()
            if passthroughAfterFirstPositional && !positionals.isEmpty {
                positionals.append(token)
                positionals.append(contentsOf: tokens)
                break
            }
            if token == "--" {
                // Everything after `--` is positional.
                positionals.append(contentsOf: tokens)
                break
            }
            if token.hasPrefix("-") {
                let (name, inlineValue) = splitFlag(token)
                if let inlineValue {
                    flags[name] = inlineValue
                } else if valueSet.contains(name) {
                    // Value-taking flag: consume the next token as its value.
                    if let next = tokens.first {
                        flags[name] = next
                        tokens.removeFirst()
                    } else {
                        booleanFlags.insert(name)
                    }
                } else if boolSet.contains(name) {
                    booleanFlags.insert(name)
                } else {
                    // Unknown flag: default to value-taking (docker convention).
                    if let next = tokens.first, !next.hasPrefix("-") {
                        flags[name] = next
                        tokens.removeFirst()
                    } else {
                        booleanFlags.insert(name)
                    }
                }
            } else {
                positionals.append(token)
            }
        }

        return DockerCommand(
            subcommand: subcommand,
            subSubcommand: subSubcommand,
            arguments: positionals,
            flags: flags,
            booleanFlags: booleanFlags
        )
    }

    /// Split a flag token into (name, inlineValue). Handles `--flag=value`,
    /// `--flag`, `-f`, `-f=value`.
    private static func splitFlag(_ token: String) -> (String, String?) {
        let stripped = token.hasPrefix("--") ? String(token.dropFirst(2)) : String(token.dropFirst())
        if let eq = stripped.firstIndex(of: "=") {
            return (String(stripped[..<eq]), String(stripped[stripped.index(after: eq)...]))
        }
        return (stripped, nil)
    }

    /// Global flags that take no value.
    private static func isBooleanGlobalFlag(_ name: String) -> Bool {
        ["debug", "version", "help", "h", "quiet", "q"].contains(name)
    }
}

/// Errors produced while parsing docker commands.
public enum DockerShimError: Error, LocalizedError {
    case missingSubcommand
    case unsupportedCommand(String)
    case unsupportedFlag(String, String)
    case missingArgument(String)

    public var errorDescription: String? {
        switch self {
        case .missingSubcommand:
            return "docker: no command specified"
        case .unsupportedCommand(let command):
            return "docker: '\(command)' is not supported by macker"
        case .unsupportedFlag(let command, let flag):
            return "docker: flag '\(flag)' is not supported for '\(command)'"
        case .missingArgument(let what):
            return "docker: missing required argument: \(what)"
        }
    }
}
