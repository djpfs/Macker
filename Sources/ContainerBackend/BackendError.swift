//===----------------------------------------------------------------------===//
// BackendError — typed errors surfaced by the container backend layer.
//===----------------------------------------------------------------------===//

import Foundation

public enum BackendError: Error, LocalizedError, Sendable {
    /// The XPC service connection was interrupted (daemon stopped / crashed).
    case connectionInterrupted
    /// The request timed out waiting for a response.
    case timeout(route: String)
    /// The requested resource does not exist.
    case notFound(String)
    /// A protocol-level error was reported by the apiserver.
    case protocolError(code: String, message: String)
    /// The response was missing or could not be decoded.
    case invalidResponse(String)
    /// A payload could not be encoded.
    case encodingFailed(String)
    /// The daemon reported an error while executing an operation.
    case operationFailed(String)
    /// The container runtime was not found or could not be started.
    case runtimeUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .connectionInterrupted:
            return "connection to container-apiserver was interrupted"
        case .timeout(let route):
            return "timed out waiting for a response from \(route)"
        case .notFound(let what):
            return "\(what) not found"
        case .protocolError(let code, let message):
            return "\(message) (\(code))"
        case .invalidResponse(let message):
            return "invalid response from container-apiserver: \(message)"
        case .encodingFailed(let message):
            return "failed to encode request: \(message)"
        case .operationFailed(let message):
            return message
        case .runtimeUnavailable(let message):
            return message
        }
    }
}
