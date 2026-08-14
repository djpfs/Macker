<div align="center">

<img src="docs/img/screenshot-01.png" alt="Macker Dashboard" width="900" />

<br />

<img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker" />

# Macker

### The Docker Desktop replacement that runs on Apple's native container runtime.

**One native macOS GUI. One CLI that doubles as `docker` and `docker-compose`. Zero gRPC. Zero NIO. Zero daemon of its own.**

<br />

[![macOS](https://img.shields.io/badge/macOS-15%2B-black?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/macos/sequoia/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-FF375F?style=for-the-badge&logo=apple&logoColor=white)](https://en.wikipedia.org/wiki/Apple_silicon)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/djpfs/Macker?style=for-the-badge&logo=github)](https://github.com/djpfs/Macker/releases)
[![Homebrew Cask](https://img.shields.io/badge/Homebrew-cask-FBB040?style=for-the-badge&logo=homebrew&logoColor=white)](https://github.com/djpfs/homebrew-tools)

<br />

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/djpfs/Macker/ci.yml?branch=main&style=for-the-badge)](https://github.com/djpfs/Macker/actions)
[![CodeQL](https://img.shields.io/github/actions/workflow/status/djpfs/Macker/codeql.yml?branch=main&style=for-the-badge&label=CodeQL&logo=github-actions)](https://github.com/djpfs/Macker/security/code-scanning)
[![Swift Format](https://img.shields.io/badge/lint-swift--format-FF6B6B?style=for-the-badge&logo=swift)](https://github.com/nicklockwood/SwiftFormat)

<br />

[<img src="https://img.shields.io/badge/Screenshots-1E90FF?style=for-the-badge&logo=files&logoColor=white" alt="Screenshots" />](#-screenshots) ·
[<img src="https://img.shields.io/badge/Features-28A745?style=for-the-badge&logo=sparkles&logoColor=white" alt="Features" />](#-features) ·
[<img src="https://img.shields.io/badge/Install-FF6B35?style=for-the-badge&logo=rocket&logoColor=white" alt="Install" />](#-install) ·
[<img src="https://img.shields.io/badge/Docs-6F42C1?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Docs" />](docs/ARCHITECTURE.md) ·
[<img src="https://img.shields.io/badge/Discussions-0D96F6?style=for-the-badge&logo=github&logoColor=white" alt="Discussions" />](https://github.com/djpfs/Macker/discussions)

<br />

</div>

---

<!-- Octicon "zap" — TL;DR -->
<img src="https://img.shields.io/badge/-zap-FFE347?style=flat-square&logoColor=black" alt="" /> **TL;DR**

> **Macker** replaces Docker Desktop on macOS by talking directly to Apple's
> [`apple/container`](https://github.com/apple/container) runtime — no Docker
> daemon, no license, no Electron, no gRPC stack.
>
> - <img src="https://img.shields.io/badge/-desktop-1E90FF?style=flat-square&logoColor=white" alt="" /> **Native SwiftUI GUI** — Dashboard, Containers, Images, Builds, Volumes, Networks, Compose, Activity Monitor, Settings.
> - <img src="https://img.shields.io/badge/-terminal-000000?style=flat-square&logo=gnubash&logoColor=white" alt="" /> **Drop-in CLI** — symlink the binary as `docker` and `docker-compose`.
> - <img src="https://img.shields.io/badge/-package-FF6B35?style=flat-square&logoColor=white" alt="" /> **Custom Compose engine** — `${VAR}` interpolation, `depends_on` with `service_healthy`, service-name DNS, config-hash recreation.
> - <img src="https://img.shields.io/badge/-sync-28A745?style=flat-square&logoColor=white" alt="" /> **Hot reload** — synthetic inotify bridge over virtiofs so Vite/webpack/nodemon rebuild on host edits.
> - <img src="https://img.shields.io/badge/-graph-8E44AD?style=flat-square&logoColor=white" alt="" /> **Menu bar extra** — CPU/memory rings and per-container quick actions.

---

<!-- Octicon "image" — Screenshots -->
<img src="https://img.shields.io/badge/-image-E91E63?style=flat-square&logoColor=white" alt="" /> **Screenshots**

<br />

<div align="center">
<img src="docs/img/screenshot-01.png" alt="Dashboard" width="900" />
<br /><sub><b>Dashboard</b> — runtime status, resource cards, live CPU/Memory/Block I/O charts, and active containers.</sub>
</div>

<br />

<details>
<summary><b><img src="https://img.shields.io/badge/-folder-F39C12?style=flat-square&logoColor=white" alt="" /> Containers &amp; details</b></summary>
<br />

<div align="center">
<img src="docs/img/screenshot-02.png" alt="Containers list" width="900" />
<br /><sub><b>Containers</b> — search &amp; filter sidebar with running containers grouped by compose project.</sub>
</div>

<br />

<div align="center">
<img src="docs/img/screenshot-03.png" alt="Container info" width="900" />
<br /><sub><b>Container detail · Info</b> — configuration, ports, mounts, and compose labels.</sub>
</div>

<br />

<div align="center">
<img src="docs/img/screenshot-10.png" alt="Container settings" width="900" />
<br /><sub><b>Container detail · Settings</b> — networks, published ports, resource limits, env vars, labels.</sub>
</div>
</details>

<details>
<summary><b><img src="https://img.shields.io/badge/-columns-17A2B8?style=flat-square&logoColor=white" alt="" /> Images · Builds · Volumes · Networks</b></summary>
<br />

<div align="center">
<img src="docs/img/screenshot-04.png" alt="Images" width="900" />
<br /><sub><b>Images</b> — repository, tag, ID, size, creation date, and platform.</sub>
</div>

<br />

<div align="center">
<img src="docs/img/screenshot-05.png" alt="Builds" width="900" />
<br /><sub><b>Builds</b> — empty state with Build and Prune cache actions.</sub>
</div>

<br />

<div align="center">
<img src="docs/img/screenshot-06.png" alt="Volumes" width="900" />
<br /><sub><b>Volumes</b> — name, driver, format, size, and created date.</sub>
</div>

<br />

<div align="center">
<img src="docs/img/screenshot-07.png" alt="Networks" width="900" />
<br /><sub><b>Networks</b> — name, mode, subnet, and plugin.</sub>
</div>
</details>

<details>
<summary><b><img src="https://img.shields.io/badge/-menu-6C757D?style=flat-square&logoColor=white" alt="" /> Compose · Activity Monitor · Settings · Menu bar</b></summary>
<br />

<div align="center">
<img src="docs/img/screenshot-08.png" alt="Compose" width="900" />
<br /><sub><b>Compose</b> — current compose file, services with mapped ports, Up/Down, and a logs panel.</sub>
</div>

<br />

<div align="center">
<img src="docs/img/screenshot-09.png" alt="Activity Monitor" width="900" />
<br /><sub><b>Activity Monitor</b> — aggregate CPU/Memory/Containers/Network cards plus per-container usage.</sub>
</div>

<br />

<div align="center">
<img src="docs/img/screenshot-11.png" alt="Settings General" width="900" />
<br /><sub><b>Settings · General</b> — polling, launch at login, menu bar toggle, version, and install actions.</sub>
</div>

<br />

<div align="center">
<img src="docs/img/screenshot-12.png" alt="Settings Storage" width="900" />
<br /><sub><b>Settings · Storage</b> — disk usage breakdown and cleanup actions.</sub>
</div>

<br />

<div align="center">
<img src="docs/img/screenshot-13.png" alt="Settings Menu bar" width="900" />
<br /><sub><b>Settings · Menu bar</b> — visibility toggle, container list size, and metric customization.</sub>
</div>

<br />

<div align="center">
<img src="docs/img/screenshot-14.png" alt="Menu bar extra" width="900" />
<br /><sub><b>Menu bar extra</b> — CPU/memory rings, per-project quick actions, and the Macker dropdown.</sub>
</div>
</details>

---

<!-- Octicon "sparkles" — Features -->
<img src="https://img.shields.io/badge/-zap-FFE347?style=flat-square&logoColor=black" alt="" /> **Features**

<table>
<thead>
<tr>
<th width="33%"><img src="https://img.shields.io/badge/-desktop-1E90FF?style=flat-square&logoColor=white" alt="" /> Native GUI</th>
<th width="33%"><img src="https://img.shields.io/badge/-terminal-000000?style=flat-square&logo=gnubash&logoColor=white" alt="" /> Docker-compatible CLI</th>
<th width="33%"><img src="https://img.shields.io/badge/-package-FF6B35?style=flat-square&logoColor=white" alt="" /> Custom Compose engine</th>
</tr>
</thead>
<tbody>
<tr>
<td>SwiftUI app — Dashboard, Containers, Images, Builds, Volumes, Networks, Compose, Activity Monitor, Settings.</td>
<td>One binary, two modes. Symlink it as <code>docker</code> and <code>docker-compose</code> for drop-in compatibility.</td>
<td>YAML parser, <code>${VAR}</code> interpolation, <code>.env</code> support, topological <code>depends_on</code> with <code>service_healthy</code> gating.</td>
</tr>
<tr>
<th><img src="https://img.shields.io/badge/-sync-28A745?style=flat-square&logoColor=white" alt="" /> Hot reload</th>
<th><img src="https://img.shields.io/badge/-graph-8E44AD?style=flat-square&logoColor=white" alt="" /> Menu bar extra</th>
<th><img src="https://img.shields.io/badge/-cleanup-DC3545?style=flat-square&logoColor=white" alt="" /> Storage management</th>
</tr>
<tr>
<td>FSEvents → synthetic inotify bridge so Vite/webpack/nodemon rebuild on host edits over virtiofs.</td>
<td>CPU/memory rings, per-container quick actions, and customizable metrics.</td>
<td>Prune images, delete the buildkit builder, full cleanup — from GUI or CLI.</td>
</tr>
</tbody>
</table>

---

<!-- Octicon "workflow" — How it works -->
<img src="https://img.shields.io/badge/-workflow-6F42C1?style=flat-square&logoColor=white" alt="" /> **How it works**

`apple/container` exposes a private XPC API (`container-apiserver`). Macker
talks to it through a lightweight XPC client — **no gRPC, no NIO, no daemon of
its own**. Operations that have no XPC route (image build, pull, push, tag,
prune) fall back to the `container` CLI.

The single `macker` binary dispatches on its arguments:

| Invocation | Mode |
|------------|------|
| `macker` | Launches the SwiftUI GUI |
| `macker <args>` | Runs the headless CLI (`ArgumentParser`) |

<div align="center">
<img src="docs/img/layers.jpeg" alt="Architecture layers — Presentation, Service, Backend, Platform" width="800" />
</div>

<img src="https://img.shields.io/badge/-book-6F42C1?style=flat-square&logoColor=white" alt="" /> Read the full module map in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

<!-- Octicon "checklist" — Requirements -->
<img src="https://img.shields.io/badge/-checklist-20C997?style=flat-square&logoColor=white" alt="" /> **Requirements**

| | |
|---|---|
| **macOS** | 15+ (Sequoia or later) |
| **CPU** | Apple Silicon (arm64) |
| **Runtime** | [`apple/container`](https://github.com/apple/container) installed and running (`container-apiserver`) |
| **XPC protocol** | pinned to **1.2.2** in `Package.swift` — client and runtime ship in lockstep |

---

<!-- Octicon "rocket" — Install -->
<img src="https://img.shields.io/badge/-rocket-FF6B35?style=flat-square&logoColor=white" alt="" /> **Install**

### Option A — Homebrew (recommended)

<img src="https://img.shields.io/badge/-homebrew-FBB040?style=flat-square&logo=homebrew&logoColor=white" alt="" /> `brew install --cask djpfs/tools/macker`

Installs the `Macker.app` bundle into `/Applications` (Launchpad/Spotlight
discoverable). The cask lives in the
[`homebrew-tools`](https://github.com/djpfs/homebrew-tools) tap and points to
the latest stable `.pkg` from GitHub Releases.

To use the CLI as a drop-in `docker` replacement, symlink the bundled binary:

```bash
ln -s /Applications/Macker.app/Contents/MacOS/macker /usr/local/bin/docker
ln -s /Applications/Macker.app/Contents/MacOS/macker /usr/local/bin/docker-compose
```

### Option B — Install the CLI to your PATH

<img src="https://img.shields.io/badge/-gear-6C757D?style=flat-square&logoColor=white" alt="" /> `make install`

This installs `/usr/local/bin/macker`. To use it as a drop-in `docker`
replacement:

```bash
ln -s /usr/local/bin/macker /usr/local/bin/docker
ln -s /usr/local/bin/macker /usr/local/bin/docker-compose
```

> <img src="https://img.shields.io/badge/-idea-FFC107?style=flat-square&logoColor=white" alt="" /> The GUI also has a **Settings → Install CLI** button that does the same
> thing (with an administrator password prompt).

### Option C — Install the app bundle

<img src="https://img.shields.io/badge/-package-FF6B35?style=flat-square&logoColor=white" alt="" /> Build a `.pkg` installer and install it into `/Applications`:

```bash
./Scripts/build-pkg.sh 1.0.0
open dist/Macker-1.0.0.pkg
```

Or, from the GUI, use **Settings → Install app in /Applications** to copy the
app bundle into `/Applications`.

### Option D — Build from source

<img src="https://img.shields.io/badge/-tools-6C757D?style=flat-square&logoColor=white" alt="" /> Clone and build:

```bash
git clone https://github.com/djpfs/macker.git
cd macker
make build          # debug build
```

---

<!-- Octicon "monitor" — Usage -->
<img src="https://img.shields.io/badge/-desktop-1E90FF?style=flat-square&logoColor=white" alt="" /> **Usage**

### <img src="https://img.shields.io/badge/-desktop-1E90FF?style=flat-square&logoColor=white" alt="" /> GUI

```bash
macker
```

The GUI provides:

- <img src="https://img.shields.io/badge/-stack-17A2B8?style=flat-square&logoColor=white" alt="" /> **Dashboard** — resource cards, daemon status, and CPU/memory/I/O charts with configurable time intervals.
- <img src="https://img.shields.io/badge/-container-2496ED?style=flat-square&logo=docker&logoColor=white" alt="" /> **Containers** — list with search, start/stop/restart, and a detail pane with Info / Stats / Logs / Terminal / Files / Settings tabs.
- <img src="https://img.shields.io/badge/-file-6C757D?style=flat-square&logoColor=white" alt="" /> **Images** — list, pull, and delete (with confirmation).
- <img src="https://img.shields.io/badge/-build-17A2B8?style=flat-square&logoColor=white" alt="" /> **Builds** — build history, build an image from a context, retry failed builds, copy the build command, and prune the build cache.
- <img src="https://img.shields.io/badge/-storage-6F42C1?style=flat-square&logoColor=white" alt="" /> **Volumes / Networks** — create, inspect, and delete.
- <img src="https://img.shields.io/badge/-compose-FF6B35?style=flat-square&logoColor=white" alt="" /> **Compose** — load compose files (including drag & drop), up/down, logs, and per-project actions.
- <img src="https://img.shields.io/badge/-monitor-8E44AD?style=flat-square&logoColor=white" alt="" /> **Activity Monitor** — per-container resource usage.
- <img src="https://img.shields.io/badge/-settings-6C757D?style=flat-square&logoColor=white" alt="" /> **Settings** — menu bar customization, storage cleanup, install CLI/app, launch at login, and more.

### <img src="https://img.shields.io/badge/-terminal-000000?style=flat-square&logo=gnubash&logoColor=white" alt="" /> CLI

```bash
docker version
docker selftest
docker system status
docker ps
docker compose up -d
```

### <img src="https://img.shields.io/badge/-sync-28A745?style=flat-square&logoColor=white" alt="" /> Docker compatibility

Because the binary is meant to be symlinked as `docker`, unknown top-level
subcommands are transparently routed to the docker shim. So these are
equivalent:

```bash
docker ps
macker ps
```

<img src="https://img.shields.io/badge/-book-6F42C1?style=flat-square&logoColor=white" alt="" /> Full command reference — see [docs/COMMANDS.md](docs/COMMANDS.md).

---

<!-- Octicon "book" — Documentation -->
<img src="https://img.shields.io/badge/-docs-6F42C1?style=flat-square&logoColor=white" alt="" /> **Documentation**

| | |
|---|---|
| <img src="https://img.shields.io/badge/-arch-6F42C1?style=flat-square&logoColor=white" alt="" /> [Architecture](docs/ARCHITECTURE.md) | Layers, modules, and how they fit together |
| <img src="https://img.shields.io/badge/-terminal-000000?style=flat-square&logo=gnubash&logoColor=white" alt="" /> [Supported commands](docs/COMMANDS.md) | Full `docker` and `docker compose` reference |
| <img src="https://img.shields.io/badge/-package-FF6B35?style=flat-square&logoColor=white" alt="" /> [Compose engine &amp; hot reload](docs/COMPOSE-ENGINE.md) | How `docker compose up` works and the virtiofs inotify bridge |
| <img src="https://img.shields.io/badge/-desktop-1E90FF?style=flat-square&logoColor=white" alt="" /> [GUI features](docs/GUI.md) | Menu bar and storage &amp; cleanup |
| <img src="https://img.shields.io/badge/-shield-DC3545?style=flat-square&logoColor=white" alt="" /> [Security](docs/SECURITY.md) | Security policy and notes |
| <img src="https://img.shields.io/badge/-heart-E91E63?style=flat-square&logoColor=white" alt="" /> [Contributing](docs/CONTRIBUTING.md) | Development setup, code style, testing, releasing |
| <img src="https://img.shields.io/badge/-rocket-FF6B35?style=flat-square&logoColor=white" alt="" /> [Roadmap &amp; limitations](docs/ROADMAP.md) | Known limitations and planned improvements |

---

<!-- Octicon "shield-lock" — Security -->
<img src="https://img.shields.io/badge/-security-DC3545?style=flat-square&logoColor=white" alt="" /> **Security**

- **Privilege escalation**: the Settings "Install CLI" and "Install app in
  /Applications" actions run `osascript` with administrator privileges. These
  are **user-initiated** and only copy the app's own binary into standard
  locations. See [SECURITY.md](docs/SECURITY.md).
- **No secrets**: the project contains no hardcoded credentials, API keys, or
  tokens. Do not commit `.env` files or `firebase-adminsdk-*.json`.
- **Keychain-backed secrets**: runtime secrets can be managed with
  `docker secret ...` and referenced as `keychain://SECRET_NAME` in
  `KEY=VALUE` environment entries.
- **Shell safety**: subprocesses are launched with argument arrays (not shell
  string interpolation), so command arguments are not shell-injected.

---

<!-- Octicon "heart" — Contributing -->
<img src="https://img.shields.io/badge/-heart-E91E63?style=flat-square&logoColor=white" alt="" /> **Contributing**

Contributions are welcome — bug reports, feature requests, docs, and pull
requests.

```bash
make build          # debug build
make test           # unit tests (needs full Xcode)
make release        # release build
make lint           # swift-format (if installed)
make guest-agent    # cross-compile the hot-reload agent
make clean          # remove build artifacts
```

Tests run in CI on macOS with full Xcode (XCTest is not shipped with
CommandLineTools). The XPC protocol is not a stable public API — client and
`container-apiserver` ship in lockstep; bump `containerVersion` in
`Package.swift` when updating the runtime.

<img src="https://img.shields.io/badge/-book-6F42C1?style=flat-square&logoColor=white" alt="" /> Full guide — see [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

---

<!-- Octicon "law" — License -->
<img src="https://img.shields.io/badge/-law-6C757D?style=flat-square&logoColor=white" alt="" /> **License**

<div align="center">

[MIT](LICENSE) © 2026 macker contributors

<br />

<sub>Made for the Apple Silicon crowd that just wants containers to work.</sub>

</div>