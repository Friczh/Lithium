#!/bin/bash
set -euo pipefail

WORK_DIR="${WORK_DIR:-.}"
SCRIPT_DIR="$WORK_DIR/repo"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/sign-$(date +%Y%m%d-%H%M%S).log"
VERSION="138.0.7204.157"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'rm -rf "$WORK_DIR/keys"' EXIT
echo "=== Job 3: Sign started: $(date) ==="

source "$SCRIPT_DIR/common.sh"
set_keys

# Android SDK paths
export ANDROID_HOME="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/temurin-17-jdk-amd64}"
export PATH="$ANDROID_HOME/platform-tools:$JAVA_HOME/bin:$PATH"

mkdir -p "$WORK_DIR/chromium/src/out/release"
INPUT="$WORK_DIR/chromium/src/out/tmp/$VERSION-arm64-v8a.apk"
OUTPUT="$WORK_DIR/chromium/src/out/release/$VERSION-arm64-v8a.apk"

echo "Signing $INPUT..."
sign_apk "$INPUT" "$OUTPUT"

echo "Signed APK: $OUTPUT"
echo "=== Job 3: Sign finished: $(date) ==="
