#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/compile-$(date +%Y%m%d-%H%M%S).log"
VERSION="138.0.7204.157"
DEPOT_TOOLS="$SCRIPT_DIR/depot_tools"
CHROMIUM_DIR="$SCRIPT_DIR/chromium"
SRC_DIR="$CHROMIUM_DIR/src"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Job 2: Compile started: $(date) ==="

export PATH="$DEPOT_TOOLS:$PATH"

if [ ! -d "$SRC_DIR/.git" ]; then
  echo "⚠️  Cache miss detected: chromium/src not found"
  echo "Running gclient sync locally (incremental)..."
  
  mkdir -p "$SRC_DIR"
  cd "$SRC_DIR"
  git init
  git remote add origin https://chromium.googlesource.com/chromium/src.git
  git fetch --depth 2 origin "+refs/tags/$VERSION:refs/tags/$VERSION"
  git checkout "$VERSION"
  
  COMMIT=$(cd "$SRC_DIR" && git rev-parse HEAD)
  cat > "$CHROMIUM_DIR/.gclient" <<GCLIENT
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git@$COMMIT",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {},
  },
]
target_os = ["android"]
GCLIENT

  cd "$CHROMIUM_DIR"
  gclient sync -D --no-history --nohooks
  gclient runhooks
  rm -rf third_party/angle/third_party/VK-GL-CTS/
  
  echo "Cache miss recovery complete ✅"
else
  echo "✅ Cache hit: chromium/src found, skipping sync"
fi

cd "$SRC_DIR"

echo "Installing Chromium build deps on fresh runner..."
sudo apt-get update -qq
sudo apt-get install -y lsb-release file git curl python3 python3-pillow
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
