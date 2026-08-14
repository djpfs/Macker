# Supported commands

## `docker` (container)

| Group | Commands |
|-------|----------|
| **Containers** | `ps`, `run`, `create`, `start`, `stop`, `restart`, `kill`, `rm`, `exec`, `logs`, `stats`, `wait`, `port`, `top`, `pause`, `unpause`, `cp`, `inspect`, `events` |
| **Images** | `images`, `pull`, `push`, `build`, `tag`, `rmi`, `prune`, `load`, `save`, `search` |
| **Volumes** | `volume create`, `volume ls`, `volume rm`, `volume inspect`, `volume prune` |
| **Networks** | `network create`, `network ls`, `network rm`, `network inspect`, `network connect`, `network disconnect`, `network prune` |
| **System** | `system df`, `system prune`, `system info`, `system version` |

## `docker compose`

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
