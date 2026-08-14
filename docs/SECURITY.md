# Security Policy

## Reporting a Vulnerability

If you find a security vulnerability in Macker, please report it privately
by opening a [GitHub Security Advisory](https://github.com/OWNER/REPO/security/advisories/new)
or emailing the maintainers. Please do **not** open a public issue for
security problems.

We aim to acknowledge reports within 48 hours and to ship a fix as soon as
possible.

## Scope

- The SwiftUI GUI (`MackerApp`)
- The docker/compose CLI shim (`MackerCLI`)
- The XPC client and backend (`ContainerBackend`)
- The Compose engine (`ComposeEngine`)
- The hot-reload bridge (`HotReloadService`)

## Security notes

- **Privilege escalation**: the Settings "Install CLI" and "Install app in
  /Applications" actions run `osascript` with administrator privileges. These
  are **user-initiated** and only copy the app's own binary into standard
  locations. The binary path comes from `Bundle.main` (not user input).
- **No secrets**: the project contains no hardcoded credentials, API keys, or
  tokens. Do not commit `.env` files, `firebase-adminsdk-*.json`, or similar
  secrets.
- **Secret handling**: user-managed secrets are stored in the macOS Keychain
  (`docker secret create/ls/inspect/rm`) and can be referenced with
  `keychain://SECRET_NAME` in container environment entries.
- **Image scanning**: `docker scan IMAGE` uses Trivy output to surface known
  vulnerabilities by severity.
- **Action audit trail**: runtime and CLI actions are appended to
  `~/.macker/audit.jsonl`.
- **Shell safety**: subprocesses are launched with argument arrays (not shell
  string interpolation), so command arguments are not shell-injected.
