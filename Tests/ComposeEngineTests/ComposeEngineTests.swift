import XCTest
@testable import ComposeEngine

final class ComposeEngineTests: XCTestCase {
    // MARK: - Parser: basic structure

    func testParseSimpleProject() throws {
        let yaml = """
        name: myapp
        services:
          web:
            image: nginx:latest
            ports:
              - "8080:80"
            environment:
              FOO: bar
        """
        let project = try ComposeParser().parse(yaml: yaml)
        XCTAssertEqual(project.name, "myapp")
        XCTAssertEqual(project.services.count, 1)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.image, "nginx:latest")
        XCTAssertEqual(web.ports, ["8080:80"])
        XCTAssertEqual(web.environment["FOO"], "bar")
    }

    func testParseProfilesAndServiceAttachments() throws {
        let yaml = """
        secrets:
          db_password:
            file: ./password.txt
        configs:
          app_config:
            file: ./app.conf
        services:
          web:
            image: nginx
            profiles: ["frontend"]
            secrets: [db_password]
            configs: [app_config]
          worker:
            image: alpine
            profiles: ["worker"]
        """
        let project = try ComposeParser().parse(yaml: yaml, profiles: ["frontend"])
        XCTAssertEqual(project.services.count, 1)
        XCTAssertNotNil(project.services["web"])
        XCTAssertEqual(project.services["web"]?.secrets, ["db_password"])
        XCTAssertEqual(project.services["web"]?.configs, ["app_config"])

        let missingSecretYAML = """
        services:
          web:
            image: nginx
            secrets: [missing_secret]
        """
        XCTAssertThrowsError(try ComposeParser().parse(yaml: missingSecretYAML)) { error in
            guard case ComposeParseError.unknownSecret("web", "missing_secret") = error else {
                return XCTFail("expected unknownSecret, got \(error)")
            }
        }

        let missingConfigYAML = """
        services:
          web:
            image: nginx
            configs: [missing_config]
        """
        XCTAssertThrowsError(try ComposeParser().parse(yaml: missingConfigYAML)) { error in
            guard case ComposeParseError.unknownConfig("web", "missing_config") = error else {
                return XCTFail("expected unknownConfig, got \(error)")
            }
        }
    }

    func testUndefinedSecretThrowsError() throws {
        let yaml = """
        services:
          web:
            image: nginx
            secrets: [nonexistent_secret]
        """
        XCTAssertThrowsError(try ComposeParser().parse(yaml: yaml)) { error in
            XCTAssertEqual(error as? ComposeParseError, .unknownSecret("web", "nonexistent_secret"))
        }
    }

    func testUndefinedConfigThrowsError() throws {
        let yaml = """
        services:
          web:
            image: nginx
            configs: [nonexistent_config]
        """
        XCTAssertThrowsError(try ComposeParser().parse(yaml: yaml)) { error in
            XCTAssertEqual(error as? ComposeParseError, .unknownConfig("web", "nonexistent_config"))
        }
    }

    func testParseDefaultsNameToDirectory() throws {
        let yaml = """
        services:
          web:
            image: nginx
        """
        let project = try ComposeParser().parse(yaml: yaml, baseDirectory: "/tmp/my-project")
        XCTAssertEqual(project.name, "my-project")
    }

    // MARK: - Parser: environment list vs map

    func testEnvironmentListNormalizedToMap() throws {
        let yaml = """
        services:
          web:
            image: nginx
            environment:
              - FOO=bar
              - BAZ=qux
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.environment["FOO"], "bar")
        XCTAssertEqual(web.environment["BAZ"], "qux")
    }

    // MARK: - Parser: depends_on list vs map

    func testDependsOnListNormalized() throws {
        let yaml = """
        services:
          web:
            image: nginx
            depends_on:
              - db
          db:
            image: postgres
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.dependsOn["db"], .serviceStarted)
    }

    func testDependsOnMapWithCondition() throws {
        let yaml = """
        services:
          web:
            image: nginx
            depends_on:
              db:
                condition: service_healthy
          db:
            image: postgres
            healthcheck:
              test: ["CMD", "pg_isready"]
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.dependsOn["db"], .serviceHealthy)
    }

    // MARK: - Parser: interpolation

    func testInterpolation() throws {
        let yaml = """
        services:
          web:
            image: nginx:${TAG}
            environment:
              PORT: ${PORT:-8080}
        """
        let project = try ComposeParser().parse(yaml: yaml, env: ["TAG": "1.25"])
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.image, "nginx:1.25")
        XCTAssertEqual(web.environment["PORT"], "8080")
    }

    func testInterpolationDefaultWhenUnset() throws {
        let yaml = """
        services:
          web:
            image: nginx:${TAG:-latest}
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.image, "nginx:latest")
    }

    func testInterpolationDoubleDollarIsLiteral() throws {
        let yaml = """
        services:
          web:
            image: nginx
            command: ["echo", "$$HOME"]
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.command, ["echo", "$HOME"])
    }

    // MARK: - Parser: validation

    func testMissingImageOrBuildThrows() {
        let yaml = """
        services:
          web:
            ports:
              - "8080:80"
        """
        XCTAssertThrowsError(try ComposeParser().parse(yaml: yaml)) { error in
            guard case ComposeParseError.missingImageOrBuild("web") = error else {
                return XCTFail("expected missingImageOrBuild, got \(error)")
            }
        }
    }

    func testUnknownDependencyThrows() {
        let yaml = """
        services:
          web:
            image: nginx
            depends_on:
              - missing
        """
        XCTAssertThrowsError(try ComposeParser().parse(yaml: yaml)) { error in
            guard case ComposeParseError.unknownDependency("web", "missing") = error else {
                return XCTFail("expected unknownDependency, got \(error)")
            }
        }
    }

    // MARK: - ServiceResolver

    func testTopologicalOrder() throws {
        let yaml = """
        services:
          web:
            image: nginx
            depends_on:
              - db
              - cache
          cache:
            image: redis
          db:
            image: postgres
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let order = try ServiceResolver.resolve(project)
        XCTAssertEqual(order, ["cache", "db", "web"])
    }

    func testCircularDependencyThrows() {
        let yaml = """
        services:
          a:
            image: nginx
            depends_on:
              - b
          b:
            image: nginx
            depends_on:
              - a
        """
        XCTAssertThrowsError(try ComposeParser().parse(yaml: yaml)) { error in
            guard case ComposeParseError.circularDependency = error else {
                return XCTFail("expected circularDependency, got \(error)")
            }
        }
    }

    // MARK: - Orchestrator helpers

    func testContainerName() {
        XCTAssertEqual(ComposeOrchestrator.containerName(project: "myapp", service: "web"), "myapp-web-1")
        XCTAssertEqual(ComposeOrchestrator.containerName(project: "My App", service: "Web"), "my-app-web-1")
    }

    func testParsePortSpec() {
        let simple = ComposeOrchestrator.parsePortSpec("8080:80")
        XCTAssertEqual(simple?.hostPort, 8080)
        XCTAssertEqual(simple?.containerPort, 80)

        let bound = ComposeOrchestrator.parsePortSpec("127.0.0.1:8080:80")
        XCTAssertEqual(bound?.hostAddress.rawValue, "127.0.0.1")

        let single = ComposeOrchestrator.parsePortSpec("80")
        XCTAssertEqual(single?.hostPort, 80)
        XCTAssertEqual(single?.containerPort, 80)
    }

    func testParseMemory() {
        XCTAssertEqual(ComposeOrchestrator.parseMemory("512m"), 512 * 1024 * 1024)
        XCTAssertEqual(ComposeOrchestrator.parseMemory("1g"), 1024 * 1024 * 1024)
        XCTAssertEqual(ComposeOrchestrator.parseMemory("256"), 256)
    }

    func testParseDuration() {
        XCTAssertEqual(ComposeOrchestrator.parseDuration("30s"), 30)
        XCTAssertEqual(ComposeOrchestrator.parseDuration("1m30s"), 90)
        XCTAssertEqual(ComposeOrchestrator.parseDuration("500ms"), 0.5)
        XCTAssertEqual(ComposeOrchestrator.parseDuration("1h"), 3600)
        XCTAssertNil(ComposeOrchestrator.parseDuration(nil))
    }

    func testParseVolumeSpec() {
        let project = ComposeProject(name: "myapp", services: [:])
        let composeFile = "/Users/me/project/docker-compose.yml"
        let bind = ComposeOrchestrator.parseVolumeSpec("./html:/usr/share/nginx/html:ro", project: project, basePath: composeFile)
        XCTAssertTrue(bind?.isVirtiofs ?? false)
        XCTAssertEqual(bind?.options, ["ro"])

        let named = ComposeOrchestrator.parseVolumeSpec("data:/var/lib/data", project: project, basePath: composeFile)
        XCTAssertTrue(named?.isVolume ?? false)
        XCTAssertEqual(named?.volumeName, "myapp_data")
    }

    func testLoadEnvFile() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test-compose-env-\(UUID().uuidString).env")
        try "FOO=bar\n# comment\nBAZ=\"quoted\"\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let env = ComposeOrchestrator.loadEnvFile(at: url.path)
        XCTAssertEqual(env?["FOO"], "bar")
        XCTAssertEqual(env?["BAZ"], "quoted")
    }

    // MARK: - Parser: string-or-list / string-or-map shorthand forms

    func testBuildAsStringShorthand() throws {
        let yaml = """
        services:
          web:
            build: ./web
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.build?.context, "./web")
        XCTAssertNil(web.image)
    }

    func testBuildAsDict() throws {
        let yaml = """
        services:
          web:
            build:
              context: ./web
              dockerfile: Dockerfile.dev
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.build?.context, "./web")
        XCTAssertEqual(web.build?.dockerfile, "Dockerfile.dev")
    }

    func testCommandAsString() throws {
        let yaml = """
        services:
          web:
            image: node:22
            command: npm start
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.command, ["npm", "start"])
    }

    func testCommandAsList() throws {
        let yaml = """
        services:
          web:
            image: node:22
            command: ["npm", "start"]
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.command, ["npm", "start"])
    }

    func testHealthcheckTestAsString() throws {
        let yaml = """
        services:
          web:
            image: nginx
            healthcheck:
              test: curl -f http://localhost
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.healthcheck?.test, ["curl -f http://localhost"])
    }

    func testNetworksAsMap() throws {
        let yaml = """
        services:
          web:
            image: nginx
            networks:
              default:
                aliases:
                  - web
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.networks, ["default"])
    }

    func testPortsAsMapNormalizedToString() throws {
        let yaml = """
        services:
          web:
            image: nginx
            ports:
              - target: 80
                published: 8080
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertEqual(web.ports, ["8080:80"])
    }

    func testSecurityOptionsAndPrivilegeParsing() throws {
        let yaml = """
        services:
          web:
            image: nginx
            privileged: true
            cap_add:
              - SYS_ADMIN
            security_opt:
              - seccomp=unconfined
        """
        let project = try ComposeParser().parse(yaml: yaml)
        let web = try XCTUnwrap(project.services["web"])
        XCTAssertTrue(web.privileged)
        XCTAssertEqual(web.capAdd, ["SYS_ADMIN"])
        XCTAssertEqual(web.securityOpt, ["seccomp=unconfined"])
    }
}
