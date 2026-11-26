#!/bin/sh
# CoreType — Clean-Room RRO Overlay Builder (aapt2 + zipalign + apksigner)
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/system/product/overlay}"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Locate Android SDK build-tools
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
BUILD_TOOLS=$(find "$SDK_ROOT/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1 || true)
ANDROID_JAR=$(find "$SDK_ROOT/platforms" -name android.jar 2>/dev/null | sort -V | tail -n 1 || true)

if [ -z "$BUILD_TOOLS" ] || [ -z "$ANDROID_JAR" ]; then
    printf '[CoreType] Error: Android SDK build-tools / android.jar not found under %s\n' "$SDK_ROOT" >&2
    exit 1
fi

AAPT2="$BUILD_TOOLS/aapt2"
ZIPALIGN="$BUILD_TOOLS/zipalign"
APKSIGNER="$BUILD_TOOLS/apksigner"

# Ephemeral signing keystore for clean-room static RRO
KEYSTORE="$WORK_DIR/coretype-rro.jks"
keytool -genkeypair -v \
    -keystore "$KEYSTORE" \
    -storepass android \
    -keypass android \
    -alias coretype \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "CN=CoreType, O=Mystivara, C=ID" >/dev/null 2>&1

mkdir -p "$OUT_DIR"

SRC="$REPO_ROOT/overlays-src/settings"
FLAT_ZIP="$WORK_DIR/res.zip"
UNALIGNED="$WORK_DIR/unaligned.apk"
ALIGNED="$WORK_DIR/aligned.apk"
FINAL_APK="$OUT_DIR/CoreTypeSettingsOverlay.apk"

"$AAPT2" compile --dir "$SRC/res" -o "$FLAT_ZIP"
"$AAPT2" link \
    -o "$UNALIGNED" \
    -I "$ANDROID_JAR" \
    --manifest "$SRC/AndroidManifest.xml" \
    --min-sdk-version 30 \
    --target-sdk-version 35 \
    "$FLAT_ZIP"

"$ZIPALIGN" -f 4 "$UNALIGNED" "$ALIGNED"
"$APKSIGNER" sign \
    --ks "$KEYSTORE" \
    --ks-pass pass:android \
    --key-pass pass:android \
    --ks-key-alias coretype \
    --out "$FINAL_APK" \
    "$ALIGNED"

rm -f "${FINAL_APK}.idsig"
printf '[CoreType] Built clean-room RRO: %s (%s bytes)\n' "$FINAL_APK" "$(wc -c < "$FINAL_APK")"
