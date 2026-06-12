#!/bin/bash
set -euo pipefail

WORK_DIR="${WORK_DIR:-.}"
SCRIPT_DIR="$WORK_DIR/repo"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"
VERSION="138.0.7204.157"
DEPOT_TOOLS="$WORK_DIR/depot_tools"
GCLIENT_VERSION=""

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Job 1: Setup started: $(date) ==="

echo "⚠️ Fetching depot_tools..."
RETRY_COUNT=0
MAX_RETRIES=3

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo ""
  echo "Attempt $RETRY_COUNT of $MAX_RETRIES..."

  # Remove depot_tools if it exists and is incomplete
  if [ -d "$DEPOT_TOOLS" ]; then
    if [ ! -f "$DEPOT_TOOLS/gclient" ]; then
      echo "⚠️  depot_tools directory exists but gclient missing, removing..."
      rm -rf "$DEPOT_TOOLS"
    fi
  fi

  # Clone depot_tools if it doesn't exist
  if [ ! -d "$DEPOT_TOOLS" ]; then
    echo "Cloning depot_tools..."
    if ! git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"; then
      echo "❌ FAILED: Failed to clone depot_tools on attempt $RETRY_COUNT"
      if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "   Retrying..."
        continue
      else
        echo "❌ ERROR: Failed to fetch depot_tools after $MAX_RETRIES attempts"
        exit 1
      fi
    fi
  fi

  # Verify depot_tools was cloned successfully
  if [ ! -f "$DEPOT_TOOLS/gclient" ]; then
    echo "❌ FAILED: gclient not found after clone on attempt $RETRY_COUNT"
    rm -rf "$DEPOT_TOOLS"
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "   Retrying..."
      continue
    else
      echo "❌ ERROR: Failed to verify depot_tools after $MAX_RETRIES attempts"
      exit 1
    fi
  fi

  # Check if gclient is executable
  if [ ! -x "$DEPOT_TOOLS/gclient" ]; then
    echo "⚠️  Making gclient executable..."
    chmod +x "$DEPOT_TOOLS/gclient"
  fi

  # Test gclient
  if ! "$DEPOT_TOOLS/gclient" --version > /dev/null 2>&1; then
    echo "❌ FAILED: gclient --version failed on attempt $RETRY_COUNT"
    rm -rf "$DEPOT_TOOLS"
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "   Retrying..."
      continue
    else
      echo "❌ ERROR: Failed to validate gclient after $MAX_RETRIES attempts"
      exit 1
    fi
  fi

  # Success!
  GCLIENT_VERSION=$("$DEPOT_TOOLS/gclient" --version 2>&1 | head -1) || true
  echo ""
  echo "✅ SUCCESS: depot_tools fetched and verified!"
  echo "   Location: $DEPOT_TOOLS"
  echo "   Version: $GCLIENT_VERSION"
  echo ""
  exit 0
done

echo "❌ ERROR: depot_tools fetch failed after $MAX_RETRIES attempts"
exit 1
