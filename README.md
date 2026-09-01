# QuickTab

**Window-level Command-Tab for macOS.**

[![Download QuickTab](https://img.shields.io/badge/Download_QuickTab-macOS_14%2B-6EE7D8?style=for-the-badge&logo=apple&logoColor=17131F)](https://github.com/jamesqquick/QuickTab/releases/latest/download/QuickTab.dmg)

[Latest release](https://github.com/jamesqquick/QuickTab/releases/latest) | [All releases](https://github.com/jamesqquick/QuickTab/releases)

QuickTab is a native macOS window switcher built for fast, deterministic keyboard navigation. It replaces app-level switching with individual windows, adds fuzzy search and learned shortcuts, and keeps window controls close to the keyboard.

## Install

1. [Download the latest DMG](https://github.com/jamesqquick/QuickTab/releases/latest/download/QuickTab.dmg).
2. Open `QuickTab.dmg` and drag QuickTab into Applications.
3. Open QuickTab from Applications.
4. Grant access in **System Settings > Privacy & Security > Accessibility**, then relaunch QuickTab.

QuickTab is Developer ID-signed and notarized by Apple.

## Features

- Switch between individual windows with Command-Tab, ordered by recent use.
- Search window and app names with non-consecutive fuzzy matching.
- Learn short queries for results you choose frequently.
- Hold Right Option, Left Option, or Fn to search, then release to switch.
- Cycle through the active application's windows with Command-Backtick.
- Close, minimize, hide, or quit directly from the switcher.
- Reveal an auto-hiding window sidebar from either screen edge.
- Show the switcher and sidebar independently on connected displays.
- Control how minimized windows and hidden applications are ordered or omitted.
- Exclude applications from the switcher.
- Launch automatically at login.
- Stay local with no analytics, network calls, or third-party dependencies.

## Controls

| Control | Action |
| --- | --- |
| `Control-Space` | Search windows |
| `Command-Tab` | Cycle through recent windows |
| `Command-Backtick` | Cycle through the active application's windows |
| Hold the configured modifier and type | Fast Search; release to switch |
| Arrow keys, `J`, or `K` | Move selection |
| Return | Switch to the selected window |
| Escape | Cancel |
| `Command-W` | Close the selected window |
| `Command-M` | Minimize the selected window |
| `Command-H` | Hide the selected application |
| `Command-Q` | Quit the selected application |

Shortcuts and display behavior can be changed from the QuickTab menu bar icon.

## Requirements

- macOS 14 Sonoma or newer
- Apple Silicon or Intel Mac
- Accessibility permission

QuickTab uses public Accessibility and Core Graphics APIs. macOS does not expose Space identifiers through a supported public API, so QuickTab retains discovered windows while they remain valid rather than relying on private Space APIs.

## Build from source

Building QuickTab requires Xcode 16 or newer.

```bash
git clone https://github.com/jamesqquick/QuickTab.git
cd QuickTab
swift test
./scripts/build-app.sh
open .build/QuickTab.app
```

The default build is ad-hoc signed for local development.

## Create a release build

Provide a Developer ID Application identity to build and package `QuickTab.dmg`:

```bash
QUICKTAB_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./scripts/package-release.sh
```

To notarize the app and DMG, also provide a `notarytool` keychain profile:

```bash
QUICKTAB_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
QUICKTAB_NOTARY_PROFILE="your-notary-profile" \
./scripts/package-release.sh
```

## License

QuickTab is available under the [MIT License](LICENSE).
