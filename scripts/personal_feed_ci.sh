#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/personal-feed"
mkdir -p "$OUT/screenshots"
core() {
git rev-parse HEAD > "$OUT/commit.txt"
xcodebuild -version > "$OUT/toolchain.txt"
python3 -m unittest discover -s scripts/tests -p 'test_personal_feed_*.py' -v 2>&1 | tee "$OUT/architecture-tests.log"
swift test --package-path PersonalClient/Core 2>&1 | tee "$OUT/core-tests.log"
swift test --package-path PersonalClient/Core -c release -Xswiftc -Osize 2>&1 | tee "$OUT/core-release-tests.log"
}
simulator() {
# Generated fixture identity is simulator-only. No provision, private key or device entitlement is used.
python3 - <<'PY'
import plistlib
from pathlib import Path
p=Path('PersonalClient/Generated/Simulator.entitlements')
p.parent.mkdir(parents=True,exist_ok=True)
p.write_bytes(plistlib.dumps({
    'application-identifier':'398XACWZ7G.org.worldexe.personalfeed',
    'com.apple.developer.team-identifier':'398XACWZ7G',
    'keychain-access-groups':['398XACWZ7G.org.worldexe.personalfeed'],
    'get-task-allow':True,
}))
PY
xcodegen generate --spec PersonalClient/project.yml --project PersonalClient
xcodebuild -project PersonalClient/PersonalFeed.xcodeproj -scheme PersonalFeed -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUT/DerivedData" \
  -resultBundlePath "$OUT/BuildForTesting.xcresult" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=398XACWZ7G build-for-testing 2>&1 | tee "$OUT/simulator-build.log"
SIM_APP="$OUT/DerivedData/Build/Products/Debug-iphonesimulator/PersonalFeed.app"
codesign --verify --deep --strict "$SIM_APP"
codesign -d --entitlements - "$SIM_APP" > "$OUT/simulator-entitlements.plist" 2> "$OUT/simulator-signature.log"
python3 - "$OUT/simulator-entitlements.plist" <<'PY'
import plistlib,sys
p=plistlib.load(open(sys.argv[1],'rb'))
identity=p.get('application-identifier') or p.get('com.apple.application-identifier')
if identity != '398XACWZ7G.org.worldexe.personalfeed':
    raise SystemExit('Simulator application identity missing; real Keychain tests require normal local signing')
if p.get('keychain-access-groups') != ['398XACWZ7G.org.worldexe.personalfeed']:
    raise SystemExit('Unexpected default keychain group in simulator')
if p.get('com.apple.security.application-groups'):
    raise SystemExit('Unexpected shared app group in personal-client simulator')
print('Simulator ad-hoc application identity verified; no Apple private signing key used.')
PY
}
ui() {
xcrun simctl list devices available --json > "$OUT/simulators.json"
export FEED_OUT="$OUT"
SIM_ID=$(python3 - <<'PY'
import json, os, re
from pathlib import Path
out=Path(os.environ['FEED_OUT']); data=json.loads((out/'simulators.json').read_text()); choices=[]
for runtime, devices in data['devices'].items():
    m=re.search(r'iOS-(\d+)(?:-(\d+))?', runtime)
    if not m or int(m[1])<18: continue
    for device in devices:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            choices.append((int(m[1]), int(m[2] or 0), device, runtime))
if not choices: raise SystemExit('No iOS 18+ simulator')
choices.sort(key=lambda v:(-v[0],-v[1], 'Pro Max' not in v[2]['name'], v[2]['name']))
_,_,d,r=choices[0]
(out/'selected-simulator.json').write_text(json.dumps({'name':d['name'],'runtime':r,'udid':d['udid']}))
print(d['udid'])
PY
)
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_ID" -b
set +e
xcodebuild -project PersonalClient/PersonalFeed.xcodeproj -scheme PersonalFeed -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_ID" -derivedDataPath "$OUT/DerivedData" \
  -resultBundlePath "$OUT/TestResults.xcresult" -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 240 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=398XACWZ7G test-without-building 2>&1 | tee "$OUT/ios-tests.log"
test_status=${PIPESTATUS[0]}
set -e
if [ -d "$OUT/TestResults.xcresult" ]; then
  xcrun xcresulttool export attachments --path "$OUT/TestResults.xcresult" --output-path "$OUT/screenshots/test-attachments" || true
fi
[ "$test_status" -eq 0 ] || return "$test_status"
}
device() {
xcodebuild -project PersonalClient/PersonalFeed.xcodeproj -scheme PersonalFeed -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$OUT/DeviceData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build 2>&1 | tee "$OUT/device-build.log"
python3 scripts/verify_app_identity.py "$OUT/DeviceData/Build/Products/Release-iphoneos/PersonalFeed.app" \
  --version 0.1.0 --build 1 --bundle org.worldexe.personalfeed | tee "$OUT/identity.json"
ditto -c -k --sequesterRsrc --keepParent "$OUT/DerivedData/Build/Products/Debug-iphonesimulator/PersonalFeed.app" "$OUT/PersonalFeed-Simulator.zip"
ditto -c -k --sequesterRsrc --keepParent "$OUT/DeviceData/Build/Products/Release-iphoneos/PersonalFeed.app" "$OUT/PersonalFeed-UNSIGNED-device.zip"
cat > "$OUT/VALIDATION.md" <<RECEIPT
# Personal Feed demo validation
Commit: $(cat "$OUT/commit.txt")
Source schema and store tests: PASS in Debug and size-optimized Release.
Native encrypted storage and HTTP transport tests: PASS.
Synthetic-data UI flow: PASS (no real account or imported personal content used).
Simulator and unsigned iOS device compilation: PASS.
Hornet API authorization: NOT provided; no live Hornet synchronization implemented.
Native Hornet export schema: NOT verified; only explicitly mapped CSV/JSON supported.
Physical-device biometric protection / networking: NOT verified by simulator.
TestFlight: NOT published by this workflow. Device artifact is unsigned.
RECEIPT
}
case "${1:-all}" in
  core) core ;;
  simulator) simulator ;;
  ui) ui ;;
  device) device ;;
  all) core; simulator; ui; device ;;
  *) echo 'Expected core, simulator, ui, device or all'; exit 2 ;;
esac
