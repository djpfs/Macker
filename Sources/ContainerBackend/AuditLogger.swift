//===----------------------------------------------------------------------===//
// AuditLogger — persistent audit trail for runtime actions.
//===----------------------------------------------------------------------===//

import Foundation

/// A single audited action.
public struct AuditEvent: Sendable, Codable, Identifiable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var action: String
    public var target: String?
    public var succeeded: Bool
    public var detail: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: String,
        target: String? = nil,
        succeeded: Bool,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.target = target
        self.succeeded = succeeded
        self.detail = detail
    }
}

/// Writes audit events to `~/.macker/audit.jsonl`.
public actor AuditLogger {
    private let logFileURL: URL
    private let encoder: JSONEncoder

    public init(logFileURL: URL? = nil) {
        if let logFileURL {
            self.logFileURL = logFileURL
        } else {
            let base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".macker", isDirectory: true)
            self.logFileURL = base.appendingPathComponent("audit.jsonl")
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    /// Record an action result. Logging failures are ignored so runtime
    /// operations are never blocked by audit I/O issues.
    public func record(action: String, target: String? = nil, succeeded: Bool, detail: String? = nil) {
        let event = AuditEvent(action: action, target: target, succeeded: succeeded, detail: detail)
        guard let data = try? encoder.encode(event) else { return }
        appendLine(data)
    }

    private func appendLine(_ data: Data) {
        let fm = FileManager.default
        let directory = logFileURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

            if !fm.fileExists(atPath: logFileURL.path) {
                fm.createFile(atPath: logFileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            handle.write(data)
            handle.write(Data([0x0a]))
        } catch {
            // Best effort only.
        }
    }
}
