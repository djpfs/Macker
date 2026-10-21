//===----------------------------------------------------------------------===//
// Migration — `macker migrate`: copy images from Docker Desktop, Colima or
// OrbStack into Apple's container runtime.
//
// Images are the only thing copied. Each one is saved with the source daemon's
// docker CLI (`docker -H <socket> save`) and loaded with `container image load`.
// Containers, volumes and compose projects are not moved; recreate them with
// `docker compose up` after the images are in place.
//===----------------------------------------------------------------------===//

import ArgumentParser
import ContainerBackend
import Foundation

/// A Docker-compatible runtime that `macker migrate` can read images from.
public enum MigrationSource: String, CaseIterable, ExpressibleByArgument {
    case dockerDesktop = "docker-desktop"
    case orbstack
    case colima

    /// Socket candidates for the runtime, in order.
    var sockets: [String] {
        let home = NSHomeDirectory()
        switch self {
        case .dockerDesktop: return [home + "/.docker/run/docker.sock"]
        case .orbstack: return [home + "/.orbstack/run/docker.sock"]
        case .colima: return [home + "/.colima/default/docker.sock", home + "/.colima/docker.sock"]
        }
    }

    /// The first socket that exists, as a docker endpoint.
    func endpoint() -> String? {
        sockets.first { FileManager.default.fileExists(atPath: $0) }.map { "unix://" + $0 }
    }
}

/// `macker migrate --from colima [--dry-run]`.
public struct MigrateCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Copy images from Docker Desktop, Colima or OrbStack into Macker."
    )

    @Option(name: .long, help: "Source runtime: docker-desktop, orbstack or colima.")
    var from: MigrationSource

    @Flag(name: .long, help: "List the images that would be copied, without copying them.")
    var dryRun = false

    public init() {}

    public func run() async throws {
        guard let endpoint = from.endpoint() else {
            throw ValidationError("\(from.rawValue) does not appear to be running (no socket found).")
        }
        let images = try listImages(endpoint: endpoint)
        if images.isEmpty {
            print("No images to copy from \(from.rawValue).")
            return
        }
        print("\(images.count) image(s) on \(from.rawValue):")
        for image in images { print("  \(image)") }
        if dryRun { return }

        let runner = ProcessRunner()
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macker-migrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        var failed: [String] = []
        for image in images {
            print("Copying \(image)...")
            let archive = workDir.appendingPathComponent(UUID().uuidString + ".tar").path
            do {
                let save = try DockerForwarder.capture(["-H", endpoint, "save", "-o", archive, image])
                guard save.status == 0 else { throw MigrationError.saveFailed(image, save.stderr) }
                let load = try await runner.run(["image", "load", "-i", archive], timeout: .seconds(1800))
                guard load.succeeded else { throw MigrationError.loadFailed(image, load.stderr) }
                print("  done")
            } catch {
                print("  failed: \(error.localizedDescription)")
                failed.append(image)
            }
            try? FileManager.default.removeItem(atPath: archive)
        }
        if !failed.isEmpty {
            throw ExitCode(1)
        }
        print("Copied \(images.count) image(s).")
    }

    private func listImages(endpoint: String) throws -> [String] {
        let result = try DockerForwarder.capture(["-H", endpoint, "images", "--format", "{{.Repository}}:{{.Tag}}"])
        guard result.status == 0 else {
            throw MigrationError.listFailed(result.stderr)
        }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("<none>") }
    }
}

enum MigrationError: LocalizedError {
    case listFailed(String)
    case saveFailed(String, String)
    case loadFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .listFailed(let detail): "could not list images: \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .saveFailed(let image, let detail): "could not save \(image): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .loadFailed(let image, let detail): "could not load \(image): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}
