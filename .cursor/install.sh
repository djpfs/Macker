#!/usr/bin/env bash
#===----------------------------------------------------------------------===//
# Macker — Cloud Agent install step.
#
# Idempotent repository bootstrap: fetch the pinned SwiftPM dependencies so the
# checkout is ready for editing, dependency resolution, and formatting.
#
# NOTE: `swift build`/`swift test` are intentionally NOT run here. Macker is a
# macOS-only app (SwiftUI/AppKit + apple/container libxpc) and does not compile
# on Linux; a build attempt fails on Darwin-only frameworks by design.
#===----------------------------------------------------------------------===//
set -euo pipefail

# Make the Swift toolchain visible when a swiftly-managed install is present
# (harmless no-op when Swift is already on PATH via the base image).
if [ -f "$HOME/.local/share/swiftly/env.sh" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.local/share/swiftly/env.sh"
fi

echo "==> Swift toolchain"
swift --version

echo "==> Resolving SwiftPM dependencies"
swift package resolve

echo "==> install complete"
