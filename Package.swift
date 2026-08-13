// swift-tools-version: 6.0
//===----------------------------------------------------------------------===//
// macker — Docker Desktop replacement on Apple's native container runtime
//
// Client + protocol version pinned to apple/container. The XPC protocol is not
// a stable public API: client and container-apiserver ship in lockstep. When
// updating the runtime, bump `containerVersion` and re-run integration tests.
//===----------------------------------------------------------------------===//

import PackageDescription

/// Version of apple/container this client was built and tested against.
let containerVersion = "1.2.2"

let package = Package(
    name: "macker",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "macker", targets: ["AppleDockerApp"]),
        .library(name: "ContainerBackend", targets: ["ContainerBackend"]),
        .library(name: "ComposeEngine", targets: ["ComposeEngine"]),
        .library(name: "HotReloadService", targets: ["HotReloadService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
    ],
    targets: [
        // ── Executable: dual binary (GUI + headless CLI) ─────────────────────
        .executableTarget(
            name: "AppleDockerApp",
            dependencies: [
                "ContainerBackend",
                "ComposeEngine",
                "HotReloadService",
                "AppleDockerCLI",
            ],
            path: "Sources/AppleDockerApp",
            exclude: ["Resources"]
        ),

        // ── CLI: ArgumentParser root + docker/compose shim ───────────────────
        .target(
            name: "AppleDockerCLI",
            dependencies: [
                "ContainerBackend",
                "ComposeEngine",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AppleDockerCLI"
        ),

        // ── Backend: lightweight XPC client for container-apiserver ──────────
        .target(
            name: "ContainerBackend",
            dependencies: [],
            path: "Sources/ContainerBackend"
        ),

        // ── Compose engine: parser + planner + orchestrator + hosts sync ─────
        .target(
            name: "ComposeEngine",
            dependencies: [
                "ContainerBackend",
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/ComposeEngine"
        ),

        // ── Hot reload: FSEvents → synthetic inotify via guest agent ─────────
        .target(
            name: "HotReloadService",
            dependencies: ["ContainerBackend"],
            path: "Sources/HotReloadService"
        ),

        // ── Tests ─────────────────────────────────────────────────────────────
        .testTarget(
            name: "ContainerBackendTests",
            dependencies: ["ContainerBackend"],
            path: "Tests/ContainerBackendTests"
        ),
        .testTarget(
            name: "ComposeEngineTests",
            dependencies: ["ComposeEngine"],
            path: "Tests/ComposeEngineTests"
        ),
        .testTarget(
            name: "DockerShimTests",
            dependencies: ["AppleDockerCLI", "ContainerBackend", "ComposeEngine"],
            path: "Tests/DockerShimTests"
        ),
        .testTarget(
            name: "HotReloadServiceTests",
            dependencies: ["HotReloadService", "ContainerBackend"],
            path: "Tests/HotReloadServiceTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["AppleDockerApp", "ContainerBackend", "ComposeEngine"],
            path: "Tests/IntegrationTests"
        ),
    ]
)
