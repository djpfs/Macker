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
    private let scanner: VulnerabilityScanner
    private let auditLogger: AuditLogger

    public init(
        runner: ProcessRunner = ProcessRunner(),
        scanner: VulnerabilityScanner = VulnerabilityScanner(),
        auditLogger: AuditLogger = .shared
    ) {
        self.runner = runner
        self.scanner = scanner
        self.auditLogger = auditLogger
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

        args.append(reference)
        let result = try await runner.run(args, timeout: .seconds(600))
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "image pull failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        await auditLogger.record(action: "image.pull", target: reference, succeeded: true)
    }

    /// Authenticate to an OCI registry without exposing the password in args.
    public func login(registry: String, username: String, password: String) async throws {
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

    /// Build an image from a Dockerfile or Containerfile.
    ///
    /// - Parameters:
    ///   - context: Path to the build context directory.
    ///   - dockerfile: Optional path to a Dockerfile/Containerfile.
    ///   - tags: Image tags to apply, e.g. `["registry.example.com/app:latest"]`.
    ///   - buildArgs: Build-time variables passed as `--build-arg KEY=VALUE`.
    ///   - useCache: When `false`, passes `--no-cache` to disable layer caching.
    /// - Returns: Combined CLI output (stdout preferred, stderr as fallback).
    @discardableResult
    public func build(
        context: String,
        dockerfile: String? = nil,
        tags: [String] = [],
        buildArgs: [String: String] = [:],
        useCache: Bool = true
    ) async throws -> String {
        var args = ["build", "--progress", "plain"]
        for tag in tags { args += ["-t", tag] }
        if let dockerfile, !dockerfile.isEmpty { args += ["-f", dockerfile] }
        for (key, value) in buildArgs.sorted(by: { $0.key < $1.key }) {
            args += ["--build-arg", "\(key)=\(value)"]
        }
        if !useCache { args.append("--no-cache") }
        args.append(context)
        let result = try await runner.run(args, timeout: .seconds(1800))
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "image build failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        return result.stdout.isEmpty ? result.stderr : result.stdout
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
        await auditLogger.record(action: "image.delete", target: references.joined(separator: ","), succeeded: true)
    }

    /// Tag an image with a new reference.
    public func tag(_ source: String, _ target: String) async throws {
        let result = try await runner.run(["image", "tag", source, target], timeout: .seconds(30))
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "image tag failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        await auditLogger.record(action: "image.tag", target: "\(source)->\(target)", succeeded: true)
    }

    /// Push an image to its registry.
    public func push(_ reference: String) async throws {
        let result = try await runner.run(["image", "push", reference], timeout: .seconds(600))
        guard result.succeeded else {
            throw BackendError.operationFailed(
                "image push failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        await auditLogger.record(action: "image.push", target: reference, succeeded: true)
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
        await auditLogger.record(action: "image.prune", target: all ? "all" : "dangling", succeeded: true)
    }

    /// Scan an image for known vulnerabilities.
    public func scan(reference: String, severities: [String] = ["CRITICAL", "HIGH", "MEDIUM", "LOW"]) async throws -> VulnerabilityScanReport {
        do {
            let report = try await scanner.scan(imageReference: reference, severities: severities)
            await auditLogger.record(action: "image.scan", target: reference, succeeded: true)
            return report
        } catch {
            await auditLogger.record(action: "image.scan", target: reference, succeeded: false, detail: error.localizedDescription)
            throw error
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
