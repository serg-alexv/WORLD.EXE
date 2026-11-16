#!/usr/bin/env bash
# Exact upstream binary for iPhone/macOS + same-revision source build for simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
PIN=d8f30a5b6db907110b6f8d67c2f84c1443b871ef
SHA=2a3387da97735921ed5256e838750c16c3fc1c3d684dc3e4bc95214dd1bf6ab2
DEST="$PWD/LocalLlama/Frameworks/llama.xcframework"
STAMP="$PWD/LocalLlama/Frameworks/pin.txt"
EXPECTED="$PIN-xcode26.3-sim-v1"
if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$EXPECTED" && -f "$DEST/Info.plist" ]]; then
  echo 'Pinned llama.cpp framework restored.'; exit 0
fi
[[ "$(uname -s)" == Darwin ]] || { echo 'Framework preparation requires macOS/Xcode.'; exit 2; }
command -v cmake >/dev/null || brew install cmake
mkdir -p build LocalLlama/Frameworks
TMP=$(mktemp -d "${RUNNER_TEMP:-/tmp}/world-llama.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
curl --fail --location --retry 3 --proto '=https' \
  'https://github.com/ggml-org/llama.cpp/releases/download/b12398/llama-b12398-xcframework.zip' -o "$TMP/framework.zip"
echo "$SHA  $TMP/framework.zip" | shasum -a 256 -c -
unzip -q "$TMP/framework.zip" -d "$TMP/upstream"
git init -q "$TMP/source"
git -C "$TMP/source" fetch -q --depth 1 https://github.com/ggml-org/llama.cpp.git "$PIN"
git -C "$TMP/source" checkout -q --detach FETCH_HEAD
[[ "$(git -C "$TMP/source" rev-parse HEAD)" == "$PIN" ]]
(cd "$TMP/source"; bash build-xcframework.sh ios-sim) > build/llama-simulator-build.log 2>&1 || { tail -80 build/llama-simulator-build.log; exit 1; }
UP="$TMP/upstream/build-apple/llama.xcframework"
SIM="$TMP/source/build-ios-sim/framework/llama.framework"
[[ -f "$SIM/llama" && -f "$UP/ios-arm64/llama.framework/llama" ]]
# Check public C ABI headers match before combining slices.
cmp "$SIM/Headers/llama.h" "$UP/ios-arm64/llama.framework/Headers/llama.h"
[[ ! -e "$DEST" ]] || { echo 'Unrecognized existing framework: remove only the generated LocalLlama/Frameworks cache and retry.'; exit 2; }
xcodebuild -create-xcframework \
  -framework "$UP/ios-arm64/llama.framework" \
  -framework "$UP/macos-arm64_x86_64/llama.framework" \
  -framework "$SIM" -output "$DEST" > build/llama-framework.log
printf '%s' "$EXPECTED" > "$STAMP"
printf 'llama.cpp b12398\nCommit: %s\nUpstream binary SHA256: %s\nSimulator compiled from same source revision.\n' "$PIN" "$SHA" > build/LLAMA_PROVENANCE.txt
