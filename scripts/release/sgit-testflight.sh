#!/usr/bin/env bash
# The sgit app: archive, sign and upload to App Store Connect (TestFlight), or sign without uploading.
# A copy of testflight.sh that also signs app extensions, each with its own entitlements, and can
# stop before the upload (DESTINATION=export): a signing mistake then shows on a work branch, not on dev.
# Simplified from PrompTugal__App__iOS scripts/release/{signing-setup,testflight}.sh.
#
#   1. install the App Store Connect API key from the environment
#   2. archive Release for a generic iOS device, UNSIGNED (automatic signing of the archive
#      would create a development certificate on every run and use up the account's limit)
#   3. sign the app ad hoc with the codesign tool and its entitlements file, so the export
#      knows which entitlements the app declares
#   4. check the archive is the app we mean to upload
#   5. export with destination "upload": Xcode signs with a cloud-managed distribution
#      certificate and profile (the API key needs the Admin role) and uploads
#
# Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64, APPLE_TEAM_ID, PROJECT, SCHEME,
# EXPECTED_BUNDLE, ENTITLEMENTS, MARKETING_VERSION, BUILD_NUMBER; optional DESTINATION (upload, the default,
# or export) and EXTENSION_ENTITLEMENTS_DIR (holding <extension name>.entitlements). Never prints a secret.
set -euo pipefail
set +x
: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_P8_BASE64:?}" "${APPLE_TEAM_ID:?}"
: "${PROJECT:?}" "${SCHEME:?}" "${EXPECTED_BUNDLE:?}" "${ENTITLEMENTS:?}" "${MARKETING_VERSION:?}" "${BUILD_NUMBER:?}"
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
OUT=${RUNNER_TEMP:?}/release
LOGS=${RUNNER_TEMP}/logs
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
mkdir -p "$OUT" "$LOGS"
note() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$SUMMARY"; }
run() { "$root/.github/scripts/run-and-summarize.sh" "$@"; }

keydir=$RUNNER_TEMP/asc
cleanup() { rm -rf "$keydir"; }
trap cleanup EXIT
mkdir -p "$keydir"; chmod 700 "$keydir"
key=$keydir/AuthKey_${ASC_KEY_ID}.p8
printf '%s' "$ASC_KEY_P8_BASE64" | base64 --decode > "$key"
chmod 600 "$key"
grep -q "BEGIN PRIVATE KEY" "$key" || { echo "::error::ASC_KEY_P8_BASE64 does not decode to a .p8 private key"; exit 1; }
auth=(-authenticationKeyPath "$key" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

note ""
note "## TestFlight: \`$EXPECTED_BUNDLE\` $MARKETING_VERSION ($BUILD_NUMBER)"

archive=$OUT/$SCHEME.xcarchive
run "Archive (Release, unsigned)" "$LOGS/archive.log" -- \
  xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" -derivedDataPath "$RUNNER_TEMP/dd-release" \
    MARKETING_VERSION="$MARKETING_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=

app=$(find "$archive/Products/Applications" -maxdepth 1 -name '*.app' | head -1)
[ -n "$app" ] || { echo "::error::the archive holds no .app"; exit 1; }

# Innermost first: frameworks, then extensions, then the app.
while IFS= read -r f; do codesign --force --sign - "$f"; done < <(find "$app" -name '*.framework' -type d -prune)
# Extensions before the app that holds them, each with the entitlements file named after it.
while IFS= read -r ext; do
  name=$(basename "$ext" .appex)
  ent="${EXTENSION_ENTITLEMENTS_DIR:-}/$name.entitlements"
  if [ -n "${EXTENSION_ENTITLEMENTS_DIR:-}" ] && [ -f "$ent" ]; then
    codesign --force --sign - --entitlements "$ent" "$ext"
  else
    codesign --force --sign - "$ext"
  fi
done < <(find "$app" -name '*.appex' -type d -prune)
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$app"

built=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist")
if [ "$built" != "$EXPECTED_BUNDLE" ]; then
  echo "::error::the archive is $built, expected $EXPECTED_BUNDLE. Nothing uploaded."; exit 1
fi
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Info.plist")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Info.plist")
note "- Archive: \`$built\` $version ($build)"

opts=$OUT/ExportOptions.plist
cp "$here/ExportOptions.plist" "$opts"
/usr/libexec/PlistBuddy -c "Set :teamID $APPLE_TEAM_ID" "$opts"
destination=${DESTINATION:-upload}
/usr/libexec/PlistBuddy -c "Set :destination $destination" "$opts"

if [ "$destination" = export ]; then
  run "Sign for distribution, without uploading" "$LOGS/sign.log" -- \
    xcodebuild -exportArchive -archivePath "$archive" -exportPath "$OUT/signed" \
      -exportOptionsPlist "$opts" -allowProvisioningUpdates "${auth[@]}"
  ipa=$(find "$OUT/signed" -name '*.ipa' | head -1)
  [ -n "$ipa" ] || { echo "::error::signing produced no .ipa"; exit 1; }
  note "- Signed for distribution, not uploaded: $(basename "$ipa"), $(du -h "$ipa" | cut -f1). The entitlements it was given:"
  work=$(mktemp -d); unzip -q "$ipa" -d "$work"
  signed=$(find "$work/Payload" -maxdepth 1 -name '*.app' | head -1)
  { echo '```'; codesign -d --entitlements :- "$signed" 2>/dev/null | grep -A3 "application-groups" || echo "(no App Group in the signed app)"; echo '```'; } >> "$SUMMARY"
  rm -rf "$work"
  exit 0
fi

run "Sign and upload to App Store Connect" "$LOGS/upload.log" -- \
  xcodebuild -exportArchive -archivePath "$archive" -exportPath "$OUT/upload" \
    -exportOptionsPlist "$opts" -allowProvisioningUpdates "${auth[@]}"

note "- Uploaded $version ($build). App Store Connect processes it in 5 to 30 minutes; then it is in TestFlight for the internal group."
