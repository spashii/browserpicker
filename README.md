# Browser Picker

A small macOS app that sits in for your default browser. Click a link anywhere and a panel asks where it should go: which browser, and for Chromium browsers and Firefox, which profile.

Profiles are the point. Brave, Chrome and Firefox keep one login per profile, and no other picker lets you say "work Brave" versus "personal Brave" from the same click.

<img src="Resources/AppIcon.iconset/icon_128x128.png" width="64" alt="">

## Install

With Homebrew:

```sh
brew tap spashii/browserpicker https://github.com/spashii/browserpicker
brew trust spashii/browserpicker
brew install --cask browserpicker
```

Or download `BrowserPicker-<version>.zip` from the [latest release](https://apps.idea2prod.in/browserpicker/download), unzip and move `Browser Picker.app` to `/Applications`.

The app is signed with a Developer ID and notarized by Apple, so it opens on the first try. Open it once. It offers to make itself the default browser and lists everything it found. Requires macOS 13 or later.

## Use

Click a link. The panel shows every browser and profile with a key next to it.

The highlighted row opens after 5 seconds. It's Browser Picker's guess when it has learned where links like this one go, and your default row otherwise. Press any key or move to another row to stop it.

- Press the key, or arrow down and press Return, to open the link there.
- Escape closes the panel without opening anything.
- Command-C copies the link instead of opening it.

Browser Picker learns which browser you pick for which links. For each link you open, it keeps, on your Mac, the time, the link cut down to its site and first two path parts (such as github.com/your-org), the app you clicked it in, and the browser you chose and how. The guess is rebuilt from that file every time, and nothing leaves your Mac. Delete ~/.config/browserpicker/picks.jsonl to start over.

## Updates

Browser Picker checks for updates with [Sparkle](https://sparkle-project.org). It asks before it checks on its own, and Check for Updates in its window looks right away. Update checks and downloads go through apps.idea2prod.in, which counts them by app, version and country and never stores your IP address.

## Configure

Everything lives in `~/.config/browserpicker/config.json`. The app writes it on first run; edit it by hand or through the Edit config button.

```json
{
  "default": "com.brave.Browser#Default",
  "countdown": 5,
  "rules": [
    { "host": "example.com", "target": "com.brave.Browser#Default" },
    { "host": "github.com", "target": "com.google.Chrome#Default" }
  ],
  "targets": [
    { "id": "com.brave.Browser#Default", "name": "Brave · work", "key": "1" },
    { "id": "com.brave.Browser#Profile 1", "key": "2" },
    { "id": "com.google.Chrome#Default", "key": "3", "hidden": true },
    { "id": "com.apple.Safari", "key": "4" }
  ]
}
```

- `targets` order is the panel order. New browsers and profiles are added next to their app.
- `name` renames a row. `key` is the shortcut. `hidden` drops it from the panel.
- `rules` skip the panel for a host and its subdomains. The longest matching host wins.
- `countdown` is how many seconds the highlighted row waits before it opens. 0 turns the countdown off.
- `default` is the row highlighted, and opened when the countdown ends, when there's no sure guess. Without it, the top row.

Target ids are the bundle id, plus `#<profile directory>` for Chromium and Firefox profiles.

## Build from source

Needs the Xcode command line tools and nothing else. The first build downloads Sparkle, pinned to one version and checked against its checksum.

```sh
./install.sh
```

That builds a universal binary into `build/`, signs it ad hoc, copies it to `/Applications` and registers it with Launch Services.

## Release

On a Mac that holds the Developer ID identity, the notary profile and the Sparkle key, with `gh` logged in:

```sh
Tools/release.sh 0.4.0
```

It builds and signs the app, notarizes and staples it, signs the zip for Sparkle, adds it to `site/appcast.xml` and the cask, then publishes the GitHub release and pushes main. The top of the script lists where it looks for each key.
