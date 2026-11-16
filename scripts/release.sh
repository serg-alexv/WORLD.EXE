#!/usr/bin/env bash
# Manual, main-branch-only distribution. Never print credential values.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "${GITHUB_REF:-}" == refs/heads/main ]] || { echo 'Releases require the main branch.'; exit 2; }
for name in DEVELOPMENT_TEAM PRODUCT_BUNDLE_IDENTIFIER PROVISIONING_PROFILE_NAME APPLE_DISTRIBUTION_P12_BASE64 APPLE_DISTRIBUTION_P12_PASSWORD APP_STORE_PROFILE_BASE64; do
  [[ -n "${!name:-}" ]] || { echo "Missing protected environment value: $name"; exit 2; }
done
[[ "$PRODUCT_BUNDLE_IDENTIFIER" == org.worldexe.prototype ]] || { echo 'Unexpected app identity.'; exit 2; }
if [[ "${UPLOAD_TO_TESTFLIGHT:-false}" == true ]]; then
  for name in ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_P8_BASE64; do
    [[ -n "${!name:-}" ]] || { echo "Missing upload value: $name"; exit 2; }
  done
fi
WORK=$(mktemp -d "${RUNNER_TEMP:-/tmp}/world-signing.XXXXXX")
KEYCHAIN="$WORK/world.keychain-db"
PROFILE_PATH=''
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  if [[ -n "$PROFILE_PATH" ]]; then rm -f "$PROFILE_PATH"; fi
  rm -rf "$WORK"
}
trap cleanup EXIT
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
echo "::add-mask::$KEYCHAIN_PASSWORD"
export WORLD_SIGNING_WORK="$WORK"
python3 - <<'PY'
import base64, os
from pathlib import Path
root=Path(os.environ['WORLD_SIGNING_WORK'])
for env,name in [('APPLE_DISTRIBUTION_P12_BASE64','identity.p12'),('APP_STORE_PROFILE_BASE64','profile.mobileprovision')]:
    (root/name).write_bytes(base64.b64decode(os.environ[env],validate=True))
PY
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -P "$APPLE_DISTRIBUTION_P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/[0-9A-F]{40}/ {print $2; exit}')
[[ ${#IDENTITY} -eq 40 ]] || { echo 'No usable signing identity.'; exit 2; }
security cms -D -i "$WORK/profile.mobileprovision" > "$WORK/profile.plist"
PROFILE_UUID=$(python3 - <<'PY'
import datetime, os, plistlib
from pathlib import Path
p=plistlib.loads((Path(os.environ['WORLD_SIGNING_WORK'])/'profile.plist').read_bytes())
assert p['Entitlements']['application-identifier']==os.environ['DEVELOPMENT_TEAM']+'.'+os.environ['PRODUCT_BUNDLE_IDENTIFIER']
assert p['Name']==os.environ['PROVISIONING_PROFILE_NAME']
assert p['ExpirationDate']>datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
assert not p.get('ProvisionedDevices') and not p.get('ProvisionsAllDevices'), 'App Store profile required'
print(p['UUID'])
PY
)
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR" build/export
PROFILE_PATH="$PROFILE_DIR/$PROFILE_UUID.mobileprovision"
[[ ! -e "$PROFILE_PATH" ]] || { echo 'Profile path already exists; refusing to overwrite.'; PROFILE_PATH=''; exit 2; }
cp "$WORK/profile.mobileprovision" "$PROFILE_PATH"
bash scripts/prepare_llama.sh
python3 scripts/GenerateAppIcon.py
xcodegen generate
BUILD_NUMBER="${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}"
xcodebuild -project WorldEXE.xcodeproj -scheme WorldEXE -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/WorldEXE.xcarchive \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" PROVISIONING_PROFILE_SPECIFIER="$PROVISIONING_PROFILE_NAME" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" MARKETING_VERSION=0.5.0 archive
APP=build/WorldEXE.xcarchive/Products/Applications/WorldEXE.app
codesign --verify --deep --strict "$APP"
python3 scripts/verify_app_identity.py "$APP" --version 0.5.0 --build "$BUILD_NUMBER" --bundle "$PRODUCT_BUNDLE_IDENTIFIER"
python3 - <<'PY'
import os, plistlib
from pathlib import Path
p={'method':'app-store-connect','destination':'export','signingStyle':'manual','teamID':os.environ['DEVELOPMENT_TEAM'],'provisioningProfiles':{os.environ['PRODUCT_BUNDLE_IDENTIFIER']:os.environ['PROVISIONING_PROFILE_NAME']},'manageAppVersionAndBuildNumber':False,'uploadSymbols':True}
Path('build/ExportOptions.plist').write_bytes(plistlib.dumps(p))
PY
xcodebuild -exportArchive -archivePath build/WorldEXE.xcarchive -exportPath build/export -exportOptionsPlist build/ExportOptions.plist
IPA=$(find build/export -maxdepth 1 -name '*.ipa' -print -quit)
[[ -n "$IPA" ]] || { echo 'Signed IPA not produced.'; exit 2; }
python3 scripts/verify_app_identity.py "$IPA" --version 0.5.0 --build "$BUILD_NUMBER" --bundle "$PRODUCT_BUNDLE_IDENTIFIER"
UPLOADED=false
if [[ "${UPLOAD_TO_TESTFLIGHT:-false}" == true ]]; then
  mkdir -p "$WORK/private_keys"
  python3 - <<'PY'
import os, base64
from pathlib import Path
(Path(os.environ['WORLD_SIGNING_WORK'])/'private_keys'/('AuthKey_'+os.environ['ASC_KEY_ID']+'.p8')).write_bytes(base64.b64decode(os.environ['ASC_PRIVATE_KEY_P8_BASE64'],validate=True))
PY
  API_PRIVATE_KEYS_DIR="$WORK/private_keys" xcrun altool --upload-app --type ios -f "$IPA" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  UPLOADED=true
fi
printf '# Release receipt\nCommit: %s\nBuild: 0.5.0 (%s)\nSignature verified: yes\nUpload command accepted: %s\nApple processing and TestFlight group availability: must be checked independently.\n' "$GITHUB_SHA" "$BUILD_NUMBER" "$UPLOADED" > build/RELEASE_RECEIPT.md
