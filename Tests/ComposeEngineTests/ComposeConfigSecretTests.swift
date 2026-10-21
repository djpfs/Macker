//===----------------------------------------------------------------------===//
// ComposeConfigSecretTests — config and secret references and their mounts.
//===----------------------------------------------------------------------===//

import XCTest
@testable import ComposeEngine

final class ComposeConfigSecretTests: XCTestCase {
    func testShortAndLongReferenceForms() throws {
        let project = try ComposeParser().parse(yaml: """
        configs:
          app_conf:
            file: ./app.conf
        secrets:
          db_pass:
            file: ./db_pass.txt
        services:
          web:
            image: nginx
            configs:
              - app_conf
              - source: app_conf
                target: /etc/nginx/extra.conf
                mode: 0440
            secrets:
              - db_pass
        """, baseDirectory: "/tmp/project")

        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.configs[0], ServiceFileRef(source: "app_conf"))
        XCTAssertEqual(web.configs[1], ServiceFileRef(source: "app_conf", target: "/etc/nginx/extra.conf", mode: "0440"))
        XCTAssertEqual(web.secrets, [ServiceFileRef(source: "db_pass")])
    }

    func testReferenceWithoutFileIsRejected() {
        XCTAssertThrowsError(
            try ComposeOrchestrator.fileRefMounts(
                [ServiceFileRef(source: "remote")],
                files: [:],
                defaultDirectory: "",
                serviceName: "web",
                project: ComposeProject(name: "p", services: [:]),
                filePath: "/tmp/p/compose.yaml"
            )
        ) { error in
            XCTAssertEqual(error as? ComposeParseError, .configWithoutFile("web", "remote"))
        }
    }

    func testFileBackedReferenceProducesAMount() throws {
        let mounts = try ComposeOrchestrator.fileRefMounts(
            [ServiceFileRef(source: "db_pass")],
            files: ["db_pass": "./db_pass.txt"],
            defaultDirectory: "/run/secrets",
            serviceName: "web",
            project: ComposeProject(name: "p", services: [:]),
            filePath: "/tmp/p/compose.yaml"
        )
        XCTAssertEqual(mounts.count, 1)
    }
}
