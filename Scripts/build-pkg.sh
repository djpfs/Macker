#!/bin/bash
#===----------------------------------------------------------------------===//
# build-pkg.sh — build a macOS .pkg installer for Macker.
#
# Produces: dist/Macker-<version>.pkg
# The package installs "Macker.app" into /Applications.
#===----------------------------------------------------------------------===//
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
APP_NAME="Macker"
EXEC_NAME="macker"
BUNDLE_ID="com.macker.app"
DIST_DIR="dist"
STAGE="$DIST_DIR/stage"
APP_DIR="$STAGE/Applications/$APP_NAME.app"

echo "==> Building release binary..."
swift build -c release

BIN=".build/release/macker"
if [ ! -f "$BIN" ]; then
    echo "[ERROR] release binary not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling .app bundle..."
rm -rf "$STAGE"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

install -m 0755 "$BIN" "$APP_DIR/Contents/MacOS/$EXEC_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXEC_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc codesigning..."
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "==> Building .pkg..."
mkdir -p "$DIST_DIR"
PKG="$DIST_DIR/Macker-$VERSION.pkg"
rm -f "$PKG"
pkgbuild \
    --root "$STAGE" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location / \
    "$PKG"

rm -rf "$STAGE"
echo "[OK] Created $PKG"
