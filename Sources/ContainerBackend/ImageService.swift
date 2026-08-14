//===----------------------------------------------------------------------===//
// ImageService — image management.
//
// Image operations have no stable XPC route in the apiserver (they live in the
// separate `container-core-images` service), so this service shells out to the
// `container image` CLI. The output is parsed from `--format json` where
// available. When Apple stabilizes the images XPC protocol, swap this
// implementation for an XPC-backed one without changing the public API.
//===----------------------------------------------------------------------===//

import Foundation

/// A lightweight summary of a container image, parsed from the CLI JSON output.
public struct ImageSummary: Sendable, Codable, Identifiable, Equatable {
    /// The image ID (a digest).
    public var id: String
    /// The image reference, e.g. `docker.io/library/node:22-alpine`.
    public var name: String
    /// The descriptor digest, e.g. `sha256:…`.
    public var digest: String
    /// Total size in bytes across the image's variants.
    public var size: UInt64
    /// When the image was created.
    public var creationDate: Date
    /// The platform of the first variant, e.g. `linux/arm64`.
    public var platform: String?

    /// The tag portion of the reference, if any.
    public var tag: String? {
        guard let colon = name.lastIndex(of: ":") else { return nil }
        let after = name[name.index(after: colon)...]
        return after.contains("/") ? nil : String(after)
    }

    /// The repository portion of the reference (without tag).
    public var repository: String {
        guard let colon = name.lastIndex(of: ":") else { return name }
        let after = name[name.index(after: colon)...]
        return after.contains("/") ? name : String(name[..<colon])
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case digest
        case size
        case creationDate
        case platform
    }
}

/// Manages images via the `container image` CLI.
public struct ImageService: Sendable {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// List all images.
    public func list() async throws -> [ImageSummary] {
        let result = try await runner.run(["image", "list", "--format", "json"], timeout: .seconds(30))
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "image list failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        return try Self.parseListJSON(result.stdout)
    }

    /// Pull an image by reference (e.g. `nginx`, `node:22-alpine`).
    public func pull(_ reference: String, platform: String? = nil) async throws {
        var args = ["image", "pull", "--progress", "plain"]
        if let platform {
            args += ["--platform", platform]
        }

        /// Authenticate to an OCI registry. The password is sent over stdin and
        /// never appears in the process arguments or environment.
        public func login(
            registry: String,
            username: String,
            password: String
        ) async throws {
            let result = try await runner.run(
                ["registry", "login", "--username", username, "--password-stdin", registry],
                standardInput: Data((password + "\n").utf8),
                timeout: .seconds(60)
            )
            guard result.succeeded else {
                throw BackendError.operationFailed(
                    "registry login failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
            }
        }

        /// Build an image using a Dockerfile or Containerfile.
        public func build(
            context: String,
            tag: String? = nil,
            dockerfile: String? = nil,
            buildArgs: [String: String] = [:],
            noCache: Bool = false
        ) async throws -> String {
            var args = ["build", "--progress", "plain"]
            if let tag, !tag.isEmpty { args += ["-t", tag] }
            if let dockerfile, !dockerfile.isEmpty { args += ["-f", dockerfile] }
            for (key, value) in buildArgs.sorted(by: { $0.key < $1.key }) {
                args += ["--build-arg", "\(key)=\(value)"]
            }
            if noCache { args.append("--no-cache") }
            args.append(context)
            let result = try await runner.run(args, timeout: .seconds(1800))
            guard result.succeeded else {
                throw BackendError.operationFailed(
                    "image build failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
            }
            return result.stdout.isEmpty ? result.stderr : result.stdout
        }
        args.append(reference)
        let result = try await runner.run(args, timeout: .seconds(600))
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "image pull failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }

    /// Delete one or more images by ID or reference.
    public func delete(_ references: [String]) async throws {
        guard !references.isEmpty else { return }
        let result = try await runner.run(["image", "delete"] + references, timeout: .seconds(60))
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "image delete failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }

    /// Tag an image with a new reference.
    public func tag(_ source: String, _ target: String) async throws {
        let result = try await runner.run(["image", "tag", source, target], timeout: .seconds(30))
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "image tag failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }

    /// Push an image to its registry.
    public func push(_ reference: String) async throws {
        let result = try await runner.run(["image", "push", reference], timeout: .seconds(600))
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "image push failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }

    /// Remove unused images. When `all` is true, removes ALL images (not just
    /// dangling ones) — this is the `container image prune -a` behavior that
    /// reclaims the most space.
    public func prune(all: Bool = false) async throws {
        var args = ["image", "prune"]
        if all {
            args.append("-a")
        }
        let result = try await runner.run(args, timeout: .seconds(120))
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "image prune failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }

    // MARK: - Parsing

    /// Parses the `container image list --format json` output.
    static func parseListJSON(_ json: String) throws -> [ImageSummary] {
        struct RawImage: Decodable {
            struct Configuration: Decodable {
                let name: String
                let creationDate: Date
                let descriptor: Descriptor
            }
            struct Descriptor: Decodable {
                let digest: String
            }
            struct Variant: Decodable {
                struct Platform: Decodable {
                    let os: String?
                    let architecture: String?
                    let variant: String?
                }
                let platform: Platform?
                let size: UInt64?
            }
            let id: String
            let configuration: Configuration
            let variants: [Variant]?
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let raw = try decoder.decode([RawImage].self, from: Data(json.utf8))

        return raw.map { image in
            let totalSize = image.variants?.reduce(0) { $0 + ($1.size ?? 0) } ?? 0
            let platform: String?
            if let p = image.variants?.first?.platform {
                var parts = [p.os, p.architecture].compactMap { $0 }
                if let variant = p.variant, !variant.isEmpty {
                    parts.append(variant)
                }
                platform = parts.isEmpty ? nil : parts.joined(separator: "/")
            } else {
                platform = nil
            }
            return ImageSummary(
                id: image.id,
                name: image.configuration.name,
                digest: image.configuration.descriptor.digest,
                size: totalSize,
                creationDate: image.configuration.creationDate,
                platform: platform
            )
        }
    }
}
