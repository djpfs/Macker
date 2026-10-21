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

    @Flag(name: .long, help: "Also copy named volumes, with their contents.")
    var volumes = false

    @Option(name: .long, help: "Image used to read and write volume contents. It must contain tar.")
    var helperImage = "alpine:latest"

    public init() {}

    public func run() async throws {
        guard let endpoint = from.endpoint() else {
            throw ValidationError("\(from.rawValue) does not appear to be running (no socket found).")
        }
        let images = try listImages(endpoint: endpoint)
        let volumeNames = volumes ? try listVolumes(endpoint: endpoint) : []
        if images.isEmpty && volumeNames.isEmpty {
            print("Nothing to copy from \(from.rawValue).")
            return
        }
        print("\(images.count) image(s) on \(from.rawValue):")
        for image in images { print("  \(image)") }
        if volumes {
            print("\(volumeNames.count) volume(s) on \(from.rawValue):")
            for name in volumeNames { print("  \(name)") }
        }
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
        for name in volumeNames {
            print("Copying volume \(name)...")
            do {
                try await copyVolume(name, endpoint: endpoint, workDir: workDir)
                print("  done")
            } catch {
                print("  failed: \(error.localizedDescription)")
                failed.append("volume:\(name)")
            }
        }
        if !failed.isEmpty {
            throw ExitCode(1)
        }
        print("Copied \(images.count) image(s)\(volumes ? " and \(volumeNames.count) volume(s)" : "").")
    }

    /// Reads a volume's contents with `tar` in the source daemon, then unpacks them
    /// into a volume of the same name in Macker.
    private func copyVolume(_ name: String, endpoint: String, workDir: URL) async throws {
        let archive = workDir.appendingPathComponent(UUID().uuidString + ".tar")
        defer { try? FileManager.default.removeItem(at: archive) }

        let read = try DockerForwarder.capture(
            ["-H", endpoint, "run", "--rm", "-v", "\(name):/src", helperImage, "tar", "-C", "/src", "-cf", "-", "."],
            stdoutTo: archive
        )
        guard read.status == 0 else { throw MigrationError.volumeReadFailed(name, read.stderr) }

        let runner = ProcessRunner()
        _ = try? await runner.run(["volume", "create", name], timeout: .seconds(60))
        let data = try Data(contentsOf: archive)
        let write = try await runner.run(
            ["run", "--rm", "-i", "-v", "\(name):/dst", helperImage, "tar", "-C", "/dst", "-xf", "-"],
            standardInput: data,
            timeout: .seconds(1800)
        )
        guard write.succeeded else { throw MigrationError.volumeWriteFailed(name, write.stderr) }
    }

    private func listVolumes(endpoint: String) throws -> [String] {
        let result = try DockerForwarder.capture(["-H", endpoint, "volume", "ls", "--format", "{{.Name}}"])
        guard result.status == 0 else { throw MigrationError.listFailed(result.stderr) }
        return result.stdout.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
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
    case volumeReadFailed(String, String)
    case volumeWriteFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .listFailed(let detail): "could not list images: \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .saveFailed(let image, let detail): "could not save \(image): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .loadFailed(let image, let detail): "could not load \(image): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .volumeReadFailed(let name, let detail): "could not read volume \(name): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .volumeWriteFailed(let name, let detail): "could not write volume \(name): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}
