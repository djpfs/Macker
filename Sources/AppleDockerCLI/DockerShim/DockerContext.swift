//===----------------------------------------------------------------------===//
// DockerContext — `docker context` and forwarding to other daemons.
//
// The `default` context is Macker's own runtime (Apple's `container`). Any other
// context stores a Docker endpoint, such as `unix:///path/docker.sock` or
// `ssh://user@host`. Commands run in such a context are passed unchanged to the
// external `docker` CLI with `-H <endpoint>`.
//
// The contexts file lives in ~/Library/Application Support/Macker/contexts.json.
//===----------------------------------------------------------------------===//

import Foundation

/// One named context.
public struct DockerContextRecord: Codable, Equatable, Sendable {
    public var name: String
    /// Docker endpoint, or `nil` for Macker's own runtime.
    public var endpoint: String?
    public var description: String

    public init(name: String, endpoint: String?, description: String) {
        self.name = name
        self.endpoint = endpoint
        self.description = description
    }
}

public enum DockerContextError: LocalizedError, Equatable {
    case unknownContext(String)
    case contextExists(String)
    case cannotRemoveDefault
    case contextInUse(String)
    case invalidEndpoint(String)
    case dockerCLINotFound

    public var errorDescription: String? {
        switch self {
        case .unknownContext(let name): "context \"\(name)\" does not exist"
        case .contextExists(let name): "context \"\(name)\" already exists"
        case .cannotRemoveDefault: "the default context cannot be removed"
        case .contextInUse(let name): "context \"\(name)\" is the current context; switch to another one first"
        case .invalidEndpoint(let value): "invalid docker endpoint \"\(value)\" (use unix://, ssh:// or tcp://)"
        case .dockerCLINotFound: "no docker CLI found to reach this endpoint; install one (Docker Desktop, Colima or OrbStack provide it)"
        }
    }
}

/// Reads and writes the context list and the current selection.
public struct DockerContextStore: Sendable {
    public static let defaultName = "default"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The store used by the app and the CLI.
    public static var standard: DockerContextStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DockerContextStore(url: support.appendingPathComponent("Macker/contexts.json"))
    }

    /// The built-in context for Macker's own runtime.
    public static let localRecord = DockerContextRecord(
        name: defaultName,
        endpoint: nil,
        description: "Apple container runtime (local)"
    )

    private struct File: Codable {
        var current: String
        var contexts: [DockerContextRecord]
    }

    private func read() -> File {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            return File(current: Self.defaultName, contexts: [])
        }
        return file
    }

    private func write(_ file: File) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    /// Every context, the default one first.
    public func list() -> [DockerContextRecord] {
        [Self.localRecord] + read().contexts.sorted { $0.name < $1.name }
    }

    /// The selected context.
    public func current() -> DockerContextRecord {
        let name = read().current
        return (try? find(name)) ?? Self.localRecord
    }

    public func find(_ name: String) throws -> DockerContextRecord {
        guard let record = list().first(where: { $0.name == name }) else {
            throw DockerContextError.unknownContext(name)
        }
        return record
    }

    public func create(name: String, endpoint: String?, description: String) throws {
        guard name != Self.defaultName, !list().contains(where: { $0.name == name }) else {
            throw DockerContextError.contextExists(name)
        }
        if let endpoint, !Self.isSupportedEndpoint(endpoint) {
            throw DockerContextError.invalidEndpoint(endpoint)
        }
        var file = read()
        file.contexts.append(DockerContextRecord(name: name, endpoint: endpoint, description: description))
        try write(file)
    }

    public func use(_ name: String) throws {
        _ = try find(name)
        var file = read()
        file.current = name
        try write(file)
    }

    public func remove(_ name: String) throws {
        guard name != Self.defaultName else { throw DockerContextError.cannotRemoveDefault }
        guard read().current != name else { throw DockerContextError.contextInUse(name) }
        _ = try find(name)
        var file = read()
        file.contexts.removeAll { $0.name == name }
        try write(file)
    }

    static func isSupportedEndpoint(_ endpoint: String) -> Bool {
        ["unix://", "ssh://", "tcp://"].contains { endpoint.hasPrefix($0) }
    }
}

/// Runs `docker context …` against the store and prints the same columns as Docker.
public enum DockerContextCommand {
    /// `args` are the docker arguments after `context`.
    public static func run(_ args: [String], store: DockerContextStore = .standard) throws {
        let command = try DockerCommandParser.parse(["context"] + args)
        switch command.subSubcommand {
        case nil, "ls", "list":
            let current = store.current().name
            print("NAME        DESCRIPTION                              DOCKER ENDPOINT                       CURRENT")
            for record in store.list() {
                let mark = record.name == current ? "*" : ""
                print("\(pad(record.name, 12))\(pad(record.description, 41))\(pad(record.endpoint ?? "(local)", 38))\(mark)")
            }
        case "show":
            print(store.current().name)
        case "use":
            guard let name = command.arguments.first else { throw DockerShimError.missingArgument("CONTEXT") }
            try store.use(name)
            print("Current context is now \"\(name)\"")
        case "create":
            guard let name = command.arguments.first else { throw DockerShimError.missingArgument("CONTEXT") }
            let host = command.value("docker").flatMap(hostValue)
            let endpoint = host
            try store.create(
                name: name,
                endpoint: endpoint,
                description: command.value(short: "d", long: "description") ?? ""
            )
            print("Successfully created context \"\(name)\"")
        case "inspect":
            guard let name = command.arguments.first else { throw DockerShimError.missingArgument("CONTEXT") }
            let record = try store.find(name)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode([record]), as: UTF8.self))
        case "rm", "remove":
            guard let name = command.arguments.first else { throw DockerShimError.missingArgument("CONTEXT") }
            try store.remove(name)
            print("\(name)")
        default:
            throw DockerShimError.unsupportedCommand("context \(command.subSubcommand ?? "")")
        }
    }

    /// `--docker host=unix:///x` → `unix:///x`.
    static func hostValue(_ option: String) -> String? {
        for part in option.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2, pair[0] == "host" { return pair[1] }
        }
        return nil
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}

/// Forwards a command to the external docker CLI for a non-default context.
public enum DockerForwarder {
    /// Strips `--context NAME` / `--context=NAME` from the arguments, returning
    /// the name (if any) and the remaining arguments.
    public static func extractContext(_ args: [String]) -> (name: String?, args: [String]) {
        var remaining: [String] = []
        var name: String?
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--context", index + 1 < args.count {
                name = args[index + 1]
                index += 2
                continue
            }
            if arg.hasPrefix("--context=") {
                name = String(arg.dropFirst("--context=".count))
                index += 1
                continue
            }
            remaining.append(arg)
            index += 1
        }
        return (name, remaining)
    }

    /// The docker CLI to delegate to: the first installed one that is not Macker itself.
    public static func locateDockerCLI() throws -> String {
        let own = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            NSHomeDirectory() + "/.orbstack/bin/docker",
            NSHomeDirectory() + "/.colima/bin/docker",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if URL(fileURLWithPath: path).resolvingSymlinksInPath().path != own {
                return path
            }
        }
        throw DockerContextError.dockerCLINotFound
    }

    /// Runs the docker CLI and collects its output (used by `macker migrate`).
    public static func capture(_ args: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try locateDockerCLI())
        process.arguments = args
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, stdout, stderr)
    }

    /// Runs `docker -H endpoint args…` with the terminal attached, and returns its exit code.
    public static func run(endpoint: String, args: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try locateDockerCLI())
        process.arguments = ["-H", endpoint] + args
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
