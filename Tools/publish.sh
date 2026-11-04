#!/usr/bin/env bash
# Publishes a release that Tools/release.sh committed: Tools/publish.sh 0.4.0
#
# Tags the release commit, creates the GitHub release with the notarized zip, then pushes
# main, which deploys the appcast. The download goes up before the appcast, so Sparkle never
# offers a zip that is not there yet. Needs gh logged in and build/BrowserPicker-<version>.zip.
set -euo pipefail

version="${1:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"

die() { echo "publish: $*" >&2; exit 1; }

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: Tools/publish.sh <version>, for example 0.4.0"
cd "$root"
zip="build/BrowserPicker-$version.zip"
[ -f "$zip" ] || die "no $zip, run Tools/release.sh $version first"
[ "$(git log -1 --format=%s)" = "release v$version" ] || die "HEAD is not the release v$version commit"
sha256="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
grep -qF "sha256 \"$sha256\"" Casks/browserpicker.rb || die "the cask does not match $zip"
gh auth status >/dev/null 2>&1 || die "gh is not logged in"

git rev-parse -q --verify "refs/tags/v$version" >/dev/null || git tag "v$version"
[ "$(git rev-parse "v$version^{commit}")" = "$(git rev-parse HEAD)" ] || die "tag v$version is not on HEAD"
git push origin "refs/tags/v$version"
gh release create "v$version" "$zip" --repo spashii/browserpicker \
	--title "v$version" --generate-notes --verify-tag
git push origin HEAD:main
echo "published https://github.com/spashii/browserpicker/releases/tag/v$version"
