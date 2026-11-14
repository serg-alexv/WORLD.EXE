#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen on the macOS build host.' >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo 'Xcode is required on the macOS build host.' >&2; exit 1; }
swift test --package-path WorldCore
xcodegen generate
if [[ -n "${DESTINATION:-}" ]]; then
  destination="$DESTINATION"
else
  device_id="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; data=json.load(sys.stdin); ids=[d["udid"] for runtime,devices in data["devices"].items() if "iOS" in runtime for d in devices if d.get("isAvailable") and "iPhone" in d["name"]]; print(ids[0] if ids else "")')"
  [[ -n "$device_id" ]] || { echo 'No available iPhone simulator. Install an iOS simulator runtime in Xcode.' >&2; exit 1; }
  destination="platform=iOS Simulator,id=$device_id"
fi
xcodebuild -project WorldEXE.xcodeproj -scheme WorldEXE \
  -destination "$destination" -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
