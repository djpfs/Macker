//===----------------------------------------------------------------------===//
// Main — dual-binary dispatch.
//
// One executable, two modes:
//   • No arguments          → SwiftUI GUI
//   • With arguments        → headless CLI (ArgumentParser)
//
// The CLI path runs `AppleDockerCLICommand.main()` in a task; ArgumentParser
// calls `exit()` itself with the proper exit code, terminating the process.
//
// Docker-compatibility: the binary is meant to be symlinked as `docker` (and
// `docker-compose`), so `docker ps`, `docker run`, etc. must work directly.
// The docker shim lives under the `docker` subcommand, so when the first
// argument is not a known top-level subcommand we transparently prepend
// `docker` — making `macker ps` and `docker ps` equivalent.
//===----------------------------------------------------------------------===//

import Foundation
import AppKit
import AppleDockerCLI

@main
enum Main {
    /// Top-level subcommands that are NOT routed to the docker shim.
    private static let knownSubcommands: Set<String> = [
        "version", "selftest", "system", "docker",
        "help", "--help", "-h", "--version",
    ]

    static func main() {
        // Any argument (including `--help`, `version`, `docker`, …) routes to
        // the CLI. No arguments launches the GUI.
        if CommandLine.arguments.count > 1 {
            Task {
                await runCLI()
                // ArgumentParser only exits itself on error; on success we must
                // terminate explicitly because dispatchMain() never returns.
                exit(0)
            }
            dispatchMain()
        } else {
            // Running as a bare executable (not a .app bundle) the app is not
            // activated by LaunchServices, so the window would never appear.
            // Activate explicitly so the GUI comes to the front.
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            AppleDockerApp.main()
        }
    }

    /// Run the CLI, transparently routing unknown top-level commands to the
    /// docker shim so `docker ps` / `macker ps` both work.
    private static func runCLI() async {
        var args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first, !knownSubcommands.contains(first) {
            args.insert("docker", at: 0)
        }
        await AppleDockerCLICommand.main(args)
    }
}
