//===----------------------------------------------------------------------===//
// DockerShim — the `docker` subcommand.
//
// `macker docker <args>` parses the raw docker-style arguments and
// translates them to runtime operations. This is what gets symlinked as
// `docker` when the user opts in.
//===----------------------------------------------------------------------===//

import ArgumentParser
import Foundation
import ContainerBackend

/// The `docker` compatibility subcommand.
public struct DockerShimCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "docker",
        abstract: "Docker CLI compatibility shim.",
        discussion: """
        Translates common docker commands to Apple's native container runtime. \
        Symlink this binary as `docker` to use it transparently.
        """
    )

    /// Raw docker arguments, captured without ArgumentParser interpretation.
    @Argument(parsing: .captureForPassthrough)
    var dockerArgs: [String] = []

    public init() {}

    public func run() async throws {
        // Streaming commands (logs -f, stats, run attached) must flush each
        // line immediately; stdout is block-buffered when piped.
        setvbuf(stdout, nil, _IONBF, 0)

        // `--context NAME` picks a context for this call only.
        let (contextOverride, args) = DockerForwarder.extractContext(dockerArgs)
        if args.first == "context" {
            try DockerContextCommand.run(Array(args.dropFirst()))
            return
        }
        let store = DockerContextStore.standard
        let context = try contextOverride.map { try store.find($0) } ?? store.current()
        if let endpoint = context.endpoint {
            let status = try DockerForwarder.run(endpoint: endpoint, args: args)
            if status != 0 {
                throw ExitCode(status)
            }
            return
        }

        let command = try DockerCommandParser.parse(args)
        let translator = DockerTranslator()
        try await translator.execute(command)
    }
}
