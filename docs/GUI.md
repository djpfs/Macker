# GUI features

## Menu bar

The menu bar extra shows customizable metrics (CPU, memory, container counts,
etc.) with per-container quick actions. Configure which metrics appear and
their order in **Settings → Menu bar**. The menu bar also includes an
**Open Macker** action that focuses the existing window instead of
spawning a new instance.

## Storage & cleanup

The native runtime stores each image as a full ext4 snapshot (no layer
deduplication like Docker's overlay2), so storage can grow quickly. Macker
provides:

- **GUI:** Settings → Storage — disk usage, prune unused images, prune all
  images, delete the buildkit builder, and full cleanup.
- **CLI:** `docker system prune [-a] [--builder]` — `--builder` also deletes
  the buildkit builder (frees the build cache).
