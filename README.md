<img src="./.github/logo.png" width="80" />

# TinyHand

[![Latest release](https://img.shields.io/github/v/release/nilbuild/tinyhand?display_name=tag&sort=semver&cacheSeconds=3600)](https://github.com/nilbuild/tinyhand/releases/latest)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey)](https://tinyhand.app)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

A tiny hand on a stick that points at things on your Mac screen.

<img src="./.github/banner.jpg" alt="TinyHand: a tiny hand for your Mac" />

[![Download for macOS](https://img.shields.io/badge/Download_for_macOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/nilbuild/tinyhand/releases/latest/download/TinyHand.dmg)
[![Visit website](https://img.shields.io/badge/Visit_website-ffffff?style=for-the-badge&logo=safari&logoColor=black)](https://tinyhand.app)

macOS 13 or later, Apple Silicon and Intel.

## Install

Open `TinyHand.dmg`, drag TinyHand to Applications and allow **Accessibility** when asked. It needs that to turn your clicks into taps. TinyHand updates itself.

## Use

| | |
|---|---|
| Click the menu bar icon, or **⌃⌥H** | Turn the pointer on or off |
| Right-click the menu bar icon | Menu and Settings |
| Click | Tap (nothing underneath gets clicked) |
| Hold and drag | Draw on the screen |
| Hold **⌘** while drawing | Add an arrowhead to the end of the line |
| Hold **⌃⇧** and a gesture's key | Show that gesture while held, on hands that have gestures. Line art has a middle finger (**M**), an OK (**O**) and a shaka (**S**). Settings › Pointers › Gestures adds gestures to your own hands, on the key you pick |
| **⌃⌥X** | Clear the drawing |
| **Esc** | Clear everything and turn the pointer off |

While the pointer is on, a small toolbar at the bottom of the screen lets you pick one of
37 hands or a laser dot, mute the tap sound, or exit. A hand with gestures has a small number
badge: hover over it to see its gestures and their shortcuts.

## Automation

Launchers like Raycast or Alfred, and shell scripts, can control TinyHand with
`tinyhand://` links. Use `open -g` so TinyHand doesn't take focus:

```sh
open -g tinyhand://toggle
```

| Link | Action |
|---|---|
| `tinyhand://on`, `tinyhand://off`, `tinyhand://toggle` | Turn the pointer on, off, or flip it |
| `tinyhand://clear` | Clear the drawing |
| `tinyhand://style/<id>` | Switch to a hand (or `laser`) and turn the pointer on |
| `tinyhand://sound/on`, `/off`, `/toggle` | Tap sound for the current pointer |

While TinyHand runs, it keeps its current state in
`~/Library/Application Support/TinyHand/state.json`: whether the pointer is on, the
selected style, whether sound is on, and every style with its `id`, name and type
(`hand`, `custom` or `laser`). The file is removed when TinyHand quits. It also
records the app's `pid`, so a file left behind by a crash can be detected.

If TinyHand isn't running, opening any link launches it and then runs the command.

## Develop

Run the tests (they work with Xcode or with only the Command Line Tools installed):

```sh
scripts/test.sh
```

To try a branch without touching your own TinyHand, quit TinyHand and install a preview:

```sh
scripts/preview.sh install     # builds "TinyHand Preview" into dist/ and opens it
scripts/preview.sh uninstall   # removes it, its settings and its Accessibility permission
```

A hand's gestures are pictures named after the hand, then one letter or digit, which is the
gesture's key: `hand_line_s.webp` is Line art's ⌃⇧S. Gestures have keys, not names: the picture
shows what each one is. To make one from a picture of the gesture on a transparent background,
sitting on the hand's own stick:

```sh
swift build && .build/debug/TinyHand --make-gesture assets/hand_line.webp shaka.png /tmp/hand_line_s.png
cwebp -lossless /tmp/hand_line_s.png -o assets/hand_line_s.webp
```

Built-in pictures ship as WebP, and TinyHand looks for a WebP before a PNG of the same name,
so a PNG beside an existing WebP never shows.

The preview has its own name and settings, can't update itself, and leaves `tinyhand://`
links to your own TinyHand. It backs up `~/Library/Application Support/TinyHand` when it
installs and puts it back when it uninstalls.

## License

MIT. See [LICENSE](LICENSE).
