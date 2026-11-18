#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
app="$root/build/Personal Radio Prototype.app"
contents="$app/Contents"
module_cache="${TMPDIR:-/tmp}/personal-radio-prototype-swift-$UID"

mkdir -p "$contents/MacOS" "$contents/Resources" "$module_cache"
cp "$root/Support/macOS-Info.plist" "$contents/Info.plist"
cp -R "$root/Assets/Audio" "$contents/Resources/"

xcrun swiftc \
  -target "$(uname -m)-apple-macosx14.0" \
  -swift-version 6 \
  -module-cache-path "$module_cache" \
  -parse-as-library \
  -O \
  -module-name PersonalRadioPrototype \
  "$root/Sources/PersonalRadioApp.swift" \
  "$root/Sources/PrototypeView.swift" \
  "$root/Sources/PlaybackModel.swift" \
  "$root/Sources/LocalPlaylist.swift" \
  -o "$contents/MacOS/PersonalRadioPrototype"

codesign --force --sign - --timestamp=none "$app"
printf '\nBuilt %s\n' "$app"
