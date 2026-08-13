#!/bin/bash
#===----------------------------------------------------------------------===//
# update-cask.sh — refresh Casks/macker.rb with the version and sha256 of a
# published GitHub release.
#
# Usage: ./Scripts/update-cask.sh v1.0.0.1
# Run this after each stable release (main branch) and commit the updated cask.
#===----------------------------------------------------------------------===//
set -euo pipefail

cd "$(dirname "$0")/.."

TAG="${1:?usage: update-cask.sh <release-tag>}"
CASK="Casks/macker.rb"
VERSION="${TAG#v}"
PKG_URL="https://github.com/djpfs/Macker/releases/download/${TAG}/Macker-${VERSION}.pkg"

echo "==> Downloading ${PKG_URL}..."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/Macker.pkg" "$PKG_URL"

echo "==> Computing sha256..."
SHA="$(shasum -a 256 "$TMP/Macker.pkg" | awk '{print $1}')"

echo "==> Updating ${CASK} (version ${VERSION})..."
sed -i '' \
  -e "s/version \".*\"/version \"${VERSION}\"/" \
  -e "s/sha256 \".*\"/sha256 \"${SHA}\"/" \
  "$CASK"

echo "[OK] ${CASK} updated to ${VERSION} (${SHA})"
