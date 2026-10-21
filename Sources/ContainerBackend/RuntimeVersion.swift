//===----------------------------------------------------------------------===//
// RuntimeVersion — installed / recommended / latest apple/container versions.
//
// Three versions matter to the user:
//   • installed   — what `container --version` reports on this Mac
//   • recommended — what this build of Macker was tested against
//   • latest      — newest apple/container release on GitHub
//
// The upgrade path downloads Apple's signed installer package for the
// recommended release, checks its SHA-256 against the GitHub asset digest,
// and runs it with administrator privileges.
//===----------------------------------------------------------------------===//

import Foundation
import CryptoKit

public enum RuntimeVersion {
    /// Version Macker is built and tested against. Keep in sync with
    /// `containerVersion` in Package.swift (that file is not readable at runtime).
    public static let recommended = "1.6.0"

    /// A GitHub release of apple/container with its signed installer package.
    public struct Release: Sendable, Equatable {
        public let tag: String
        public let installerURL: URL
        public let installerName: String
        /// Hex SHA-256 of the installer, from the GitHub asset digest.
        public let sha256: String?
    }

    public enum Failure: LocalizedError, Equatable {
        case releaseLookupFailed(String)
        case installerNotFound(String)
        case missingDigest(String)
        case digestMismatch(String)
        case downloadFailed(Int)

        public var errorDescription: String? {
            switch self {
            case .releaseLookupFailed(let tag):
                return "Could not read apple/container release \(tag) from GitHub."
            case .installerNotFound(let tag):
                return "Release \(tag) has no signed installer package."
            case .missingDigest(let name):
                return "\(name) has no checksum published, refusing to install it."
            case .digestMismatch(let name):
                return "Checksum mismatch for \(name). The download was discarded."
            case .downloadFailed(let status):
                return "Installer download failed (HTTP \(status))."
            }
        }
    }

    // MARK: - Installed

    /// Version reported by the installed `container` CLI, or nil if it is not installed.
    public static func installedVersion(runner: ProcessRunner = ProcessRunner()) async -> String? {
        guard let result = try? await runner.run(["--version"], timeout: .seconds(10)),
              result.succeeded else { return nil }
        return parseVersion(result.stdout + result.stderr)
    }

    /// Extracts `1.2.2` from `container CLI version 1.2.2 (build: release, commit: 0190097)`.
    public static func parseVersion(_ text: String) -> String? {
        guard let range = text.range(of: #"version\s+\d+(\.\d+)+"#, options: .regularExpression) else {
            return nil
        }
        return text[range].split(separator: " ").last.map(String.init)
    }

    /// True when `a` is strictly older than `b`, comparing dot-separated numbers.
    public static func isOlder(_ a: String, than b: String) -> Bool {
        let left = numericParts(a)
        let right = numericParts(b)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r }
        }
        return false
    }

    private static func numericParts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    // MARK: - Release lookup

    /// Looks up a release by tag, or the latest release when `tag` is nil.
    public static func release(tag: String? = nil, session: URLSession = .shared) async throws -> Release {
        let endpoint = tag.map { "https://api.github.com/repos/apple/container/releases/tags/\($0)" }
            ?? "https://api.github.com/repos/apple/container/releases/latest"
        guard let url = URL(string: endpoint) else {
            throw Failure.releaseLookupFailed(tag ?? "latest")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure.releaseLookupFailed(tag ?? "latest")
        }
        return try parseRelease(data, requestedTag: tag)
    }

    /// Decodes a GitHub release payload and picks the signed installer asset.
    static func parseRelease(_ data: Data, requestedTag: String?) throws -> Release {
        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = payload.assets.first(where: { $0.name.hasSuffix("-installer-signed.pkg") }) else {
            throw Failure.installerNotFound(payload.tagName)
        }
        let digest = asset.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        return Release(
            tag: payload.tagName,
            installerURL: asset.browserDownloadURL,
            installerName: asset.name,
            sha256: digest
        )
    }

    // MARK: - Download

    /// Downloads the installer into a temporary folder and verifies its SHA-256.
    /// The file is removed again if the checksum does not match.
    public static func download(_ release: Release, session: URLSession = .shared) async throws -> URL {
        guard let expected = release.sha256 else {
            throw Failure.missingDigest(release.installerName)
        }
        let (tempFile, response) = try await session.download(from: release.installerURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            try? FileManager.default.removeItem(at: tempFile)
            throw Failure.downloadFailed(status)
        }

        let digest = SHA256.hash(data: try Data(contentsOf: tempFile, options: .mappedIfSafe))
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else {
            try? FileManager.default.removeItem(at: tempFile)
            throw Failure.digestMismatch(release.installerName)
        }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("macker-runtime-\(release.tag)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(release.installerName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempFile, to: destination)
        return destination
    }

    // MARK: - GitHub payload

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case digest
            }
        }
    }
}
