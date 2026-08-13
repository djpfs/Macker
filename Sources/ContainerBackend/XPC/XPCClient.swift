//===----------------------------------------------------------------------===//
// XPCClient — a reusable XPC connection to a Mach service.
//
// This is a lightweight reimplementation of apple/container's ContainerXPC
// client: it connects to the named service, sends route-keyed XPCMessages with
// a configurable timeout, and surfaces XPC errors as BackendError.
//===----------------------------------------------------------------------===//

import Foundation

public final class XPCClient: @unchecked Sendable {
    /// The maximum amount of time to wait for a request to a recently
    /// registered XPC service. Once a service has launched, requests take only
    /// milliseconds, but macOS can take several seconds to launch a service
    /// after it has been registered.
    public static let registrationTimeout: Duration = .seconds(60)

    private nonisolated(unsafe) let connection: xpc_connection_t
    private let service: String

    public init(service: String, queue: DispatchQueue? = nil) {
        let connection = xpc_connection_create_mach_service(service, queue, 0)
        self.connection = connection
        self.service = service

        xpc_connection_set_event_handler(connection) { _ in }
        xpc_connection_set_target_queue(connection, queue)
        xpc_connection_activate(connection)
    }

    deinit {
        xpc_connection_cancel(connection)
    }

    /// Close the underlying XPC connection.
    public func close() {
        xpc_connection_cancel(connection)
    }

    /// Install a handler that is called whenever the connection receives an
    /// XPC error event (e.g. the service crashed or was stopped).
    public func setDisconnectHandler(_ handler: @escaping @Sendable () -> Void) {
        xpc_connection_set_event_handler(connection) { object in
            if xpc_get_type(object) == XPC_TYPE_ERROR {
                handler()
            }
        }
    }

    /// Send a message to the service and await the reply.
    @discardableResult
    public func send(
        _ message: XPCMessage,
        responseTimeout: Duration? = XPCClient.registrationTimeout
    ) async throws -> XPCMessage {
        try await withThrowingTaskGroup(of: XPCMessage.self, returning: XPCMessage.self) { group in
            if let responseTimeout {
                group.addTask {
                    try await Task.sleep(for: responseTimeout)
                    let route = message.string(key: XPCMessage.routeKey) ?? "nil"
                    throw BackendError.timeout(route: "\(self.service)/\(route)")
                }
            }

            group.addTask {
                try await withCheckedThrowingContinuation { cont in
                    xpc_connection_send_message_with_reply(self.connection, message.underlying, nil) { reply in
                        do {
                            cont.resume(returning: try self.parseReply(reply))
                        } catch {
                            cont.resume(throwing: error)
                        }
                    }
                }
            }

            let response = try await group.next()
            group.cancelAll()
            try? await group.waitForAll()

            guard let response else {
                throw BackendError.invalidResponse("failed to receive XPC response")
            }
            return response
        }
    }

    private func parseReply(_ reply: xpc_object_t) throws -> XPCMessage {
        switch xpc_get_type(reply) {
        case XPC_TYPE_ERROR:
            if xpc_equal(reply, XPC_ERROR_CONNECTION_INTERRUPTED) {
                throw BackendError.connectionInterrupted
            }
            let description: String = {
                guard let value = xpc_dictionary_get_string(reply, XPC_ERROR_KEY_DESCRIPTION) else {
                    return "unknown XPC error"
                }
                return String(cString: value)
            }()
            throw BackendError.operationFailed(description)
        case XPC_TYPE_DICTIONARY:
            let message = XPCMessage(object: reply)
            // Surface protocol-level errors reported by the apiserver.
            if let errorData = message.data(key: XPCMessage.errorKey),
               let decoded = try? JSONDecoder().decode(ContainerXPCError.self, from: errorData) {
                throw BackendError.protocolError(code: decoded.code, message: decoded.message)
            }
            return message
        default:
            throw BackendError.invalidResponse("unexpected XPC object type")
        }
    }
}
