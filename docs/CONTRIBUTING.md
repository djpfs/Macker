# Contributing

Contributions are welcome — bug reports, feature requests, docs, and pull
requests. Here's how to get involved.

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

## Development setup

In short:

```bash
make build          # debug build
make test           # unit tests (needs full Xcode)
make lint           # swift-format
make run ARGS="docker ps"   # run the CLI headless
```

Requirements:

- **macOS 15+** on **Apple Silicon** (arm64).
- **Full Xcode** — XCTest is not shipped with CommandLineTools, so `make test`
  and the test targets require Xcode.
- [apple/container](https://github.com/apple/container) installed and running
  (`container-apiserver`). The XPC protocol is pinned to **1.2.2** in
  `Package.swift` — client and runtime ship in lockstep.

## Reporting issues

Open an [issue](https://github.com/djpfs/Macker/issues) with:

- A clear title and description of the problem.
- Steps to reproduce, including your macOS version and `apple/container`
  version.
- The output of `docker version` and `docker selftest` if relevant.

## Branch strategy

- `main` — stable releases. Each successful push builds the `.pkg` and
  publishes it as a GitHub Release.
- `develop` — integration branch. **Open pull requests against `develop`.**

## Code style

- Run `make lint` (swift-format) before committing; CI enforces it.
- Match the surrounding code — same naming, comment density, and structure.
- Keep changes focused: one logical change per pull request.

## Testing

- Add or update tests for the code you change. Test targets live in `Tests/`.
- Make sure `make test` passes locally (requires Xcode). CI runs the full
  suite (build, test, lint, CodeQL) on every push and pull request.

## Commit messages

- Write clear, imperative commit messages that describe the change.
- Keep the history clean — amend or rebase locally before pushing.

## Releasing

Releases are cut from `main` by the CI: a push to `main` builds the `.pkg` and
publishes it as a stable GitHub Release (`v1.0.0.<run>`). After a release,
refresh the Homebrew cask with:

```bash
./Scripts/update-cask.sh v1.0.0.<run>
```
