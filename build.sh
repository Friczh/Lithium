#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
VERSION="138.0.7204.157"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'rm -rf "$SCRIPT_DIR/keys"' EXIT
echo "Lithium Build Started: $(date)"
source "$SCRIPT_DIR/common.sh"
set_keys

# Install deps
sudo apt-get update -qq
sudo apt-get install -y sudo lsb-release file nano git curl python3 python3-pillow

# Clone depot_tools
git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$SCRIPT_DIR/depot_tools"
export PATH="$SCRIPT_DIR/depot_tools:$PATH"

# Setup Chromium dir
mkdir -p "$SCRIPT_DIR/chromium/src/out/Default"
cd "$SCRIPT_DIR/chromium"
gclient root
cd src

# Fetch exact version
git init
git remote add origin https://chromium.googlesource.com/chromium/src.git
git fetch --depth 2 origin "+refs/tags/$VERSION:chromium_$VERSION"
git checkout "$VERSION"
export COMMIT
COMMIT=$(git show-ref -s "$VERSION" | head -n1)

# Write .gclient
cat > "$SCRIPT_DIR/chromium/.gclient" <<GCLIENT
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

# Sync
gclient sync -D --no-history --nohooks
gclient runhooks
rm -rf third_party/angle/third_party/VK-GL-CTS/

# Build deps + generate
./build/install-build-deps.sh --no-prompt
cp "$SCRIPT_DIR/args.gn" out/Default/args.gn
gn gen out/Default

# Build arm64
autoninja -C out/Default chrome_public_apk
mkdir -p out/tmp out/release
mv out/Default/apks/ChromePublic.apk "out/tmp/$VERSION-arm64-v8a.apk"

# Android SDK paths
export ANDROID_HOME="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/temurin-17-jdk-amd64}"
export PATH="$ANDROID_HOME/platform-tools:$JAVA_HOME/bin:$PATH"

sign_apk "out/tmp/$VERSION-arm64-v8a.apk" "out/release/$VERSION-arm64-v8a.apk"
echo "Lithium Build Finished: $(date)"
echo "APK: out/release/$VERSION-arm64-v8a.apk"
