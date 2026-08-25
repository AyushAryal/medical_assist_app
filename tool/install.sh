#!/usr/bin/env bash
# Build the release APK and install it on the attached Android device.
#
# arm64 only: every phone sold in the last several years is arm64, and the
# sherpa-onnx native libraries are ~24 MB *per ABI*. Building all four turns a
# 60 MB APK into a 130 MB one for no benefit on a device you are holding.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -z "$(adb devices | sed '1d' | grep -w device || true)" ]; then
  echo "No Android device attached."
  echo
  echo "  1. Connect the phone by USB"
  echo "  2. Enable Developer options › USB debugging"
  echo "  3. Accept the 'Allow USB debugging' prompt on the phone"
  echo
  echo "Then run this again. 'adb devices' should list it as 'device',"
  echo "not 'unauthorized' or 'offline'."
  exit 1
fi

APK=build/app/outputs/flutter-apk/app-release.apk
rm -f "$APK"

flutter build apk --release --target-platform android-arm64

# `flutter build` can report a Gradle failure and still exit 0, so the APK's
# existence is the thing worth checking rather than the exit code.
if [ ! -f "$APK" ]; then
  echo
  echo "Build produced no APK."
  echo
  echo "If the output mentions 'Could not read workspace metadata' or"
  echo "'Could not deserialize analysis', the Gradle transform cache is"
  echo "corrupt — usually left behind by a build that was interrupted."
  echo "It is a cache and regenerates. Stop the daemon first, or it will just"
  echo "write the bad entries back from memory:"
  echo
  echo "  (cd android && ./gradlew --stop)"
  echo "  rm -rf ~/.gradle/caches/*/transforms ~/.gradle/caches/*/kotlin-dsl"
  echo
  exit 1
fi

adb install -r "$APK"

echo
echo "Installed. The speech model is not bundled — open"
echo "Settings › Dictation on the device to install or side-load it."
