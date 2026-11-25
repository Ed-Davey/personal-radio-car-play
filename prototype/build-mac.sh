#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
app="$root/build/Personal Radio Prototype.app"
preview_audio=
if [[ $# -ne 0 ]]; then
  if [[ $# -ne 2 || "$1" != "--presenter-preview" || ! -f "$2" || ! -r "$2" ]]; then
    printf '%s\n' 'Usage: build-mac.sh [--presenter-preview <prepared WAV>]' >&2
    exit 2
  fi
  preview_audio=$2
  mkdir -p "$root/build"
  preview_directory=$(mktemp -d "$root/build/presenter-preview.XXXXXX")
  trap 'rm -rf -- "$preview_directory"' EXIT
  app="$preview_directory/Personal Radio Presenter Preview.app"
fi
contents="$app/Contents"
module_cache="${TMPDIR:-/tmp}/personal-radio-prototype-swift-$UID"

mkdir -p "$contents/MacOS" "$contents/Resources" "$module_cache"
cp "$root/Support/macOS-Info.plist" "$contents/Info.plist"
cp -R "$root/Assets/Audio" "$contents/Resources/"
if [[ -n "$preview_audio" ]]; then
  cp -- "$preview_audio" "$contents/Resources/Audio/intro-1.wav"
  plutil -replace CFBundleIdentifier -string local.personalradio.presenter-preview "$contents/Info.plist"
  plutil -replace CFBundleName -string 'Personal Radio Presenter Preview' "$contents/Info.plist"
  plutil -replace CFBundleDisplayName -string 'Personal Radio Presenter Preview' "$contents/Info.plist"
fi

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
trap - EXIT
printf '\nBuilt %s\n' "$app"
if [[ -n "$preview_audio" ]]; then
  printf 'Open the preview with:\nopen -n %q\n' "$app"
fi
