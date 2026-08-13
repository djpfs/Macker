//===----------------------------------------------------------------------===//
// ComposeParser — parses a docker-compose.yml into a ComposeProject.
//
// Pipeline:
//   1. Load the raw YAML into a generic tree (Yams `YAML.load`).
//   2. Interpolate `${VAR}` references using the process environment plus the
//      project's `.env` file (shell env wins, matching docker compose).
//   3. Convert the interpolated tree to JSON and decode into the typed model.
//
// Interpolating before type decoding matters: `cpus: ${CPUS}` must become the
// number 2, not the string "2", so the Double field can decode.
//===----------------------------------------------------------------------===//

import Foundation
import Yams

/// Errors produced while parsing or validating a compose file.
public enum ComposeParseError: Error, LocalizedError, Equatable {
    case unreadableFile(String)
    case invalidYAML(String)
    case missingImageOrBuild(String)
    case unknownDependency(String, String)
    case unknownNetwork(String, String)
    case unknownVolume(String, String)
    case circularDependency([String])
    case interpolationError(String, String)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let path):
            return "compose: cannot read file: \(path)"
        case .invalidYAML(let message):
            return "compose: invalid YAML: \(message)"
        case .missingImageOrBuild(let service):
            return "compose: service '\(service)' must specify an image or a build"
        case .unknownDependency(let service, let dep):
            return "compose: service '\(service)' depends on undefined service '\(dep)'"
        case .unknownNetwork(let service, let network):
            return "compose: service '\(service)' references undefined network '\(network)'"
        case .unknownVolume(let service, let volume):
            return "compose: service '\(service)' references undefined volume '\(volume)'"
        case .circularDependency(let chain):
            return "compose: circular dependency: \(chain.joined(separator: " -> "))"
        case .interpolationError(let variable, let message):
            return "compose: interpolation error for '\(variable)': \(message)"
        }
    }
}

/// Parses compose files.
public struct ComposeParser: Sendable {
    public init() {}

    /// Parse a compose file at `path`, resolving relative paths against the
    /// file's directory and loading a sibling `.env` file for interpolation.
    public func parse(fileAt path: String) throws -> ComposeProject {
        let url = URL(fileURLWithPath: path)
        let yaml: String
        do {
            yaml = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ComposeParseError.unreadableFile(path)
        }
        let env = try loadEnvFile(in: url.deletingLastPathComponent())
        return try parse(yaml: yaml, env: env, baseDirectory: url.deletingLastPathComponent().path)
    }

    /// Parse a compose YAML string. `env` supplies interpolation variables
    /// (the process environment is always consulted first).
    public func parse(yaml: String, env: [String: String] = [:], baseDirectory: String = ".") throws -> ComposeProject {
        let tree: Any
        do {
            tree = try Yams.load(yaml: yaml) ?? [:]
        } catch {
            throw ComposeParseError.invalidYAML(error.localizedDescription)
        }

        // Shell environment wins over the .env file, matching docker compose.
        var variables = env
        for (key, value) in ProcessInfo.processInfo.environment {
            variables[key] = value
        }

        let interpolated = interpolate(tree, env: variables)
        let normalized = normalizeEmptyDeclarations(interpolated)

        let project: ComposeProject
        do {
            let data = try JSONSerialization.data(withJSONObject: normalized)
            project = try JSONDecoder().decode(ComposeProject.self, from: data)
        } catch {
            throw ComposeParseError.invalidYAML(error.localizedDescription)
        }

        var result = project
        if result.name.isEmpty {
            result.name = URL(fileURLWithPath: baseDirectory).lastPathComponent
        }
        try validate(result)
        return result
    }

    // MARK: - Validation

    /// Validate cross-references between services, networks and volumes.
    public func validate(_ project: ComposeProject) throws {
        for (name, service) in project.services {
            if service.image == nil && service.build == nil {
                throw ComposeParseError.missingImageOrBuild(name)
            }
            for dep in service.dependsOn.keys where project.services[dep] == nil {
                throw ComposeParseError.unknownDependency(name, dep)
            }
            for network in service.networks where project.networks[network] == nil {
                // The implicit `default` network always exists.
                if network != "default" {
                    throw ComposeParseError.unknownNetwork(name, network)
                }
            }
            for volume in namedVolumes(in: service.volumes) where project.volumes[volume] == nil {
                throw ComposeParseError.unknownVolume(name, volume)
            }
        }
        _ = try ServiceResolver.resolve(project)
    }

