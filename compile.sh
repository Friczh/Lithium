#!/bin/bash
set -euo pipefail
MODE="${1:---all}"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/compile-$(date +%Y%m%d-%H%M%S).log"
VERSION="138.0.7204.157"
DEPOT_TOOLS="$SCRIPT_DIR/depot_tools"
CHROMIUM_DIR="$SCRIPT_DIR/chromium"
SRC_DIR="$CHROMIUM_DIR/src"
export PATH="$DEPOT_TOOLS:$PATH"
export DEPOT_TOOLS_METRICS=0

git config --global init.defaultBranch main
git config --global advice.detachedHead false
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Job 2: Compile started: $(date) ==="

if [[ "$MODE" == "--all" || "$MODE" == "--fetch-only" ]]; then
# Install base deps
sudo apt-get update -qq
sudo apt-get install -qq lsb-release file git curl python3 python3-pillow gperf > /dev/null 2>&1

# depot_tools - self-heal 
if [ ! -f "$DEPOT_TOOLS/gclient" ]; then
  echo "⚠️ depot_tools missing, cloning..."
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
else
  echo "✅ depot_tools found"
fi

# Chromium source fetch 
mkdir -p "$SRC_DIR"
cd "$SRC_DIR"
git -c init.defaultBranch=main init
git remote add origin https://chromium.googlesource.com/chromium/src.git 2>/dev/null || true
git fetch --depth 1 origin "+refs/tags/$VERSION:refs/tags/$VERSION"
git -c advice.detachedHead=false checkout "$VERSION"
sudo apt-get install -qq git-restore-mtime > /dev/null 2>&1

COMMIT=$(cd "$SRC_DIR" && git rev-parse HEAD)
echo "Commit: $COMMIT"

# Write .gclient
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
rm -rf "$SRC_DIR/third_party/angle/third_party/VK-GL-CTS/"
fi
git restore-mtime > /dev/null 2>&1

if [[ "$MODE" == "--all" || "$MODE" == "--build-only" ]]; then
# Install Chromium build deps (clang, lld etc.) — fresh runner every time
cd "$SRC_DIR"
./build/install-build-deps --no-prompt > /dev/null 2>&1 || true

# GN gen
mkdir -p out/Default
cp "$SCRIPT_DIR/args.gn" out/Default/args.gn
if [ ! -f out/Default/build.ninja ]; then
  gn gen out/Default
  echo "gn gen done."
else
  echo "gn gen skipped."
fi

# Compile
echo "Building with autoninja + siso..."
autoninja -C out/Default chrome_public_apk
ls -la out/Default/ | head -50

mkdir -p out/tmp out/release
mv out/Default/apks/ChromePublic.apk "out/tmp/$VERSION-arm64-v8a.apk"
echo "APK ready at out/tmp/$VERSION-arm64-v8a.apk"
fi

echo "=== Job 2: Compile finished: $(date) ==="
