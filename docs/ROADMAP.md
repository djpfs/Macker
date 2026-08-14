# Roadmap & limitations

## Limitations

- **Apple Silicon only** — containers run as Linux VMs via Virtualization.framework.
- **Protocol lockstep** — the XPC protocol is pinned to `apple/container 1.2.2`.
- **No layer deduplication** — each image is a full snapshot; storage can grow
  quickly (see [GUI features](GUI.md)).
- **Hot reload** — only ATTRIB events are synthesized.
- **Not all docker commands** — unsupported commands fail with an explicit
  message (e.g. `attach`, `update`, `history`, `rename`).

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
