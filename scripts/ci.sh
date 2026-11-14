#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/screenshots
xcodebuild -version | tee build/toolchain.txt
xcodegen --version | tee -a build/toolchain.txt
swift --version | tee -a build/toolchain.txt
git rev-parse HEAD > build/commit.txt
swift test --package-path WorldCore 2>&1 | tee build/core-tests.log
swift scripts/GenerateAppIcon.swift
xcodegen generate
xcrun simctl list devices available --json > build/simulators.json
SIMULATOR_ID=$(python3 - <<'PY'
import json
from pathlib import Path
p=json.loads(Path('build/simulators.json').read_text())
devices=[d for group in p['devices'].values() for d in group if d.get('isAvailable') and d['name'].startswith('iPhone')]
if not devices: raise SystemExit('No available iPhone simulator; cannot claim runtime validation')
devices.sort(key=lambda d:(d.get('state')!='Booted',d['name']))
print(devices[0]['udid'])
PY
)
STATE=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; p=json.load(sys.stdin); print(next(d["state"] for ds in p["devices"].values() for d in ds if d["udid"]==sys.argv[1]))' "$SIMULATOR_ID")
if [ "$STATE" != "Booted" ]; then xcrun simctl boot "$SIMULATOR_ID"; fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b
printf '%s\n' "$SIMULATOR_ID" > build/simulator-id.txt
xcodebuild -project WorldEXE.xcodeproj -scheme WorldEXE \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath build/DerivedData -resultBundlePath build/TestResults.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test 2>&1 | tee build/ios-tests.log
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/WorldEXE.app
[ -d "$APP" ] || { echo 'Simulator app artifact missing'; exit 1; }
xcrun simctl install "$SIMULATOR_ID" "$APP"
xcrun simctl terminate "$SIMULATOR_ID" org.worldexe.prototype 2>/dev/null || true
xcrun simctl launch "$SIMULATOR_ID" org.worldexe.prototype -ui-testing
sleep 3
xcrun simctl io "$SIMULATOR_ID" screenshot build/screenshots/training-launch.png
xcodebuild -project WorldEXE.xcodeproj -scheme WorldEXE \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/DeviceData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' build 2>&1 | tee build/device-build.log
ditto -c -k --sequesterRsrc --keepParent "$APP" build/WORLD.EXE-Simulator.zip
ditto -c -k --sequesterRsrc --keepParent \
  build/DeviceData/Build/Products/Release-iphoneos/WorldEXE.app build/WORLD.EXE-UNSIGNED-device.zip
cat > build/VALIDATION.md <<EOF
# Build validation receipt
Commit: $(cat build/commit.txt)
Pure Swift core tests: passed (see core-tests.log).
Simulator UI tests: passed (see TestResults.xcresult and ios-tests.log).
iOS device target: compiled WITHOUT signing; not installable as a TestFlight app.
Simulator launch screenshot: screenshots/training-launch.png.
Physical LiDAR, RoomPlan accuracy, thermal behavior and real gameplay: NOT validated by this CI.
EOF
