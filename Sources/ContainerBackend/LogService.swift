//===----------------------------------------------------------------------===//
// LogService — streaming container logs.
//
// The XPC `containerLogs` route returns file handles for the container's
// stdout and stderr. This service reads those handles as an async sequence of
// lines, supporting both tail (read what's buffered) and follow (keep reading
// until cancelled) modes.
//===----------------------------------------------------------------------===//

import Foundation

/// A single log line with its originating stream.
public struct LogLine: Sendable, Equatable {
    public enum Stream: String, Sendable {
        case stdout
        case stderr
    }

    public let stream: Stream
    public let text: String

    public init(stream: Stream, text: String) {
        self.stream = stream
        self.text = text
    }
}

/// Streams container logs from the XPC-provided file handles.
public struct LogService: Sendable {
    private let client: ContainerAPIClient

    public init(client: ContainerAPIClient = ContainerAPIClient()) {
        self.client = client
    }

    /// An async sequence of log lines for a container.
    ///
    /// - Parameters:
    ///   - id: the container ID.
    ///   - follow: keep reading new output until cancelled (like `docker logs -f`).
    ///   - tail: only read the last `tail` lines of buffered output.
    public func logs(
        for id: String,
        follow: Bool = false,
        tail: Int? = nil
    ) -> AsyncThrowingStream<LogLine, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let handles = try await client.logs(id: id)
                    guard handles.count >= 2 else {
                        continuation.finish(throwing: BackendError.invalidResponse(
                            "expected stdout and stderr log handles for \(id)"
                        ))
                        return
                    }
                    let stdout = handles[0]
                    let stderr = handles[1]

                    // Read both streams concurrently, interleaving lines in
                    // arrival order.
                    let stdoutStream = Self.readLines(from: stdout, stream: .stdout, follow: follow)
                    let stderrStream = Self.readLines(from: stderr, stream: .stderr, follow: follow)

                    // In tail mode, buffer the last N lines and emit them once
                    // the buffered output is exhausted.
                    var ring: [LogLine] = []
                    let maxTail = tail ?? 0

                    for try await line in Self.merge(stdoutStream, stderrStream) {
                        if maxTail > 0 {
                            ring.append(line)
                            if ring.count > maxTail {
                                ring.removeFirst()
                            }
                        } else {
                            continuation.yield(line)
                        }
                    }

                    if maxTail > 0 {
                        for line in ring {
                            continuation.yield(line)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Read a file handle as an async sequence of lines.
    private static func readLines(
        from handle: FileHandle,
        stream: LogLine.Stream,
        follow: Bool
    ) -> AsyncThrowingStream<LogLine, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buffer = Data()
                while !Task.isCancelled {
                    let chunk: Data
                    do {
                        chunk = try handle.read(upToCount: 4096) ?? Data()
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                    if chunk.isEmpty {
                        // EOF. In non-follow mode the buffered output is
                        // exhausted, so stop. In follow mode we keep the handle
                        // open and wait for more; the caller cancels to stop.
                        if !follow || Task.isCancelled {
                            break
                        }
                        try await Task.sleep(for: .milliseconds(200))
                        continue
                    }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let lineData = buffer[..<newline]
                        buffer.removeSubrange(...newline)
                        if let text = String(data: lineData, encoding: .utf8) {
                            continuation.yield(LogLine(stream: stream, text: text))
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Merge two async sequences in arrival order.
    private static func merge(
        _ a: AsyncThrowingStream<LogLine, Error>,
        _ b: AsyncThrowingStream<LogLine, Error>
    ) -> AsyncThrowingStream<LogLine, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        do {
                            for try await line in a {
                                continuation.yield(line)
                            }
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    group.addTask {
                        do {
                            for try await line in b {
                                continuation.yield(line)
                            }
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    await group.waitForAll()
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
