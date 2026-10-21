//===----------------------------------------------------------------------===//
// ComposeMultiFileTests — merging several compose files and profile filtering.
//===----------------------------------------------------------------------===//

import XCTest
import Yams
@testable import ComposeEngine

final class ComposeMultiFileTests: XCTestCase {
    func testOverrideReplacesScalarsAndCommandAndAccumulatesPorts() throws {
        let base: Any = try Yams.load(yaml: """
        services:
          web:
            image: nginx:1
            command: ["serve", "--old"]
            ports: ["8080:80"]
        """) ?? [:]
        let override: Any = try Yams.load(yaml: """
        services:
          web:
            image: nginx:2
            command: ["serve", "--new"]
            ports: ["8080:80", "8443:443"]
        """) ?? [:]
        let merged = ComposeParser.merge(base, override) as? [String: Any]
        let web = (merged?["services"] as? [String: Any])?["web"] as? [String: Any]
        XCTAssertEqual(web?["image"] as? String, "nginx:2")
        XCTAssertEqual(web?["command"] as? [String], ["serve", "--new"])
        XCTAssertEqual(web?["ports"] as? [String], ["8080:80", "8443:443"])
    }

    func testProfilesOnlyEnableMatchingServices() throws {
        let yaml = """
        services:
          app:
            image: alpine
          debugger:
            image: alpine
            profiles: ["debug"]
        """
        let without = try ComposeParser().parse(yaml: yaml, profiles: [])
        XCTAssertEqual(Set(without.services.keys), ["app"])

        let withDebug = try ComposeParser().parse(yaml: yaml, profiles: ["debug"])
        XCTAssertEqual(Set(withDebug.services.keys), ["app", "debugger"])
    }

    func testParseFilesMergesInOrder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-multi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = dir.appendingPathComponent("compose.yaml")
        let override = dir.appendingPathComponent("compose.override.yaml")
        try """
        services:
          web:
            image: nginx:1
        """.write(to: base, atomically: true, encoding: .utf8)
        try """
        services:
          web:
            image: nginx:2
        """.write(to: override, atomically: true, encoding: .utf8)

        let project = try ComposeParser().parse(files: [base.path, override.path])
        XCTAssertEqual(project.services["web"]?.image, "nginx:2")
    }
}

final class ComposeReplicaTests: XCTestCase {
    func testReplicaNamesAndCustomNameOnReplicaOne() {
        XCTAssertEqual(ComposeOrchestrator.replicaName(project: "shop", service: "web", replica: 1), "shop-web-1")
        XCTAssertEqual(ComposeOrchestrator.replicaName(project: "shop", service: "web", replica: 3), "shop-web-3")

        var custom = ServiceConfig(image: "nginx")
        custom.containerName = "frontend"
        XCTAssertEqual(ComposeOrchestrator.replicaName(project: "shop", service: "web", config: custom, replica: 1), "frontend")
    }

    func testReplicaCountPrefersScaleOverride() throws {
        let project = try ComposeParser().parse(yaml: """
        services:
          web:
            image: nginx
            scale: 2
          db:
            image: postgres
        """)
        XCTAssertEqual(ComposeOrchestrator.replicaCount(for: "web", in: project, scales: [:]), 2)
        XCTAssertEqual(ComposeOrchestrator.replicaCount(for: "web", in: project, scales: ["web": 4]), 4)
        XCTAssertEqual(ComposeOrchestrator.replicaCount(for: "db", in: project, scales: [:]), 1)
        XCTAssertEqual(ComposeOrchestrator.replicaCount(for: "db", in: project, scales: ["db": 0]), 1)
    }
}
