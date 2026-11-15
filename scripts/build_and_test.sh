#!/usr/bin/env bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ]; then
  echo 'Native iOS validation requires macOS/Xcode. Use GitHub Actions from Windows/WSL.'
  echo 'Pure logic can be tested separately: swift test --package-path WorldCore'
  exit 2
fi
for tool in xcodebuild xcrun xcodegen python3; do
  command -v "$tool" >/dev/null || { echo "Required tool missing: $tool"; exit 2; }
done
exec bash "$(dirname "$0")/ci.sh" all
