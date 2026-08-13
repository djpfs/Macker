//===----------------------------------------------------------------------===//
// XPCMessage — a thin, type-safe wrapper over the C XPC dictionary API.
//
// The container-apiserver protocol is a route-keyed XPC dictionary: the route
// is stored under "com.apple.container.xpc.route" and errors under
// "com.apple.container.xpc.error". This mirrors the wire format used by
// apple/container's own ContainerXPC module.
//===----------------------------------------------------------------------===//

import Foundation

/// A message that can be passed across application boundaries via XPC.
public struct XPCMessage: @unchecked Sendable {
    /// Defined message key storing the route value.
    public static let routeKey = "com.apple.container.xpc.route"
    /// Defined message key storing the error value.
    public static let errorKey = "com.apple.container.xpc.error"

    // Access to `object` is protected by a lock.
    private nonisolated(unsafe) let object: xpc_object_t
    private let lock = NSLock()
    private let isErr: Bool

    /// The underlying xpc object that the message wraps.
    public var underlying: xpc_object_t {
        lock.withLock { object }
    }

    public var isErrorType: Bool { isErr }

    public init(object: xpc_object_t) {
        self.object = object
        self.isErr = xpc_get_type(self.object) == XPC_TYPE_ERROR
    }

    public init(route: String) {
        self.object = xpc_dictionary_create_empty()
        self.isErr = false
        xpc_dictionary_set_string(self.object, Self.routeKey, route)
    }

    /// Build a reply message from this request.
    public func reply() -> XPCMessage? {
        lock.withLock {
            guard let reply = xpc_dictionary_create_reply(object) else { return nil }
            return XPCMessage(object: reply)
        }
    }

    /// The XPC error description, if this message wraps an XPC_TYPE_ERROR.
    public func errorKeyDescription() -> String? {
        guard isErr else { return nil }
        return lock.withLock {
            guard let xpcErr = xpc_dictionary_get_string(object, XPC_ERROR_KEY_DESCRIPTION) else { return nil }
            return String(cString: xpcErr)
        }
    }
}

// MARK: - Typed accessors

extension XPCMessage {
    public func data(key: String) -> Data? {
        var length: Int = 0
        let bytes = lock.withLock {
            xpc_dictionary_get_data(self.object, key, &length)
        }
        guard let bytes else { return nil }
        return Data(bytes: bytes, count: length)
    }

    public func set(key: String, value: Data) {
        value.withUnsafeBytes { ptr in
            if let addr = ptr.baseAddress {
                lock.withLock {
                    xpc_dictionary_set_data(self.object, key, addr, value.count)
                }
            }
        }
    }

    public func string(key: String) -> String? {
        lock.withLock {
            guard let value = xpc_dictionary_get_string(self.object, key) else { return nil }
            return String(cString: value)
        }
    }

    public func set(key: String, value: String) {
        lock.withLock {
            xpc_dictionary_set_string(self.object, key, value)
        }
    }

    public func bool(key: String) -> Bool {
        lock.withLock { xpc_dictionary_get_bool(self.object, key) }
    }

    public func set(key: String, value: Bool) {
        lock.withLock { xpc_dictionary_set_bool(self.object, key, value) }
    }

    public func uint64(key: String) -> UInt64 {
        lock.withLock { xpc_dictionary_get_uint64(self.object, key) }
    }

    public func set(key: String, value: UInt64) {
        lock.withLock { xpc_dictionary_set_uint64(self.object, key, value) }
    }

    public func int64(key: String) -> Int64 {
        lock.withLock { xpc_dictionary_get_int64(self.object, key) }
    }

    public func set(key: String, value: Int64) {
        lock.withLock { xpc_dictionary_set_int64(self.object, key, value) }
    }

    public func date(key: String) -> Date? {
        lock.withLock {
            let nsSinceEpoch = xpc_dictionary_get_date(self.object, key)
            guard nsSinceEpoch != 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(nsSinceEpoch) / 1_000_000_000)
        }
    }

    public func set(key: String, value: Date) {
        lock.withLock {
            let nsSinceEpoch = Int64(value.timeIntervalSince1970 * 1_000_000_000)
            xpc_dictionary_set_date(self.object, key, nsSinceEpoch)
        }
    }

    public func fileHandle(key: String) -> FileHandle? {
        lock.withLock {
            guard let value = xpc_dictionary_get_value(self.object, key) else { return nil }
            let fd = xpc_fd_dup(value)
            guard fd >= 0 else { return nil }
            return FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        }
    }

    public func set(key: String, value: FileHandle) {
        // xpc_fd_create duplicates the fd, so the caller keeps ownership of the
        // handle. We must NOT close it here: the same handle may be passed for
        // multiple channels (e.g. stdout and stderr), and closing it would make
        // a later access to `fileDescriptor` throw an ObjC exception.
        if let fd = xpc_fd_create(value.fileDescriptor) {
            lock.withLock {
                xpc_dictionary_set_value(self.object, key, fd)
            }
        }
    }

    public func fileHandles(key: String) -> [FileHandle]? {
        lock.withLock {
            guard let value = xpc_dictionary_get_value(self.object, key) else { return nil }
            var handles: [FileHandle] = []
            let count = xpc_array_get_count(value)
            guard count > 0 else { return nil }
            for index in 0..<count {
                let fd = xpc_array_dup_fd(value, index)
                guard fd >= 0 else { continue }
                handles.append(FileHandle(fileDescriptor: fd, closeOnDealloc: false))
            }
            return handles.isEmpty ? nil : handles
        }
    }

    public func set(key: String, value: [FileHandle]) {
        let fdArray = xpc_array_create(nil, 0)
        for fh in value {
            if let xpcFd = xpc_fd_create(fh.fileDescriptor) {
                xpc_array_append_value(fdArray, xpcFd)
            }
        }
        lock.withLock {
            xpc_dictionary_set_value(self.object, key, fdArray)
        }
    }
}

// MARK: - Protocol error payload

/// Error payload exchanged by the apiserver when a request fails at the
/// protocol level.
struct ContainerXPCError: Codable {
    let code: String
    let message: String
}

// MARK: - Helpers

extension XPCMessage {
    /// Decode a JSON payload into a typed value.
    public func decodeJSON<T: Decodable>(_ type: T.Type, key: String) throws -> T {
        guard let data = data(key: key) else {
            throw BackendError.invalidResponse("missing expected payload for key '\(key)'")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw BackendError.invalidResponse("failed to decode payload for key '\(key)': \(error)")
        }
    }

    /// Encode a value as JSON and set it on the message.
    public func setJSON<T: Encodable>(_ value: T, key: String) throws {
        do {
            let data = try JSONEncoder().encode(value)
            set(key: key, value: data)
        } catch {
            throw BackendError.encodingFailed("failed to encode payload for key '\(key)': \(error)")
        }
    }
}
