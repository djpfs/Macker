# Architecture

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

## Modules

| Module | Purpose |
|--------|---------|
| `AppleDockerApp` | SwiftUI GUI + dual-binary dispatch |
| `AppleDockerCLI` | ArgumentParser root + `docker`/`compose` shim |
| `ContainerBackend` | Lightweight XPC client for `container-apiserver` |
| `ComposeEngine` | YAML parser, resolver, orchestrator, DNS sync, health checks |
| `HotReloadService` | FSEvents → synthetic inotify bridge for virtiofs mounts |
