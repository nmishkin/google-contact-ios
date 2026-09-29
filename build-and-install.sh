#!/bin/sh
set -eu

cd "$(dirname "$0")"

# Regenerate the Xcode project from project.yml, sourcing the OAuth client ID
# env vars it needs to fill into Info.plist (see .env.local).
[ -f .env.local ] && . ./.env.local
xcodegen generate

# Route build output through Xcode's DerivedData instead of a project-local
# build/ folder. Without this, a module-map generation bug in this
# Xcode/SDK version causes the build to fail with
# "module map file ... not found".
DD="$HOME/Library/Developer/Xcode/DerivedData/GoogleContacts-manual"

xcodebuild -project GoogleContacts.xcodeproj -target GoogleContacts_macOS \
  -configuration Release ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  SYMROOT="$DD/Build/Products" OBJROOT="$DD/Build/Intermediates.noindex" build

cp -R "$DD/Build/Products/Release/GoogleContacts.app" /Applications/
