#!/usr/bin/env bash
# Builds libclinical_llm.so for the host (test runs) and for Android arm64
# (the app), against a pinned llama.cpp tag. Run from the repository root.
#
# The pinned tag is the one the shim was written against; llama.cpp's C API
# moves, so bumping it means re-reading include/llama.h against
# native/llm_shim/clinical_llm.c first.
set -euo pipefail

LLAMA_TAG="b10615"
LLAMA_DIR="${LLAMA_DIR:-$HOME/.cache/clinical_llm/llama.cpp}"
NDK="${ANDROID_NDK:-$HOME/Android/Sdk/ndk/26.3.11579264}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIM="$ROOT/native/llm_shim"

if [ ! -d "$LLAMA_DIR" ]; then
  git clone --depth 1 --branch "$LLAMA_TAG" \
    https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
fi

echo "== host (linux x86_64, for tests) =="
cmake -S "$SHIM" -B "$SHIM/build-host" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DLLAMA_CPP_DIR="$LLAMA_DIR"
cmake --build "$SHIM/build-host" --target clinical_llm
mkdir -p "$ROOT/.native/linux-x64"
cp "$SHIM/build-host/libclinical_llm.so" "$ROOT/.native/linux-x64/"

echo "== android arm64-v8a =="
cmake -S "$SHIM" -B "$SHIM/build-android" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DLLAMA_CPP_DIR="$LLAMA_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 \
  -DGGML_OPENMP=OFF
cmake --build "$SHIM/build-android" --target clinical_llm
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" \
  "$SHIM/build-android/libclinical_llm.so"
mkdir -p "$ROOT/android/app/src/main/jniLibs/arm64-v8a"
cp "$SHIM/build-android/libclinical_llm.so" \
   "$ROOT/android/app/src/main/jniLibs/arm64-v8a/"

echo "done:"
ls -lh "$ROOT/.native/linux-x64/libclinical_llm.so" \
       "$ROOT/android/app/src/main/jniLibs/arm64-v8a/libclinical_llm.so"
