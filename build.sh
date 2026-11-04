#!/usr/bin/env bash
# Builds Browser Picker.app into ./build as a universal binary.
# Needs the Xcode command line tools, nothing else: the first build downloads Sparkle.
# VERSION stamps the bundle (defaults to the value already in Info.plist).
# IDENTITY signs with that Developer ID and the hardened runtime, ready for notarization,
# and KEYCHAIN names the keychain holding it. Without IDENTITY the build is signed ad hoc.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/build/Browser Picker.app"
contents="$app/Contents"
macos="$contents/MacOS"

# Sparkle, pinned to one release and checked against the checksum GitHub publishes for it.
sparkle_version=2.10.1
sparkle_sha256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
sparkle="$root/build/sparkle-$sparkle_version"
if [ ! -d "$sparkle/Sparkle.framework" ]; then
	mkdir -p "$root/build"
	tarball="$root/build/Sparkle-$sparkle_version.tar.xz"
	curl -fsSL -o "$tarball" \
		"https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz"
	echo "$sparkle_sha256  $tarball" | shasum -a 256 -c - >/dev/null
	rm -rf "$sparkle.partial" && mkdir "$sparkle.partial"
	tar -xJf "$tarball" -C "$sparkle.partial"
	mv "$sparkle.partial" "$sparkle"
	rm "$tarball"
fi

rm -rf "$app"
mkdir -p "$macos" "$contents/Resources" "$contents/Frameworks"

# Two thin builds and lipo, so one zip serves Apple silicon and Intel alike.
for arch in arm64 x86_64; do
	swiftc -swift-version 5 -O -target "$arch-apple-macos13.0" \
		-F "$sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
		-o "$macos/BrowserPicker-$arch" "$root"/Sources/*.swift
done
lipo -create -output "$macos/BrowserPicker" "$macos"/BrowserPicker-{arm64,x86_64}
rm "$macos"/BrowserPicker-{arm64,x86_64}

ditto "$sparkle/Sparkle.framework" "$contents/Frameworks/Sparkle.framework"

cp "$root/Resources/Info.plist" "$contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$contents/Info.plist"
fi

if [ -d "$root/Resources/AppIcon.iconset" ]; then
	iconutil -c icns -o "$contents/Resources/AppIcon.icns" "$root/Resources/AppIcon.iconset"
fi

if [ -n "${IDENTITY:-}" ]; then
	# Inside out, in the order Sparkle documents for apps outside the sandbox. Notarization
	# wants the hardened runtime and a secure timestamp on every piece of code.
	sign=(codesign --force --sign "$IDENTITY" --options runtime --timestamp)
	if [ -n "${KEYCHAIN:-}" ]; then sign+=(--keychain "$KEYCHAIN"); fi
	framework="$contents/Frameworks/Sparkle.framework"
	"${sign[@]}" "$framework/Versions/B/XPCServices/Installer.xpc"
	"${sign[@]}" --preserve-metadata=entitlements "$framework/Versions/B/XPCServices/Downloader.xpc"
	"${sign[@]}" "$framework/Versions/B/Autoupdate"
	"${sign[@]}" "$framework/Versions/B/Updater.app"
	"${sign[@]}" "$framework"
	"${sign[@]}" "$app"
else
	# Ad hoc: fine to run on the machine that built it. Releases go through Tools/release.sh.
	codesign --force --sign - "$app"
fi
echo "built $app"
