#!/usr/bin/env bash
#
# notarize.sh — Build, sign with Developer ID, notarize, staple, and package CharBar for distribution.
#
# Prerequisites (one-time setup):
#   1. Acquire a "Developer ID Application" certificate in Apple Developer portal and
#      install it in your login keychain. (Different from "Apple Development" — that one
#      is for local debugging only and Gatekeeper rejects it.)
#   2. Create an app-specific password at appleid.apple.com → Security → App-Specific
#      Passwords. Name it e.g. "CharBar Notarization".
#   3. Store credentials in your keychain:
#        xcrun notarytool store-credentials "CharBar-Notary" \
#          --apple-id "your.apple.id@example.com" \
#          --team-id "838ASYRYR5" \
#          --password "your-app-specific-password"
#   4. (Optional, recommended) `brew install create-dmg` to package the result as a DMG.
#
# Usage:
#   ./Scripts/notarize.sh                # Builds, signs, notarizes, staples, packages
#   SKIP_DMG=1 ./Scripts/notarize.sh     # Skip DMG step (just produces a stapled .app)
#
set -euo pipefail

# ---- Configuration --------------------------------------------------------
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="CharBar"
PROJECT="$PROJECT_ROOT/CharBar.xcodeproj"
CONFIG="Release"
TEAM_ID="838ASYRYR5"
NOTARY_PROFILE="CharBar-Notary"   # Must match the profile name used in store-credentials.
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/CharBar.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/CharBar.app"
ZIP_PATH="$BUILD_DIR/CharBar.zip"
DMG_PATH="$BUILD_DIR/CharBar.dmg"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/exportOptions.plist"

# ---- Pretty output --------------------------------------------------------
say()   { printf "\033[1;36m▶︎ %s\033[0m\n" "$*"; }
ok()    { printf "\033[1;32m✓ %s\033[0m\n" "$*"; }
err()   { printf "\033[1;31m✗ %s\033[0m\n" "$*" >&2; }

# ---- Pre-flight -----------------------------------------------------------
command -v xcodebuild >/dev/null   || { err "xcodebuild not found";  exit 1; }
command -v xcrun >/dev/null        || { err "xcrun not found";       exit 1; }

# Verify the notary profile exists (xcrun returns nonzero if absent).
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  err "Notary profile '$NOTARY_PROFILE' not found in keychain."
  err "Run:  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id ... --team-id $TEAM_ID --password ..."
  exit 1
fi

# Verify a Developer ID Application cert is installed.
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  err "No 'Developer ID Application' certificate found in keychain."
  err "Download yours from https://developer.apple.com/account/resources/certificates"
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

# ---- Archive --------------------------------------------------------------
say "Archiving $SCHEME ($CONFIG)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive | xcbeautify --quiet 2>/dev/null || \
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive
ok "Archive created"

# ---- Export options plist (Developer ID, manual signing, hardened runtime) ----
cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

# ---- Export with Developer ID ---------------------------------------------
say "Exporting with Developer ID"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
ok "Exported to $APP_PATH"

# ---- Zip for notarization (notarytool wants a zip or dmg) ------------------
say "Zipping app for notarization"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
ok "Zip created"

# ---- Submit to Apple notarization service ---------------------------------
say "Submitting to Apple notarization (this can take a few minutes)"
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
ok "Notarized"

# ---- Staple ticket so the app works offline -------------------------------
say "Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
ok "Stapled"

# ---- (Optional) Package as DMG --------------------------------------------
if [[ "${SKIP_DMG:-0}" != "1" ]]; then
  if command -v create-dmg >/dev/null 2>&1; then
    say "Building DMG"
    rm -f "$DMG_PATH"
    create-dmg \
      --volname "CharBar" \
      --window-size 540 380 \
      --icon-size 100 \
      --icon "CharBar.app" 140 200 \
      --app-drop-link 400 200 \
      --no-internet-enable \
      "$DMG_PATH" \
      "$APP_PATH"
    ok "DMG ready: $DMG_PATH"
  else
    say "create-dmg not installed; skipping DMG step (brew install create-dmg)"
  fi
fi

echo
ok "Release artifact: $APP_PATH"
[[ -f "$DMG_PATH" ]] && ok "DMG: $DMG_PATH"
