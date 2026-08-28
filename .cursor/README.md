# Cloud Agent environment

Macker is a **macOS-only** application:

- The GUI is built with SwiftUI/AppKit/ServiceManagement.
- `ContainerBackend` talks to Apple's `container-apiserver` over `libxpc`
  (`xpc_connection_*`) and uses the `Security` framework, none of which exist on
  Linux, and are not guarded by `#if os(...)`.
- Every other target (`ComposeEngine`, `AppleDockerCLI`, `AppleDockerApp`,
  `HotReloadService`) depends on `ContainerBackend`.

Cloud Agents run on **x86_64 Linux**, so the full product **cannot be built,
tested, or run here**. `swift build` fails on Darwin-only frameworks by design;
a full build/test/run requires **macOS 15 + Xcode + [apple/container]** as CI
does (`runs-on: macos-15`).

## What this environment provides

The image ([`.cursor/Dockerfile`](Dockerfile)) installs the pinned Swift 6
toolchain (matching `swift-tools-version: 6.0`) so agents can:

| Capability | Command | Works on Linux |
| --- | --- | --- |
| Resolve dependencies | `swift package resolve` | ✅ |
| Format / lint | `swift format lint -r Sources Tests` | ✅ |
| Edit with SourceKit-LSP | (editor) | ✅ |
| Build the app | `swift build` / `make build` | ❌ macOS-only |
| Run tests | `swift test` / `make test` | ❌ macOS + Xcode |
| Run the app/CLI | `macker` | ❌ macOS + apple/container |

`install` ([`.cursor/install.sh`](install.sh)) resolves the SwiftPM
dependencies. It deliberately does **not** run `swift build`, which cannot
succeed on Linux.

[apple/container]: https://github.com/apple/container
