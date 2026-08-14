# Compose engine & hot reload

## Compose engine

`docker compose up`:

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
