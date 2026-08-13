//===----------------------------------------------------------------------===//
// StatsService — streaming container statistics.
//
// The XPC `containerStats` route returns a point-in-time snapshot. Streaming is
// implemented as polling on a configurable interval, which is what the GUI
// needs for live resource charts. The sequence terminates when the container
// disappears or the poll fails with a non-transient error.
//===----------------------------------------------------------------------===//

import Foundation

/// Streams `ContainerStats` snapshots for a container.
public struct StatsService: Sendable {
    private let client: ContainerAPIClient

    public init(client: ContainerAPIClient = ContainerAPIClient()) {
        self.client = client
    }

    /// An async sequence of stats snapshots, polled every `interval`.
    ///
    /// - Parameters:
    ///   - id: the container ID.
    ///   - interval: polling interval (default 2s, matching the GUI cadence).
    ///   - maxSamples: stop after this many samples, or `nil` for unbounded.
    public func stats(
        for id: String,
        interval: Duration = .seconds(2),
        maxSamples: Int? = nil
    ) -> AsyncThrowingStream<ContainerStats, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var samples = 0
                while !Task.isCancelled {
                    do {
                        let snapshot = try await client.stats(id: id)
                        continuation.yield(snapshot)
                        samples += 1
                        if let maxSamples, samples >= maxSamples {
                            break
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                    try await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
