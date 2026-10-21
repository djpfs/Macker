//===----------------------------------------------------------------------===//
// MigrationTests — `macker migrate` arguments and source sockets.
//===----------------------------------------------------------------------===//

import XCTest
@testable import AppleDockerCLI

final class MigrationTests: XCTestCase {
    func testParsesSourceAndDryRun() throws {
        let command = try MigrateCommand.parse(["--from", "colima", "--dry-run"])
        XCTAssertEqual(command.from, .colima)
        XCTAssertTrue(command.dryRun)
    }

    func testRejectsUnknownSource() {
        XCTAssertThrowsError(try MigrateCommand.parse(["--from", "podman"]))
    }

    func testEveryMigrationSourceHasASocketCandidate() {
        for source in MigrationSource.allCases {
            XCTAssertFalse(source.sockets.isEmpty, "\(source.rawValue) has no socket path")
            XCTAssertTrue(source.sockets.allSatisfy { $0.hasPrefix(NSHomeDirectory()) })
        }
    }
}
