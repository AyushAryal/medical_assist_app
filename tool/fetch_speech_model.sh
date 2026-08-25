#!/usr/bin/env bash
# Fetch a Whisper speech model to ./.speech-models/, then optionally push it to
# an attached Android device.
#
# Why this exists rather than bundling the model in the APK: it is ~100 MB of
# binary weights. Bundling would put them in the repository, add them to every
# download including for users who will never dictate, and make them
# undeletable. Fetched once and pushed, they stay removable from
# Settings › Dictation.
#
#   ./tool/fetch_speech_model.sh          # download only
#   ./tool/fetch_speech_model.sh --push   # download and push to the device
set -euo pipefail

cd "$(dirname "$0")/.."

MODEL_ID=whisper-tiny-en
REPO=csukuangfj/sherpa-onnx-whisper-tiny.en
PACKAGE=com.medapp.medical_app
DEST=".speech-models/$MODEL_ID"

# name:expected-size — the app refuses a file whose size does not match, so a
# truncated download fails loudly here rather than crashing a C++ library later.
FILES=(
  "tiny.en-tokens.txt:835554"
  "tiny.en-encoder.int8.onnx:12937772"
  "tiny.en-decoder.int8.onnx:89853865"
)

mkdir -p "$DEST"

for entry in "${FILES[@]}"; do
  name="${entry%%:*}"
  want="${entry##*:}"
  path="$DEST/$name"

  if [ -f "$path" ] && [ "$(stat -c%s "$path")" = "$want" ]; then
    echo "have    $name"
    continue
  fi

  echo "fetch   $name ($((want / 1024 / 1024)) MB)"
  curl -fL --progress-bar -o "$path.part" \
    "https://huggingface.co/$REPO/resolve/main/$name"

  got=$(stat -c%s "$path.part")
  if [ "$got" != "$want" ]; then
    rm -f "$path.part"
    echo "ERROR: $name came back as $got bytes, expected $want. Discarded." >&2
    exit 1
  fi
  mv "$path.part" "$path"
done

echo
echo "Model ready in $DEST"

if [ "${1:-}" != "--push" ]; then
  echo "Run again with --push to copy it to an attached device."
  exit 0
fi

if [ -z "$(adb devices | sed '1d' | grep -w device || true)" ]; then
  echo "No Android device attached — nothing pushed." >&2
  exit 1
fi

# The app's own external files directory. adb can write here without root, and
# the app reads it without any runtime permission, which is what makes this a
# viable provisioning route for a device that must never touch a network.
TARGET="/sdcard/Android/data/$PACKAGE/files/speech_models/$MODEL_ID"

adb shell mkdir -p "$TARGET"
for entry in "${FILES[@]}"; do
  name="${entry%%:*}"
  echo "push    $name"
  adb push "$DEST/$name" "$TARGET/$name" >/dev/null
done

echo
echo "Pushed to $TARGET"
echo "The app picks it up on next launch — Settings › Dictation will show"
echo "'Loaded from file'. Remove it there, or with:"
echo "  adb shell rm -rf $TARGET"
