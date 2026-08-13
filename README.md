# Macker

A **Docker Desktop replacement** built on Apple's native container runtime
([`apple/container`](https://github.com/apple/container)). It ships a native
macOS SwiftUI GUI **and** a CLI shim you can symlink as `docker` /
`docker-compose`, plus a custom Compose engine with service-name DNS and hot
reload for virtiofs bind mounts.

> Containers run as lightweight Linux VMs on Apple Silicon via
> Virtualization.framework — no Docker daemon, no Docker Desktop license, no
> gRPC/NIO dependency.

---

## Table of Contents

- [Features](#features)
- [How it works](#how-it-works)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [GUI](#gui)
  - [CLI](#cli)
  - [Docker compatibility](#docker-compatibility)
- [Supported commands](#supported-commands)
- [Compose engine](#compose-engine)
- [Hot reload](#hot-reload)
- [Menu bar](#menu-bar)
- [Storage & cleanup](#storage--cleanup)
- [Security](#security)
- [Development](#development)
- [Limitations](#limitations)
- [Next steps](#next-steps)
- [License](#license)

---

## Features

- **Native macOS GUI (SwiftUI)** — Dashboard, Containers, Images, Builds,
  Volumes, Networks, Compose, Activity Monitor and Settings.
- **Docker-compatible CLI** — one binary, two modes. Symlink it as `docker`
  and `docker-compose` for drop-in compatibility.
- **Custom Compose engine** — YAML parser, `${VAR}` interpolation, `.env`
  support, topological `depends_on` resolution, config-hash recreation,
  service-name DNS via `/etc/hosts`, and health-check gating.
- **Hot reload** — FSEvents → synthetic inotify bridge so Vite/webpack/nodemon
  rebuild when you edit files on the host (virtiofs does not propagate inotify).
- **Menu bar extra** — CPU/memory rings, per-container quick actions, and
  customizable metrics.
- **Storage management** — prune images, delete the buildkit builder, and full
  cleanup from the GUI or CLI.

---

## How it works

`apple/container` exposes a private XPC API (`container-apiserver`). Apple
Docker talks to it through a lightweight XPC client — no gRPC, no NIO, no
daemon of its own. Operations that have no XPC route (image build, pull, push,
tag, prune) fall back to the `container` CLI.

The single `macker` binary dispatches on its arguments:

- **No arguments** → launches the SwiftUI GUI.
- **With arguments** → runs the headless CLI (ArgumentParser).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                       │
│  Views (SwiftUI)  ←  AppState (@Observable)                │
├─────────────────────────────────────────────────────────────┤
│                    SERVICE LAYER                            │
│  AppState (polling, state aggregation)                      │
│  ContainerService | ComposeEngine | HotReloadService        │
├─────────────────────────────────────────────────────────────┤
│                    BACKEND LAYER                            │
│  XPCClient (primary) | ProcessRunner (fallback)             │
│  LaunchdManager (daemon lifecycle)                          │
├─────────────────────────────────────────────────────────────┤
│                    PLATFORM LAYER                           │
│  container-apiserver (XPC) | container CLI | virtiofs/VZ     │
└─────────────────────────────────────────────────────────────┘
```

### Modules

| Module | Purpose |
|--------|---------|
| `AppleDockerApp` | SwiftUI GUI + dual-binary dispatch |
| `AppleDockerCLI` | ArgumentParser root + `docker`/`compose` shim |
| `ContainerBackend` | Lightweight XPC client for `container-apiserver` |
| `ComposeEngine` | YAML parser, resolver, orchestrator, DNS sync, health checks |
| `HotReloadService` | FSEvents → synthetic inotify bridge for virtiofs mounts |

---

## Requirements

- **macOS 15+** (Sequoia or later)
- **Apple Silicon** (arm64)
- [apple/container](https://github.com/apple/container) installed and running
  (`container-apiserver`). The protocol version is pinned to **1.2.2** in
  `Package.swift` — client and runtime ship in lockstep.

---

## Installation

### Option A — Build from source

```bash
git clone https://github.com/<you>/macker.git
cd macker
make build          # debug build
```

### Option B — Install the CLI to your PATH

```bash
make install
```

This installs `/usr/local/bin/macker`. To use it as a drop-in `docker`
replacement:

```bash
ln -s /usr/local/bin/macker /usr/local/bin/docker
ln -s /usr/local/bin/macker /usr/local/bin/docker-compose
```

> The GUI also has a **Settings → Install CLI** button that does the same thing
> (with an administrator password prompt).

### Option C — Install the app bundle

Build a `.pkg` installer and install it into `/Applications`:

```bash
./Scripts/build-pkg.sh 1.0.0
open dist/Macker-1.0.0.pkg
```

Or, from the GUI, use **Settings → Install app in /Applications** to copy the
app bundle into `/Applications` (Launchpad/Spotlight discoverable).

### Option D — Homebrew (planned)

A Homebrew formula is on the roadmap.

---

## Usage

### GUI

```bash
macker
```

The GUI provides:

- **Dashboard** — resource cards, daemon status, and CPU/memory/I/O charts with
  configurable time intervals.
- **Containers** — list with search, start/stop/restart, and a detail pane with
  Info / Stats / Logs / Terminal / Files / Settings tabs.
- **Images** — list, pull, and delete (with confirmation).
- **Builds** — build history, build an image from a context, retry failed
  builds, copy the build command, and prune the build cache.
- **Volumes / Networks** — create, inspect, and delete.
- **Compose** — load compose files (including drag & drop), up/down, logs, and
  per-project actions.
- **Activity Monitor** — per-container resource usage.
- **Settings** — menu bar customization, storage cleanup, install CLI/app,
  launch at login, and more.

### CLI

```bash
macker version
macker selftest
macker system status
macker docker ps
macker compose up -d
```

### Docker compatibility

Because the binary is meant to be symlinked as `docker`, unknown top-level
subcommands are transparently routed to the docker shim. So these are
equivalent:

```bash
macker ps
docker ps
```

---

## Supported commands

### `docker` (container)

| Group | Commands |
|-------|----------|
| **Containers** | `ps`, `run`, `create`, `start`, `stop`, `restart`, `kill`, `rm`, `exec`, `logs`, `stats`, `wait`, `port`, `top`, `pause`, `unpause`, `cp`, `inspect`, `events` |
| **Images** | `images`, `pull`, `push`, `build`, `tag`, `rmi`, `prune`, `load`, `save`, `search` |
| **Volumes** | `volume create`, `volume ls`, `volume rm`, `volume inspect`, `volume prune` |
| **Networks** | `network create`, `network ls`, `network rm`, `network inspect`, `network connect`, `network disconnect`, `network prune` |
| **System** | `system df`, `system prune`, `system info`, `system version` |

### `docker compose`

| Command | Description |
|---------|-------------|
| `up` | Create and start services (`-d` to detach) |
| `down` | Stop and remove services (`-v` removes volumes) |
| `ps` | List project containers |
| `logs` | Stream logs (`-f` follow, `--tail N`) |
| `stop` / `start` / `restart` | Manage service lifecycle |
| `pull` | Pull service images |
| `build` | Build service images |
| `create` | Create services without starting |
| `exec` | Run a command in a service container |
| `run` | Run a one-off command |
| `config` | Print the resolved compose config as JSON |
| `images` | List service images |
| `kill` | Kill service containers |
| `port` | Print the public port for a service |
| `rm` | Remove stopped service containers |

Unsupported commands fail with an explicit, actionable message.

---

## Compose engine

`macker compose up`:

1. Parses `docker-compose.yml` (Yams) with `${VAR}` interpolation and `.env`
   support.
2. Resolves `depends_on` topologically (including `service_healthy` gating).
3. Creates and starts containers in dependency order.
4. Writes `<service-name> <ip>` entries into each container's `/etc/hosts` so
   services resolve each other by name.
5. Recreates containers when their config hash changes.

**Supported compose keys:** `services`, `image`, `build`, `ports`, `volumes`,
`networks`, `environment`, `env_file`, `depends_on` (with `service_healthy`),
`healthcheck`, `profiles`, `command`, `entrypoint`, `restart`, `labels`,
`deploy.resources.limits`, `${VAR}` interpolation, `.env`.

---

## Hot reload

virtiofs does not propagate inotify events into the guest, so watch tools
(Vite, webpack, nodemon, Air) never see host-side edits. Following the
Colima/Lima `--mount-inotify` pattern:

1. `FSEventWatcher` watches host directories (debounced, 100ms windows).
2. `InotifyBridge` maps host paths to container paths and batches them.
3. A tiny guest agent (`Resources/guest-agent`, built with
   `Scripts/build-guest-agent.sh`) `touch`es each file.
4. The Linux kernel emits inotify ATTRIB → watch tools rebuild.

**Known limitations:** only ATTRIB events are synthesized (no MODIFY/CREATE/
DELETE), and deletions on the host do not propagate.

---

## Menu bar

The menu bar extra shows customizable metrics (CPU, memory, container counts,
etc.) with per-container quick actions. Configure which metrics appear and
their order in **Settings → Menu bar**. The menu bar also includes an
**Open Macker** action that focuses the existing window instead of
spawning a new instance.

---

## Storage & cleanup

The native runtime stores each image as a full ext4 snapshot (no layer
deduplication like Docker's overlay2), so storage can grow quickly. Macker
provides:

- **GUI:** Settings → Storage — disk usage, prune unused images, prune all
  images, delete the buildkit builder, and full cleanup.
- **CLI:** `docker system prune [-a] [--builder]` — `--builder` also deletes
  the buildkit builder (frees the build cache).

---

## Security

- **Privilege escalation**: the Settings "Install CLI" and "Install app in
  /Applications" actions run `osascript` with administrator privileges. These
  are **user-initiated** and only copy the app's own binary into standard
  locations. See [SECURITY.md](SECURITY.md).
- **No secrets**: the project contains no hardcoded credentials, API keys, or
  tokens. Do not commit `.env` files or `firebase-adminsdk-*.json`.
- **Shell safety**: subprocesses are launched with argument arrays (not shell
  string interpolation), so command arguments are not shell-injected.

---

## Development

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

---

## Limitations

- **Apple Silicon only** — containers run as Linux VMs via Virtualization.framework.
- **Protocol lockstep** — the XPC protocol is pinned to `apple/container 1.2.2`.
- **No layer deduplication** — each image is a full snapshot; storage can grow
  quickly (see [Storage & cleanup](#storage--cleanup)).
- **Hot reload** — only ATTRIB events are synthesized.
- **Not all docker commands** — unsupported commands fail with an explicit
  message (e.g. `attach`, `update`, `history`, `rename`).

---

## Next steps

Ideas and improvements on the roadmap, roughly ordered by impact:

### Reliability & correctness
- **Layer deduplication** — the native runtime stores each image as a full
  snapshot. Investigate sharing base layers across images to cut storage.
- **More docker commands** — implement `attach`, `update`, `history`, `rename`,
  and `docker compose` gaps (`top`, `events`, `pause`).
- **Hot reload fidelity** — synthesize MODIFY/CREATE/DELETE inotify events, not
  just ATTRIB, and propagate host-side deletions.
- **Graceful daemon handling** — auto-start `container-apiserver` if it is not
  running, and surface a clear onboarding flow when the runtime is missing.

### Distribution
- **Homebrew formula** — publish `macker` as a cask/formula.
- **Notarization & signing** — sign the `.pkg` with a Developer ID and notarize
  it so Gatekeeper accepts it out of the box.
- **Auto-update** — integrate Sparkle for seamless in-app updates.
- **CI release pipeline** — build and attach signed `.pkg`/`.dmg` artifacts to
  GitHub Releases on tag push.

### GUI & UX
- **Compose history** — persist recently used compose files for one-click
  reload.
- **Container settings** — richer per-container configuration (networks, port
  mapping, resource limits) from the detail pane.
- **Dashboard** — more chart types and per-container filtering.
- **Localization** — add pt-BR and other locales.

### Performance
- **Faster polling** — batch stats collection and reduce refresh overhead for
  large container counts.
- **Build cache** — surface buildkit cache usage and per-image reclaimable
  space in the GUI.

### Testing
- **More unit tests** — expand coverage for the compose parser, orchestrator,
  and docker shim.
- **Integration tests** — run against a real `container-apiserver` in CI.

---

## License

[MIT](LICENSE) © 2026 macker contributors
