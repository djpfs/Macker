//===----------------------------------------------------------------------===//
// RuntimeVersionTests — CLI version parsing, ordering, and release payloads.
//===----------------------------------------------------------------------===//

import XCTest
@testable import ContainerBackend

final class RuntimeVersionTests: XCTestCase {
    func testParsesCLIVersionOutput() {
        XCTAssertEqual(
            RuntimeVersion.parseVersion("container CLI version 1.2.2 (build: release, commit: 0190097)"),
            "1.2.2"
        )
        XCTAssertNil(RuntimeVersion.parseVersion("command not found: container"))
    }

    func testOrdersVersionsNumerically() {
        XCTAssertTrue(RuntimeVersion.isOlder("1.2.2", than: "1.6.0"))
        XCTAssertTrue(RuntimeVersion.isOlder("1.9.0", than: "1.10.0"))
        XCTAssertFalse(RuntimeVersion.isOlder("1.6.0", than: "1.6.0"))
        XCTAssertFalse(RuntimeVersion.isOlder("1.6.1", than: "1.6.0"))
        XCTAssertTrue(RuntimeVersion.isOlder("1.6", than: "1.6.1"))
    }

    func testParsesInstallerAssetAndDigest() throws {
        let json = """
        {
          "tag_name": "1.6.0",
          "assets": [
            {
              "name": "container-dSYM.zip",
              "browser_download_url": "https://example.com/dsym.zip",
              "digest": "sha256:0000"
            },
            {
              "name": "container-1.6.0-installer-signed.pkg",
              "browser_download_url": "https://example.com/installer.pkg",
              "digest": "sha256:a084d66df2fb573172d7f923fa83c9229d17f6c1ab61f09c8a90c43dab66ba02"
            }
          ]
        }
        """
        let release = try RuntimeVersion.parseRelease(Data(json.utf8), requestedTag: "1.6.0")
        XCTAssertEqual(release.tag, "1.6.0")
        XCTAssertEqual(release.installerName, "container-1.6.0-installer-signed.pkg")
        XCTAssertEqual(release.installerURL.absoluteString, "https://example.com/installer.pkg")
        XCTAssertEqual(release.sha256, "a084d66df2fb573172d7f923fa83c9229d17f6c1ab61f09c8a90c43dab66ba02")
    }

    func testReleaseWithoutSignedInstallerThrows() {
        let json = #"{"tag_name":"1.0.0","assets":[{"name":"container-installer-unsigned.pkg","browser_download_url":"https://example.com/u.pkg","digest":null}]}"#
        XCTAssertThrowsError(try RuntimeVersion.parseRelease(Data(json.utf8), requestedTag: nil)) { error in
            XCTAssertEqual(error as? RuntimeVersion.Failure, .installerNotFound("1.0.0"))
        }
    }
}

final class LaunchdStatusParsingTests: XCTestCase {
    func testRunningPayloadMapsToRunning() {
        let json = #"{"status":"running","client":{"version":"1.6.0"}}"#
        XCTAssertEqual(LaunchdManager.parseStatus(json, fallback: ""), .running)
    }

    func testDownPayloadsMapToStopped() {
        XCTAssertEqual(LaunchdManager.parseStatus(#"{"status":"not running"}"#, fallback: ""), .stopped)
        XCTAssertEqual(LaunchdManager.parseStatus(#"{"status":"unregistered"}"#, fallback: ""), .stopped)
    }

    func testUnknownStatusIsReportedVerbatim() {
        XCTAssertEqual(LaunchdManager.parseStatus(#"{"status":"starting"}"#, fallback: ""), .unknown("starting"))
    }

    func testUnreadableOutputUsesStderrAsReason() {
        XCTAssertEqual(LaunchdManager.parseStatus("not json", fallback: " boom \n"), .unknown("boom"))
        XCTAssertEqual(LaunchdManager.parseStatus("", fallback: ""), .unknown("unreadable system status output"))
    }
}

final class AttachmentAliasCodingTests: XCTestCase {
    func testAliasesOmittedFromJSONWhenEmpty() throws {
        let data = try JSONEncoder().encode(AttachmentOptions(hostname: "web", mtu: 1280))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("aliases"))
    }

    func testAliasesRoundTrip() throws {
        let original = AttachmentOptions(hostname: "web", mtu: 1280, aliases: ["api", "web-api"])
        let decoded = try JSONDecoder().decode(AttachmentOptions.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.aliases, ["api", "web-api"])
        XCTAssertEqual(decoded.hostname, "web")
    }

    func testLegacyConfigWithoutAliasesDecodes() throws {
        let legacy = #"{"hostname":"web","mtu":1280}"#
        let decoded = try JSONDecoder().decode(AttachmentOptions.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.aliases, [])
    }
}
