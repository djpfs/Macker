//===----------------------------------------------------------------------===//
// ContainerBackendTests — model serialization round-trips and XPC helpers.
//===----------------------------------------------------------------------===//

import XCTest
@testable import ContainerBackend

final class KernelModelTests: XCTestCase {
    func testKernelRoundTrip() throws {
        let kernel = Kernel(
            path: URL(fileURLWithPath: "/usr/local/share/apple/container/kernel"),
            platform: .linuxArm,
            commandLine: .init(
                kernelArgs: Kernel.CommandLine.kernelDefaults + ["console=ttyS0"],
                initArgs: ["/sbin/init"]
            )
        )
        let data = try JSONEncoder().encode(kernel)
        let decoded = try JSONDecoder().decode(Kernel.self, from: data)
        XCTAssertEqual(decoded, kernel)
        XCTAssertEqual(decoded.path.path, "/usr/local/share/apple/container/kernel")
        XCTAssertEqual(decoded.platform.os, .linux)
        XCTAssertEqual(decoded.platform.architecture, .arm64)
        XCTAssertEqual(decoded.kernelArgs, Kernel.CommandLine.kernelDefaults + ["console=ttyS0"])
        XCTAssertEqual(decoded.initArgs, ["/sbin/init"])
    }

    func testSystemPlatformJSONKeyNames() throws {
        // The daemon expects `os` and `architecture` — key names must not drift.
        let platform = SystemPlatform.linuxArm
        let data = try JSONEncoder().encode(platform)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object["os"], "linux")
        XCTAssertEqual(object["architecture"], "arm64")
    }

    func testPlatformDescription() {
        XCTAssertEqual(SystemPlatform.linuxAmd.ociPlatform.description, "linux/amd64")
    }
}

final class XPCMessageTests: XCTestCase {
    func testSetAndGetData() throws {
        let message = XPCMessage(route: .ping)
        let payload = Data("hello".utf8)
        message.set(key: .kernel, value: payload)
        XCTAssertEqual(message.data(key: .kernel), payload)
        XCTAssertNil(message.data(key: .fd))
    }

    func testSetAndGetString() {
        let message = XPCMessage(route: .containerList)
        message.set(key: .id, value: "abc")
        XCTAssertEqual(message.string(key: .id), "abc")
    }

    func testSetAndGetBool() {
        let message = XPCMessage(route: .containerDelete)
        message.set(key: .forceDelete, value: true)
        XCTAssertTrue(message.bool(key: .forceDelete))
    }

    func testJSONRoundTrip() throws {
        let message = XPCMessage(route: .networkCreate)
        let config = NetworkConfiguration(name: "bridge", plugin: "vmnet")
        try message.setJSON(config, key: .networkConfig)
        let decoded: NetworkConfiguration = try message.decodeJSON(.networkConfig)
        XCTAssertEqual(decoded.name, "bridge")
        XCTAssertEqual(decoded.plugin, "vmnet")
    }
}
