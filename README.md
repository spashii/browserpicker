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

The cask clears the quarantine flag for you, so the app opens on the first try.

Or download `BrowserPicker-<version>.zip` from the [latest release](https://github.com/spashii/browserpicker/releases/latest), unzip, move `Browser Picker.app` to `/Applications`, then clear the quarantine flag once. The app is signed ad hoc, not notarised, so macOS would otherwise refuse to open it:

```sh
xattr -dr com.apple.quarantine "/Applications/Browser Picker.app"
```

Open the app once. It offers to make itself the default browser and lists everything it found. Requires macOS 13 or later.

## Use

Click a link. The panel shows every browser and profile with a key next to it, with one row already highlighted: where it thinks the link goes. A bar drains under that row and the link opens there after five seconds.

- Press the key, or arrow down and press Return, to open the link there.
- Any key, or moving to another row, stops the countdown and the panel waits for you.
- Escape closes the panel without opening anything.
- Command-C copies the link instead of opening it.

The guess is learned from your own picks: the host, its parent domains, the first two path segments (so `github.com/<org>` can go to a different profile than `github.com/<other-org>`), the words in the link and the app you clicked it in. What you picked last at the most specific matching place counts most. When it is unsure it highlights your `default`, or the top row.

Every pick is appended to `~/.config/browserpicker/picks.jsonl`, and the guess is relearned from that file on every link. There is no model file. Delete the log to start over.

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
- `default` is highlighted when the guess is unsure. Without it, the top row.
- `countdown` is the seconds before the highlighted row opens by itself. `0` turns it off.

Target ids are the bundle id, plus `#<profile directory>` for Chromium and Firefox profiles.

## Build from source

Needs the Xcode command line tools and nothing else.

```sh
./install.sh
```

That builds a universal binary into `build/`, copies it to `/Applications` and registers it with Launch Services.

`Tools/ModelCheck.swift` checks the guessing model without the app: its behaviour cases, and a replay of a `picks.jsonl` that counts how often the countdown would have opened the wrong place. The header has the commands.

## Release

Push a tag and CI does the rest:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

The workflow builds the app, uploads the zip to a GitHub release, and commits the new version and checksum into the Homebrew cask.
