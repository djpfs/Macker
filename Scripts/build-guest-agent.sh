#!/bin/bash
#===----------------------------------------------------------------------===//
# build-guest-agent.sh — cross-compile the hot-reload guest agent for Linux
# aarch64.
#
# The agent is a tiny C program (no libc dependencies beyond the kernel
# syscalls), so it can be built with any aarch64 Linux cross toolchain. The
# script looks for one in this order:
#   1. $CROSS_CC (explicit)
#   2. aarch64-linux-gnu-gcc on PATH
#   3. zig cc (zig ships a bundled aarch64-linux-musl target)
#
# Output: Resources/guest-agent/guest-agent (static aarch64 binary).
#===----------------------------------------------------------------------===//
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Resources/guest-agent/guest-agent.c"
OUT="$ROOT/Resources/guest-agent/guest-agent"

if [[ -n "${CROSS_CC:-}" ]]; then
    CC="$CROSS_CC"
elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    CC="aarch64-linux-gnu-gcc"
elif command -v zig >/dev/null 2>&1; then
    CC="zig cc -target aarch64-linux-musl"
else
    echo "error: no aarch64 Linux cross compiler found." >&2
    echo "  Install one, or set CROSS_CC, or install zig (brew install zig)." >&2
    exit 1
fi

echo "Building guest agent with: $CC"
$CC -O2 -static -s -o "$OUT" "$SRC"
chmod +x "$OUT"
echo "Built $OUT ($(wc -c < "$OUT") bytes)"
