#!/usr/bin/env bash
#===----------------------------------------------------------------------===//
# Macker — Cloud Agent install step.
#
# Cloud Agents run on x86_64 Linux, while Macker itself is a macOS-only app
# (SwiftUI/AppKit + apple/container libxpc). The product cannot be built or run
# on Linux (see .cursor/README.md), but the Swift toolchain is cross-platform,
# so this script provisions Swift 6 so agents can edit sources, resolve
# dependencies, and run `swift format`.
#
# The step is idempotent: the (large) toolchain install only runs on the first
# boot; on later boots Swift is already present and only dependency resolution
# runs. `swift build`/`swift test` are intentionally NOT run — they fail on
# Darwin-only frameworks by design.
#===----------------------------------------------------------------------===//
set -euo pipefail

# Pinned to match `swift-tools-version: 6.0` in Package.swift.
SWIFT_VERSION="6.1"
SWIFTLY_ENV="$HOME/.local/share/swiftly/env.sh"

# Make an existing swiftly-managed toolchain visible (no-op on a fresh machine).
if [ -f "$SWIFTLY_ENV" ]; then
    # shellcheck disable=SC1091
    . "$SWIFTLY_ENV"
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "==> Swift not found — installing the Swift ${SWIFT_VERSION} toolchain"

    SUDO=""
    if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    fi

    echo "==> Installing Swift runtime prerequisites (apt)"
    export DEBIAN_FRONTEND=noninteractive
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq --no-install-recommends \
        binutils \
        ca-certificates \
        curl \
        git \
        gnupg2 \
        libc6-dev \
        libcurl4-openssl-dev \
        libedit2 \
        libgcc-13-dev \
        libncurses-dev \
        libpython3-dev \
        libsqlite3-0 \
        libstdc++-13-dev \
        libxml2-dev \
        libz3-dev \
        pkg-config \
        tzdata \
        unzip \
        zlib1g-dev

    echo "==> Installing swiftly + Swift ${SWIFT_VERSION}"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/swiftly.tar.gz" \
        "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
    tar -xzf "$tmp/swiftly.tar.gz" -C "$tmp"
    "$tmp/swiftly" init --quiet-shell-followup --assume-yes --skip-install
    # shellcheck disable=SC1091
    . "$SWIFTLY_ENV"
    swiftly install "${SWIFT_VERSION}" --use --assume-yes
    rm -rf "$tmp"
    hash -r
fi

echo "==> Swift toolchain"
swift --version

echo "==> Resolving SwiftPM dependencies"
swift package resolve

echo "==> install complete"
