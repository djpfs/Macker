//===----------------------------------------------------------------------===//
// ComposeHealthcheckTests — healthcheck forms: list, string, disable, NONE.
//===----------------------------------------------------------------------===//

import XCTest
@testable import ComposeEngine

final class ComposeHealthcheckTests: XCTestCase {
    private func healthcheck(_ block: String) throws -> HealthCheckConfig? {
        let project = try ComposeParser().parse(yaml: """
        services:
          web:
            image: nginx
        \(block)
        """)
        return project.services["web"]?.healthcheck
    }

    func testListFormTestIsKept() throws {
        let hc = try healthcheck("""
            healthcheck:
              test: ["CMD", "curl", "-f", "http://localhost"]
              interval: 10s
        """)
        XCTAssertEqual(hc?.test, ["CMD", "curl", "-f", "http://localhost"])
        XCTAssertFalse(hc?.isDisabled ?? true)
    }

    func testDisableTrueIsDisabled() throws {
        let hc = try healthcheck("""
            healthcheck:
              disable: true
        """)
        XCTAssertEqual(hc?.isDisabled, true)
    }

    func testTestNoneIsDisabled() throws {
        let hc = try healthcheck("""
            healthcheck:
              test: ["NONE"]
        """)
        XCTAssertEqual(hc?.isDisabled, true)
    }
}
