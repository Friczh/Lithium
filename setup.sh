#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"
VERSION="138.0.7204.157"
DEPOT_TOOLS="$SCRIPT_DIR/depot_tools"
CHROMIUM_DIR="$SCRIPT_DIR/chromium"
SRC_DIR="$CHROMIUM_DIR/src"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Job 1: Setup started: $(date) ==="

# Cache check
if [ -f "$DEPOT_TOOLS/gclient" ] && [ -d "$SRC_DIR/.git" ]; then
  echo "✅ depot_tools and chromium/src both exist, nothing to do."
  exit 0
fi

# Install base deps
sudo apt-get update -qq
sudo apt-get install -y lsb-release file git curl python3 python3-pillow

# depot_tools — skip if cached
if [ ! -f "$DEPOT_TOOLS/gclient" ]; then
  echo "Cloning depot_tools..."
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
else
  echo "depot_tools cache hit, skipping clone."
fi
export PATH="$DEPOT_TOOLS:$PATH"

# Chromium src — skip fetch if cached
mkdir -p "$SRC_DIR"

if [ ! -d "$SRC_DIR/.git" ]; then
  echo "Fetching Chromium $VERSION..."
  cd "$SRC_DIR"
  git init
  git remote add origin https://chromium.googlesource.com/chromium/src.git
  git fetch --depth 2 origin "+refs/tags/$VERSION:refs/tags/$VERSION"
  git checkout "$VERSION"
else
  echo "Chromium src cache hit, skipping fetch."
fi

COMMIT=$(cd "$SRC_DIR" && git rev-parse HEAD)
echo "Commit: $COMMIT"

# Write .gclient into chromium/ (parent of src/)
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
gclient root

# gclient sync — skip if build.ninja already exists (full cache hit)
if [ ! -f "$SRC_DIR/out/Default/build.ninja" ]; then
  echo "Running gclient sync..."
  cd "$SRC_DIR"
  gclient sync -D --no-history --nohooks
  gclient runhooks
  rm -rf third_party/angle/third_party/VK-GL-CTS/

  # Install Chromium build deps (clang, lld, etc.)
  ./build/install-build-deps.sh --no-prompt

  mkdir -p out/Default
  cp "$SCRIPT_DIR/args.gn" out/Default/args.gn
  gn gen out/Default
  echo "gn gen done."
else
  echo "build.ninja cache hit, skipping sync + gn gen."
  cp "$SCRIPT_DIR/args.gn" "$SRC_DIR/out/Default/args.gn"
fi

echo "=== Job 1: Setup finished: $(date) ==="
