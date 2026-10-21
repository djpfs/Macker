import XCTest
@testable import AppleDockerCLI

final class DockerShimTests: XCTestCase {
    // MARK: - Boolean flags must not consume the next token

    func testRunRmDoesNotConsumeImage() throws {
        let cmd = try DockerCommandParser.parse(["run", "--rm", "node:22-alpine", "echo", "hi"])
        XCTAssertEqual(cmd.subcommand, "run")
        XCTAssertTrue(cmd.has("rm"))
        XCTAssertEqual(cmd.arguments, ["node:22-alpine", "echo", "hi"])
    }

    func testRunDetachShortFlag() throws {
        let cmd = try DockerCommandParser.parse(["run", "-d", "--name", "web", "nginx"])
        XCTAssertTrue(cmd.has("d"))
        XCTAssertEqual(cmd.value("name"), "web")
        XCTAssertEqual(cmd.arguments, ["nginx"])
    }

    func testRunPublishAllIsBoolean() throws {
        let cmd = try DockerCommandParser.parse(["run", "-d", "-P", "nginx"])
        XCTAssertTrue(cmd.has("P"))
        XCTAssertEqual(cmd.arguments, ["nginx"])
    }

    // MARK: - Command passthrough after the image

    func testRunPassthroughAfterImage() throws {
        let cmd = try DockerCommandParser.parse(["run", "--rm", "node:22-alpine", "sh", "-c", "echo hi; exit 3"])
        XCTAssertEqual(cmd.arguments, ["node:22-alpine", "sh", "-c", "echo hi; exit 3"])
    }

    func testExecPassthroughAfterContainer() throws {
        let cmd = try DockerCommandParser.parse(["exec", "web", "sh", "-c", "ls -la"])
        XCTAssertEqual(cmd.arguments, ["web", "sh", "-c", "ls -la"])
    }

    // MARK: - Ambiguous short flags are resolved per subcommand

    func testRmForceIsBoolean() throws {
        let cmd = try DockerCommandParser.parse(["rm", "-f", "web"])
        XCTAssertTrue(cmd.has("f"))
        XCTAssertEqual(cmd.arguments, ["web"])
    }

    func testLogsFollowIsBoolean() throws {
        let cmd = try DockerCommandParser.parse(["logs", "-f", "web"])
        XCTAssertTrue(cmd.has("f"))
        XCTAssertEqual(cmd.arguments, ["web"])
    }

    func testPsFilterTakesValue() throws {
        let cmd = try DockerCommandParser.parse(["ps", "-f", "name=web"])
        XCTAssertEqual(cmd.value("f"), "name=web")
        XCTAssertTrue(cmd.arguments.isEmpty)
    }

    // MARK: - Value flags

    func testRunPublishValue() throws {
        let cmd = try DockerCommandParser.parse(["run", "-p", "8080:80", "nginx"])
        XCTAssertEqual(cmd.value("p"), "8080:80")
        XCTAssertEqual(cmd.arguments, ["nginx"])
    }

    func testRunInlineValue() throws {
        let cmd = try DockerCommandParser.parse(["run", "--name=web", "nginx"])
        XCTAssertEqual(cmd.value("name"), "web")
        XCTAssertEqual(cmd.arguments, ["nginx"])
    }

    func testRunEnvValue() throws {
        let cmd = try DockerCommandParser.parse(["run", "-e", "FOO=bar", "nginx"])
        XCTAssertEqual(cmd.value("e"), "FOO=bar")
        XCTAssertEqual(cmd.arguments, ["nginx"])
    }

    // MARK: - Grouped commands

    func testComposeUp() throws {
        let cmd = try DockerCommandParser.parse(["compose", "up", "-d"])
        XCTAssertEqual(cmd.subcommand, "compose")
        XCTAssertEqual(cmd.subSubcommand, "up")
        XCTAssertTrue(cmd.has("d"))
    }

    func testComposeFileFlagBeforeSubcommand() throws {
        // `compose -f file.yml up` — the -f flag precedes the sub-subcommand
        // and must be preserved, not discarded.
        let cmd = try DockerCommandParser.parse(["compose", "-f", "docker-compose.yml", "up", "-d"])
        XCTAssertEqual(cmd.subSubcommand, "up")
        XCTAssertEqual(cmd.value("f"), "docker-compose.yml")
        XCTAssertTrue(cmd.has("d"))
    }

    func testNetworkLs() throws {
        let cmd = try DockerCommandParser.parse(["network", "ls"])
        XCTAssertEqual(cmd.subcommand, "network")
        XCTAssertEqual(cmd.subSubcommand, "ls")
    }

    func testImagePull() throws {
        let cmd = try DockerCommandParser.parse(["image", "pull", "nginx"])
        XCTAssertEqual(cmd.subcommand, "image")
        XCTAssertEqual(cmd.subSubcommand, "pull")
        XCTAssertEqual(cmd.arguments, ["nginx"])
    }

    func testSecretCreateCommand() throws {
        let cmd = try DockerCommandParser.parse(["secret", "create", "db-pass", "-"])
        XCTAssertEqual(cmd.subcommand, "secret")
        XCTAssertEqual(cmd.subSubcommand, "create")
        XCTAssertEqual(cmd.arguments, ["db-pass", "-"])
    }

    func testScanCommandWithSeverity() throws {
        let cmd = try DockerCommandParser.parse(["scan", "--severity", "HIGH,CRITICAL", "nginx:latest"])
        XCTAssertEqual(cmd.subcommand, "scan")
        XCTAssertEqual(cmd.value("severity"), "HIGH,CRITICAL")
        XCTAssertEqual(cmd.arguments, ["nginx:latest"])
    }

    // MARK: - Positional separator

    func testDoubleDashSeparator() throws {
        // After the image, `--` is part of the command (docker passes it through).
        let cmd = try DockerCommandParser.parse(["run", "nginx", "--", "echo", "--version"])
        XCTAssertEqual(cmd.arguments, ["nginx", "--", "echo", "--version"])
    }

    // MARK: - Errors

    func testMissingSubcommand() {
        XCTAssertThrowsError(try DockerCommandParser.parse([])) { error in
            guard case DockerShimError.missingSubcommand = error else {
                return XCTFail("expected missingSubcommand, got \(error)")
            }
        }
    }
}
