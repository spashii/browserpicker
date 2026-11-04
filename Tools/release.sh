#!/usr/bin/env bash
# Makes a release: Tools/release.sh 0.4.0
#
# Runs on a Mac that holds the Developer ID identity, the notary profile and the Sparkle key.
# Builds and signs the app, notarizes and staples it, signs the zip for Sparkle, adds it to
# the appcast, points the cask at it and commits that. Then Tools/publish.sh tags it, creates
# the GitHub release and pushes main. PUBLISH=0 stops after the commit, before anything
# leaves this machine.
#
# Where it looks, each overridable from the environment:
#   IDENTITY        Developer ID Application certificate name
#   KEYCHAIN        keychain holding it, unlocked with KEYCHAIN_PASSWORD_FILE when that exists
#   NOTARY_PROFILE  notarytool keychain profile, stored in KEYCHAIN
#   SPARKLE_KEY     Sparkle EdDSA private key file
set -euo pipefail

version="${1:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"
identity="${IDENTITY:-Developer ID Application: Sameer Pashikanti (JMCP69LCSU)}"
keychain="${KEYCHAIN:-$HOME/Library/Keychains/blend-release.keychain-db}"
keychain_password_file="${KEYCHAIN_PASSWORD_FILE:-$HOME/.blend-signing/keychain-password}"
profile="${NOTARY_PROFILE:-blend-notary}"
ed_key="${SPARKLE_KEY:-$HOME/.blend-signing/sparkle-private-key}"

die() { echo "release: $*" >&2; exit 1; }

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: Tools/release.sh <version>, for example 0.4.0"
cd "$root"
git diff --quiet && git diff --cached --quiet || die "commit or stash your changes first"
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "release from main"
git fetch --quiet origin main
git merge-base --is-ancestor origin/main HEAD || die "main is behind origin/main, pull first"
git rev-parse -q --verify "refs/tags/v$version" >/dev/null && die "tag v$version already exists"
remote=0; git ls-remote --exit-code --tags origin "v$version" >/dev/null || remote=$?
[ "$remote" = 2 ] || die "tag v$version is already on origin, or origin is unreachable"
grep -qF "<sparkle:version>$version</sparkle:version>" site/appcast.xml && die "appcast already lists $version"
[ -r "$ed_key" ] || die "no Sparkle key at $ed_key"
if [ "${PUBLISH:-1}" != 0 ]; then
	gh auth status >/dev/null 2>&1 || die "gh is not logged in, so it could not publish (PUBLISH=0 builds only)"
fi

if [ -r "$keychain_password_file" ]; then
	security unlock-keychain -p "$(cat "$keychain_password_file")" "$keychain"
fi
identities="$(security find-identity -v -p codesigning "$keychain")"
[[ "$identities" == *"\"$identity\""* ]] || die "no valid \"$identity\" in $keychain (is it unlocked?)"

app="$root/build/Browser Picker.app"
zip="$root/build/BrowserPicker-$version.zip"
sparkle_bin="$root/build/sparkle-$(sed -n 's/^sparkle_version=//p' build.sh)/bin"

# Until the release commit exists, a failure puts the files it edits back as they were.
committed=0
trap '[ "$committed" = 1 ] || git checkout -q -- Resources/Info.plist site/appcast.xml Casks/browserpicker.rb' EXIT

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" Resources/Info.plist
IDENTITY="$identity" KEYCHAIN="$keychain" "$root/build.sh"

codesign --verify --deep --strict "$app" || die "signature does not verify"
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)"
[[ "$entitlements" != *get-task-allow* ]] || die "the app carries get-task-allow, which notarization rejects"

# Notarize a zip of the app, staple the ticket to the app itself, then zip again so the
# download carries the ticket and opens offline.
rm -f "$zip" "$root/build/notarize.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$root/build/notarize.zip"
echo "notarizing, which usually takes a few minutes"
xcrun notarytool submit "$root/build/notarize.zip" --keychain-profile "$profile" --keychain "$keychain" \
	--wait --output-format json >"$root/build/notarize.json" || die "notarytool could not submit"
status="$(plutil -extract status raw -o - "$root/build/notarize.json")"
if [ "$status" != Accepted ]; then
	id="$(plutil -extract id raw -o - "$root/build/notarize.json" || true)"
	[ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$profile" --keychain "$keychain" >&2
	die "notarization came back $status"
fi
rm "$root/build/notarize.zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
assessment="$(spctl -a -vv "$app" 2>&1)" || die "Gatekeeper rejects it: $assessment"
echo "$assessment"
[[ "$assessment" == *"Notarized Developer ID"* ]] || die "Gatekeeper does not see it as notarized"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

# Sparkle checks this EdDSA signature against SUPublicEDKey before it installs anything.
enclosure="$("$sparkle_bin/sign_update" --ed-key-file "$ed_key" "$zip")"
signature="$(sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/' <<<"$enclosure")"
"$sparkle_bin/sign_update" --verify --ed-key-file "$ed_key" "$zip" "$signature" \
	|| die "the Sparkle signature does not verify"
sha256="$(shasum -a 256 "$zip" | cut -d' ' -f1)"

# Newest first, directly under the marker in site/appcast.xml.
url="https://github.com/spashii/browserpicker/releases/download/v$version/BrowserPicker-$version.zip"
item="$(mktemp)"
cat >"$item" <<EOF
    <item>
      <title>Version $version</title>
      <link>https://github.com/spashii/browserpicker/releases/tag/v$version</link>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="$url" $enclosure type="application/octet-stream"/>
    </item>
EOF
marker="<!-- Tools/release.sh adds each release below this line, newest first. -->"
grep -qF "$marker" site/appcast.xml || die "site/appcast.xml lost its marker line"
awk -v marker="$marker" -v item="$item" \
	'{ print } index($0, marker) { while ((getline line < item) > 0) print line }' \
	site/appcast.xml >site/appcast.xml.new
mv site/appcast.xml.new site/appcast.xml
rm "$item"
xmllint --noout site/appcast.xml || die "site/appcast.xml is no longer valid XML"

sed -i '' -e "s/^  version \".*\"/  version \"$version\"/" \
	-e "s/^  sha256 \".*\"/  sha256 \"$sha256\"/" Casks/browserpicker.rb

git add Resources/Info.plist site/appcast.xml Casks/browserpicker.rb
git commit -q -m "release v$version"
committed=1
echo "committed release v$version: $zip ($sha256)"

if [ "${PUBLISH:-1}" != 0 ]; then
	"$root/Tools/publish.sh" "$version"
else
	echo "PUBLISH=0: stopped before publishing. Run Tools/publish.sh $version with the zip in build/."
fi
