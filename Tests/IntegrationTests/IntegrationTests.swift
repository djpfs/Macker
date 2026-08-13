//===----------------------------------------------------------------------===//
// IntegrationTests — exercises against a real container-apiserver.
//
// These tests require the apple/container runtime to be installed and running.
// They are skipped unless the `APPLE_CONTAINER_RUNTIME` environment variable is
// set to a truthy value (see the Makefile `test-integration` target).
//===----------------------------------------------------------------------===//

import XCTest
@testable import ContainerBackend

final class IntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        guard Self.runtimeAvailable() else {
            throw XCTSkip("container runtime not available (set APPLE_CONTAINER_RUNTIME=1)")
        }
    }

    private static func runtimeAvailable() -> Bool {
        let env = ProcessInfo.processInfo.environment["APPLE_CONTAINER_RUNTIME"]
        return env == "1" || env == "true"
    }

    func testPing() async throws {
        let client = ContainerAPIClient()
        let health = try await client.ping(timeout: .seconds(10))
        XCTAssertFalse(health.appRoot.isEmpty)
        XCTAssertFalse(health.apiServerVersion.isEmpty)
        client.close()
    }

    func testNetworkList() async throws {
        let client = ContainerAPIClient()
        let networks = try await client.networkList()
        XCTAssertTrue(networks.contains { $0.name == ContainerAPIClient.defaultNetworkName })
        client.close()
    }
}
