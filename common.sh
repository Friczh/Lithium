#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

set_keys() {
  mkdir -p "$SCRIPT_DIR/keys"
    echo "$KEYSTORE_JKS" | base64 -d > "$SCRIPT_DIR/keys/lithium.jks"
    }

    sign_apk() {
      local input=$1
      local output=$2
      "$ANDROID_HOME/build-tools/$(ls $ANDROID_HOME/build-tools | tail -1)/apksigner" sign \
      --ks "$SCRIPT_DIR/keys/lithium.jks" \
      --ks-key-alias "$KEY_ALIAS" \
      --ks-pass "pass:$STORE_PASSWORD" \
      --key-pass "pass:$KEY_PASSWORD" \
      --out "$output" \
      "$input"
     }

    replace() {
      local dir=$1
      local from=$2
      local to=$3
      grep -rl "$from" "$dir" | xargs sed -i "s/$from/$to/g"
    }                                       