    /// Extract the named-volume references from a service's volume mounts.
    private func namedVolumes(in mounts: [String]) -> [String] {
        mounts.compactMap { mount in
            let parts = mount.split(separator: ":", omittingEmptySubsequences: false)
            guard let first = parts.first else { return nil }
            let source = String(first)
            // Bind mounts (absolute paths, `./`, `~/`, `../`, or the bare
            // relative sources `.` / `..`) are not named volumes.
            if source.hasPrefix("/") || source.hasPrefix("./") || source.hasPrefix("../")
                || source.hasPrefix("~/") || source == "." || source == ".." {
                return nil
            }
            return source
        }
    }

    // MARK: - Normalization

    /// Compose allows empty declarations like `volumes: {data:}` (a volume
    /// with no options). Yams parses those as `null`, which fails to decode
    /// into a typed config. Replace null values in the top-level resource
    /// sections with empty dictionaries.
    private func normalizeEmptyDeclarations(_ tree: Any) -> Any {
        guard var dict = tree as? [String: Any] else { return tree }
        for key in ["volumes", "networks", "configs", "secrets"] {
            if var section = dict[key] as? [String: Any] {
                for (name, value) in section where value is NSNull {
                    section[name] = [:]
                }
                dict[key] = section
            }
        }
        return dict
    }

    // MARK: - Interpolation

    /// Recursively interpolate `${VAR}` references in every string in the tree.
    private func interpolate(_ value: Any, env: [String: String]) -> Any {
        if let string = value as? String {
            return interpolateString(string, env: env)
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { interpolate($0, env: env) }
        }
        if let array = value as? [Any] {
            return array.map { interpolate($0, env: env) }
        }
        return value
    }

    /// Interpolate a single string. Supports `${VAR}`, `${VAR:-def}`,
    /// `${VAR-def}`, `${VAR:?err}`, `${VAR?err}` and `$$` (literal `$`).
    func interpolateString(_ string: String, env: [String: String]) -> String {
        var result = ""
        var index = string.startIndex

        while index < string.endIndex {
            let char = string[index]
            if char == "$" {
                let next = string.index(after: index)
                if next < string.endIndex {
                    if string[next] == "$" {
                        result.append("$")
                        index = string.index(after: next)
                        continue
                    }
                    if string[next] == "{" {
                        if let (value, endIndex) = expandVariable(string, from: next, env: env) {
                            result.append(value)
                            index = endIndex
                            continue
                        }
                    }
                }
                // A lone `$` is passed through verbatim.
                result.append("$")
                index = next
            } else {
                result.append(char)
                index = string.index(after: index)
            }
        }
        return result
    }

    /// Expand `${...}` starting at the `{`. Returns the value and the index
    /// just past the closing `}`.
    private func expandVariable(_ string: String, from openBrace: String.Index, env: [String: String]) -> (String, String.Index)? {
        var index = string.index(after: openBrace)
        var name = ""
        while index < string.endIndex, string[index] != "}" {
            name.append(string[index])
            index = string.index(after: index)
        }
        guard index < string.endIndex else { return nil }
        let closeBrace = index
        let endIndex = string.index(after: closeBrace)

        // Parse the modifier: `VAR`, `VAR:-def`, `VAR-def`, `VAR:?err`, `VAR?err`.
        var variable = name
        var modifier: Character?
        var defaultValue: String?
        var errorMessage: String?

        if let colon = name.firstIndex(of: ":") {
            variable = String(name[..<colon])
            let rest = name[name.index(after: colon)...]
            if let q = rest.first, q == "-" || q == "?" {
                modifier = q
                defaultValue = String(rest.dropFirst())
            }
        } else if let dash = name.firstIndex(of: "-") {
            variable = String(name[..<dash])
            modifier = "-"
            defaultValue = String(name[name.index(after: dash)...])
        } else if let q = name.firstIndex(of: "?") {
            variable = String(name[..<q])
            modifier = "?"
            errorMessage = String(name[name.index(after: q)...])
        }

        let value = env[variable]
        let isSet = value != nil
        let isEmpty = value?.isEmpty ?? true

        switch modifier {
        case "-":
            if isSet && !isEmpty {
                return (value!, endIndex)
            }
            return (defaultValue ?? "", endIndex)
        case "?":
            if isSet && !isEmpty {
                return (value!, endIndex)
            }
            return (errorMessage ?? "", endIndex)
        default:
            return (value ?? "", endIndex)
        }
    }

    // MARK: - .env file

    /// Load `KEY=VALUE` pairs from a `.env` file in `directory`, if present.
    func loadEnvFile(in directory: URL) throws -> [String: String] {
        let url = directory.appendingPathComponent(".env")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return [:]
        }
        var result: [String: String] = [:]
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes.
            if value.count >= 2, value.first == "\"", value.last == "\"" {
                value = String(value.dropFirst().dropLast())
            } else if value.count >= 2, value.first == "'", value.last == "'" {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}
