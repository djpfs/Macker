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

This is a repo-managed environment ([`environment.json`](environment.json)) that
runs on Cursor's default Linux image. [`install.sh`](install.sh) provisions the
pinned **Swift 6** toolchain (via [swiftly], matching `swift-tools-version: 6.0`)
and resolves dependencies, so agents can:

| Capability | Command | Works on Linux |
| --- | --- | --- |
| Resolve dependencies | `swift package resolve` | yes |
| Format / lint | `swift format lint -r Sources Tests` | yes |
| Edit with SourceKit-LSP | (editor) | yes |
| Build the app | `swift build` / `make build` | no — macOS-only |
| Run tests | `swift test` / `make test` | no — macOS + Xcode |
| Run the app/CLI | `macker` | no — macOS + apple/container |

`install.sh` is idempotent: the toolchain install runs only on the first boot
(and is baked into environment builds), while later boots only re-resolve
dependencies. It deliberately does **not** run `swift build`, which cannot
succeed on Linux.

> To make cold boots faster, maintainers can later enable environment builds so
> the toolchain is prebuilt into the base snapshot instead of installed on first
> boot.

[apple/container]: https://github.com/apple/container
[swiftly]: https://www.swift.org/install/linux/swiftly/
