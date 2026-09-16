#!/usr/bin/env bash
# Builds Browser Picker.app into ./build as a universal binary.
# Needs the Xcode command line tools, nothing else.
# VERSION stamps the bundle (defaults to the value already in Info.plist).
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/build/Browser Picker.app"
macos="$app/Contents/MacOS"

rm -rf "$app"
mkdir -p "$macos" "$app/Contents/Resources"

# Two thin builds and lipo, so one zip serves Apple silicon and Intel alike.
for arch in arm64 x86_64; do
	swiftc -swift-version 5 -O -target "$arch-apple-macos13.0" \
		-o "$macos/BrowserPicker-$arch" "$root"/Sources/*.swift
done
lipo -create -output "$macos/BrowserPicker" "$macos"/BrowserPicker-{arm64,x86_64}
rm "$macos"/BrowserPicker-{arm64,x86_64}

cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$app/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$app/Contents/Info.plist"
fi

if [ -d "$root/Resources/AppIcon.iconset" ]; then
	iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" "$root/Resources/AppIcon.iconset"
fi

# Ad-hoc signature: no Developer ID, so Gatekeeper needs the quarantine flag cleared
# on first launch. The README and the Homebrew cask both handle that.
codesign --force --sign - "$app"
echo "built $app"
