#!/bin/sh
set -eu

cd "$(dirname "$0")"

# Regenerate the Xcode project from project.yml, sourcing the OAuth client ID
# env vars it needs to fill into Info.plist (see .env.local).
[ -f .env.local ] && . ./.env.local
xcodegen generate

DD="$HOME/Library/Developer/Xcode/DerivedData/GoogleContacts-ios-manual"

DEVICES_JSON="$(mktemp)"
trap 'rm -f "$DEVICES_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null

UDID=$(python3 -c "
import json
with open('$DEVICES_JSON') as f:
    data = json.load(f)
for d in data['result']['devices']:
    hw = d.get('hardwareProperties', {})
    if hw.get('platform') == 'iOS' and hw.get('reality') == 'physical':
        print(d['identifier'])
        break
")

if [ -z "$UDID" ]; then
  echo "No physical iPhone found. Connect it by cable, unlock it, and tap 'Trust This Computer' if prompted, then re-run this script." >&2
  exit 1
fi

xcodebuild -project GoogleContacts.xcodeproj -scheme GoogleContacts_iOS \
  -configuration Debug -destination "platform=iOS,id=$UDID" \
  -allowProvisioningUpdates \
  SYMROOT="$DD/Build/Products" OBJROOT="$DD/Build/Intermediates.noindex" build

APP_PATH=$(find "$DD/Build/Products" -maxdepth 2 -name "GoogleContacts.app" -print -quit)
if [ -z "$APP_PATH" ]; then
  echo "Build succeeded but the .app bundle wasn't found under $DD/Build/Products" >&2
  exit 1
fi

xcrun devicectl device install app --device "$UDID" "$APP_PATH"

echo "Installed. On first launch, if iOS blocks it as an untrusted developer, go to Settings > General > VPN & Device Management, trust the developer certificate, then relaunch the app."
