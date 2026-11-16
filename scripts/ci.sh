#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/screenshots
core() {
  xcodebuild -version | tee build/toolchain.txt
  xcodegen --version | tee -a build/toolchain.txt
  swift --version | tee -a build/toolchain.txt
  git rev-parse HEAD > build/commit.txt
  swift test --package-path WorldCore 2>&1 | tee build/core-tests.log
  swift test --package-path PersonalClient/Core 2>&1 | tee build/feed-core-tests.log
  swift test --package-path PersonalClient/Core -c release -Xswiftc -Osize 2>&1 | tee build/feed-core-release-tests.log
  touch build/core.ok
}
simulator() {
  bash scripts/prepare_llama.sh
  python3 scripts/GenerateAppIcon.py
  python3 - <<'IDENTITY'
import plistlib
from pathlib import Path
Path('build/FusionSimulator.entitlements').write_bytes(plistlib.dumps({
'application-identifier':'398XACWZ7G.org.worldexe.prototype',
'keychain-access-groups':['398XACWZ7G.org.worldexe.prototype'],
'com.apple.developer.team-identifier':'398XACWZ7G','get-task-allow':True}))
IDENTITY
  xcodegen generate
  xcodebuild -project WorldEXE.xcodeproj -scheme WorldEXE -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath build/DerivedData -resultBundlePath build/BuildForTesting.xcresult \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=398XACWZ7G build-for-testing 2>&1 | tee build/simulator-build.log
  python3 scripts/verify_app_identity.py build/DerivedData/Build/Products/Debug-iphonesimulator/WorldEXE.app --version 0.5.0 --build 1
  touch build/simulator-build.ok
}
ui() {
  xcrun simctl list devices available --json > build/simulators.json
  python3 - <<'PY'
import json,re,subprocess
from pathlib import Path
p=json.loads(Path('build/simulators.json').read_text())
choices=[]
for runtime,devices in p['devices'].items():
    m=re.search(r'iOS-(\d+)(?:-(\d+))?',runtime)
    if not m or int(m[1])<18: continue
    for d in devices:
        if d.get('isAvailable') and d['name'].startswith('iPhone'):
            choices.append((int(m[1]),int(m[2] or 0),d,runtime))
if not choices: raise SystemExit('No iOS 18+ iPhone simulator; runtime validation unavailable')
choices.sort(key=lambda x:(-x[0],-x[1],'Pro Max' not in x[2]['name'],x[2]['name']))
_,_,d,runtime=choices[0]
Path('build/simulator-id.txt').write_text(d['udid'])
Path('build/selected-simulator.json').write_text(json.dumps({'name':d['name'],'runtime':runtime,'udid':d['udid']},indent=2))
print('Selected simulator:',d['name'],runtime,flush=True)
if d['state']!='Booted': subprocess.run(['xcrun','simctl','boot',d['udid']],check=True,timeout=60)
subprocess.run(['xcrun','simctl','bootstatus',d['udid'],'-b'],check=True,timeout=240)
PY
  local id; id=$(cat build/simulator-id.txt)
  xcrun simctl install "$id" build/DerivedData/Build/Products/Debug-iphonesimulator/WorldEXE.app
  export WORLD_SIM_CONTAINER
  WORLD_SIM_CONTAINER=$(xcrun simctl get_app_container "$id" org.worldexe.prototype data)
  python3 - <<'MODEL_FIXTURE'
import json,os,shutil
from pathlib import Path
m=json.loads(Path('Dependencies/models.json').read_text())['defaultModel']
source=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'world-qwen-23749fef'/m['filename']
assert source.is_file() and source.stat().st_size==m['bytes']
root=Path(os.environ['WORLD_SIM_CONTAINER'])/'Library'/'Application Support'/'Models-CI'
root.mkdir(parents=True,exist_ok=True)
filename=m['sha256']+'.gguf'
shutil.copyfile(source,root/filename)
record={'name':'Qwen3 native UI fixture','filename':filename,'bytes':m['bytes'],'sha256':m['sha256'],'source':'Pinned model; real runtime, not a mock'}
(root/'installed-v1.json').write_text(json.dumps(record),encoding='utf-8')
print('Isolated real GGUF fixture installed in simulator app container.')
MODEL_FIXTURE
  # Reproduce the ranking-clear regression before the full suite. No test is skipped below.
  xcodebuild -project WorldEXE.xcodeproj -scheme WorldEXE -configuration Debug \
    -destination "platform=iOS Simulator,id=$id" -derivedDataPath build/DerivedData \
    -resultBundlePath build/FocusedUI.xcresult -parallel-testing-enabled NO \
    -only-testing:WorldEXEUITests/SignalSiegeUITests/testOfflineNPCAndLocalRankingsClear \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
    -maximum-test-execution-time-allowance 240 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=398XACWZ7G \
    test-without-building 2>&1 | tee build/focused-ui-tests.log
  xcodebuild -project WorldEXE.xcodeproj -scheme WorldEXE -configuration Debug \
    -destination "platform=iOS Simulator,id=$id" -derivedDataPath build/DerivedData \
    -resultBundlePath build/TestResults.xcresult -parallel-testing-enabled NO \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 240 \
    -maximum-test-execution-time-allowance 300 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=398XACWZ7G \
    test-without-building 2>&1 | tee build/ios-tests.log
  touch build/ui.ok
  xcrun simctl terminate "$id" org.worldexe.prototype 2>/dev/null || true
  python3 scripts/fusion_simulator_launch.py "$id" org.worldexe.prototype -ui-testing
  sleep 3
  xcrun simctl io "$id" screenshot build/screenshots/training-launch.png
  xcrun xcresulttool export attachments --path build/TestResults.xcresult --output-path build/screenshots/test-attachments || echo 'Attachment export unavailable; original xcresult is retained.'
}
device() {
  xcodebuild -project WorldEXE.xcodeproj -scheme WorldEXE -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath build/DeviceData \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
    build 2>&1 | tee build/device-build.log
  python3 scripts/verify_app_identity.py build/DeviceData/Build/Products/Release-iphoneos/WorldEXE.app --version 0.5.0 --build 1
  touch build/device.ok
  ditto -c -k --sequesterRsrc --keepParent build/DerivedData/Build/Products/Debug-iphonesimulator/WorldEXE.app build/WORLD.EXE-Simulator.zip
  ditto -c -k --sequesterRsrc --keepParent build/DeviceData/Build/Products/Release-iphoneos/WorldEXE.app build/WORLD.EXE-UNSIGNED-device.zip
  for gate in core simulator-build ui device; do [ -f "build/$gate.ok" ] || { echo "Missing validation gate: $gate"; exit 1; }; done
  printf '# Validation receipt\nCommit: %s\nCore tests: passed.\nSimulator build and gameplay UI tests: passed.\niOS device target: compiled WITHOUT signing.\nPhysical LiDAR/RoomPlan and human playtest: NOT validated.\nTestFlight: NOT uploaded by this workflow.\n' "$(cat build/commit.txt)" > build/VALIDATION.md
}
case "${1:-all}" in
 core) core;; simulator) simulator;; ui) ui;; device) device;;
 all) core; simulator; ui; device;;
 *) echo 'Usage: ci.sh [all|core|simulator|ui|device]'; exit 2;;
esac
