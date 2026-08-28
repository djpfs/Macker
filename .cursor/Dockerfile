#===----------------------------------------------------------------------===//
# Macker — Cloud Agent development image.
#
# Macker is a macOS-only application: the GUI uses SwiftUI/AppKit and the
# backend talks to Apple's `container-apiserver` over libxpc, so the product
# CANNOT be built, tested, or run on Linux (see .cursor/README.md).
#
# Cloud Agents run on x86_64 Linux, so this image provides the pinned Swift
# toolchain (matching swift-tools-version 6.0 in Package.swift) so agents can:
#   - browse/edit Swift sources with a working toolchain (SourceKit-LSP),
#   - resolve dependencies (`swift package resolve`),
#   - run the same formatter CI uses (`swift format`).
# A full `swift build`/`swift test` requires macOS 15 + Xcode + apple/container.
#===----------------------------------------------------------------------===//
FROM swift:6.1-noble

# git + curl for repository operations and tooling; ca-certificates for TLS.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
    && rm -rf /var/lib/apt/lists/*

# The official Swift image derives from ubuntu:24.04, which ships a uid-1000
# `ubuntu` user. Guard the creation so the build is robust either way.
RUN id -u ubuntu >/dev/null 2>&1 || useradd --create-home --shell /bin/bash --uid 1000 ubuntu

USER ubuntu
