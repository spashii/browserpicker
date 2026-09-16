#!/usr/bin/env bash
# Builds, installs to /Applications and registers with Launch Services.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
"$root/build.sh"

rm -rf "/Applications/Browser Picker.app"
cp -R "$root/build/Browser Picker.app" /Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
	-f "/Applications/Browser Picker.app"

open "/Applications/Browser Picker.app"
echo "installed. Set it as your default browser in the window that just opened."
