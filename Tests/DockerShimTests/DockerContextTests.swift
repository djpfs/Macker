//===----------------------------------------------------------------------===//
// DockerContextTests — context store, --context extraction, endpoint checks.
//===----------------------------------------------------------------------===//

import XCTest
@testable import AppleDockerCLI

final class DockerContextTests: XCTestCase {
    private func temporaryStore() -> DockerContextStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("contexts-\(UUID().uuidString).json")
        return DockerContextStore(url: url)
    }

    func testDefaultIsAlwaysListedAndCurrent() {
        let store = temporaryStore()
        XCTAssertEqual(store.list().map(\.name), ["default"])
        XCTAssertEqual(store.current().name, "default")
        XCTAssertNil(store.current().endpoint)
    }

    func testCreateUseAndRemove() throws {
        let store = temporaryStore()
        try store.create(name: "colima", endpoint: "unix:///tmp/colima.sock", description: "Colima VM")
        try store.use("colima")
        XCTAssertEqual(store.current().endpoint, "unix:///tmp/colima.sock")

        XCTAssertThrowsError(try store.remove("colima")) { error in
            XCTAssertEqual(error as? DockerContextError, .contextInUse("colima"))
        }
        try store.use("default")
        try store.remove("colima")
        XCTAssertEqual(store.list().map(\.name), ["default"])
    }

    func testDefaultCannotBeRemovedOrDuplicated() throws {
        let store = temporaryStore()
        XCTAssertThrowsError(try store.remove("default")) { error in
            XCTAssertEqual(error as? DockerContextError, .cannotRemoveDefault)
        }
        XCTAssertThrowsError(try store.create(name: "default", endpoint: nil, description: ""))
    }

    func testRejectsUnsupportedEndpoint() {
        let store = temporaryStore()
        XCTAssertThrowsError(try store.create(name: "bad", endpoint: "http://x", description: "")) { error in
            XCTAssertEqual(error as? DockerContextError, .invalidEndpoint("http://x"))
        }
    }

    func testExtractsContextFlagFromAnywhere() {
        let one = DockerForwarder.extractContext(["--context", "colima", "ps", "-a"])
        XCTAssertEqual(one.name, "colima")
        XCTAssertEqual(one.args, ["ps", "-a"])

        let two = DockerForwarder.extractContext(["ps", "--context=orbstack"])
        XCTAssertEqual(two.name, "orbstack")
        XCTAssertEqual(two.args, ["ps"])

        let none = DockerForwarder.extractContext(["images"])
        XCTAssertNil(none.name)
        XCTAssertEqual(none.args, ["images"])
    }

    func testHostOptionIsExtracted() {
        XCTAssertEqual(DockerContextCommand.hostValue("host=unix:///tmp/d.sock"), "unix:///tmp/d.sock")
        XCTAssertNil(DockerContextCommand.hostValue("other=1"))
    }
}
