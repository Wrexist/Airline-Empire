#!/usr/bin/env bash
# Installs a Swift 6.0.3 toolchain on Linux x86_64 for building/testing
# AirlineEmpireCore in environments where download.swift.org is unreachable.
#
# Source: the SwiftWasm project's GitHub release mirror. Their toolchain is
# the official Swift 6.0.3 compiler + a wasm cross target; the native
# x86_64-linux host toolchain inside it is fully standard (verified:
# `swift test` with Swift Testing works, Phase 1, 2026-08-25).
#
# Usage:  source scripts/setup-linux-toolchain.sh   (adds swift to PATH)
#         ./scripts/setup-linux-toolchain.sh        (install only)
set -euo pipefail

SWIFT_VERSION="swift-wasm-6.0.3-RELEASE"
INSTALL_DIR="${SWIFT_INSTALL_DIR:-$HOME/.swift-toolchain}"
URL="https://github.com/swiftwasm/swift/releases/download/${SWIFT_VERSION}/${SWIFT_VERSION}-ubuntu22.04_x86_64.tar.gz"

if [ ! -x "${INSTALL_DIR}/${SWIFT_VERSION}/usr/bin/swift" ]; then
  echo "Installing Swift toolchain to ${INSTALL_DIR} ..."
  mkdir -p "${INSTALL_DIR}"
  curl -sSL --retry 3 "${URL}" | tar -xz -C "${INSTALL_DIR}"
fi

export PATH="${INSTALL_DIR}/${SWIFT_VERSION}/usr/bin:${PATH}"
swift --version
