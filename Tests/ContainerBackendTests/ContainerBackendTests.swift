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
        let decoded: NetworkConfiguration = try message.decodeJSON(NetworkConfiguration.self, key: .networkConfig)
        XCTAssertEqual(decoded.name, "bridge")
        XCTAssertEqual(decoded.plugin, "vmnet")
    }
}

final class SecurityHardeningTests: XCTestCase {
    func testResolveEnvironmentFromKeychainReference() throws {
        let resolved = try KeychainSecretStore.resolveEnvironment(
            ["TOKEN=keychain://my-token", "PLAIN=value"],
            lookup: { name in
                XCTAssertEqual(name, "my-token")
                return "super-secret"
            }
        )
        XCTAssertEqual(resolved, ["TOKEN=super-secret", "PLAIN=value"])
    }

    func testResolveEnvironmentThrowsWhenSecretMissing() {
        XCTAssertThrowsError(
            try KeychainSecretStore.resolveEnvironment(["TOKEN=keychain://missing"], lookup: { _ in nil })
        ) { error in
            guard case BackendError.notFound(let message) = error else {
                return XCTFail("expected notFound, got \(error)")
            }
            XCTAssertEqual(message, "secret missing")
        }
    }

    func testParseTrivyReport() throws {
        let json = """
        {
          "Results": [
            {
              "Vulnerabilities": [
                {
                  "VulnerabilityID": "CVE-1",
                  "PkgName": "openssl",
                  "InstalledVersion": "1.0.0",
                  "FixedVersion": "1.0.1",
                  "Title": "Demo vuln",
                  "Severity": "HIGH",
                  "PrimaryURL": "https://example.com/CVE-1"
                },
                {
                  "VulnerabilityID": "CVE-2",
                  "PkgName": "zlib",
                  "Severity": "LOW"
                }
              ]
            }
          ]
        }
        """
        let report = try VulnerabilityScanner.parseTrivyReport(json, imageReference: "demo:latest")
        XCTAssertEqual(report.imageReference, "demo:latest")
        XCTAssertEqual(report.findings.count, 2)
        XCTAssertEqual(report.totalBySeverity["HIGH"], 1)
        XCTAssertEqual(report.totalBySeverity["LOW"], 1)
    }

    func testContainerConfigurationDefaultsSecurityFields() throws {
        let image = ImageDescription(
            reference: "nginx:latest",
            descriptor: Descriptor(
                mediaType: "application/vnd.oci.image.manifest.v1+json",
                digest: "sha256:abc",
                size: 123
            )
        )
        let original = ContainerConfiguration(
            id: "demo",
            image: image,
            process: .init(executable: "/bin/sh", arguments: [], environment: [])
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        object.removeValue(forKey: "privileged")
        object.removeValue(forKey: "securityOptions")
        let data = try JSONSerialization.data(withJSONObject: object)
        let config = try JSONDecoder().decode(ContainerConfiguration.self, from: data)
        XCTAssertFalse(config.privileged)
        XCTAssertEqual(config.securityOptions, [])
    }
}
