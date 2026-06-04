#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/compile-$(date +%Y%m%d-%H%M%S).log"
VERSION="138.0.7204.157"
DEPOT_TOOLS="$SCRIPT_DIR/depot_tools"
SRC_DIR="$SCRIPT_DIR/chromium/src"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Job 2: Compile started: $(date) ==="

export PATH="$DEPOT_TOOLS:$PATH"

# Re-install build deps — Job 2 is a fresh runner, clang/lld won't exist
echo "Installing Chromium build deps on fresh runner..."
sudo apt-get update -qq
sudo apt-get install -y lsb-release file git curl python3 python3-pillow
cd "$SRC_DIR"
./build/install-build-deps.sh --no-prompt

# Configure sccache
if command -v sccache &>/dev/null; then
  echo "sccache detected, enabling..."
  export SCCACHE_DIR="${SCCACHE_DIR:-$HOME/.cache/sccache}"
  # Inject cc_wrapper into args.gn if not already there
  if ! grep -q "cc_wrapper" "$SRC_DIR/out/Default/args.gn"; then
    echo 'cc_wrapper="sccache"' >> "$SRC_DIR/out/Default/args.gn"
    echo "Added cc_wrapper=sccache to args.gn, regenerating..."
    gn gen out/Default
  fi
else
  echo "sccache not found, building without cache wrapper."
fi

JOBS=$(nproc)
echo "Building with $JOBS cores..."
autoninja -C out/Default chrome_public_apk -j"$JOBS"

mkdir -p out/tmp out/release
mv out/Default/apks/ChromePublic.apk "out/tmp/$VERSION-arm64-v8a.apk"
echo "APK ready at out/tmp/$VERSION-arm64-v8a.apk"

echo "=== Job 2: Compile finished: $(date) ==="
