# Installing T-Utilities

T-Utilities is signed with a personal certificate, not an Apple Developer ID, so macOS needs one extra step the first time.

Requirements: macOS 26 or later, Apple Silicon.

## Homebrew (recommended)

```sh
brew install --cask mordol/tap/t-utilities
```

Homebrew installs to `/Applications` and clears the quarantine flag, so you can skip steps 1–3 below and go straight to step 4.
Uninstall with `brew uninstall --cask t-utilities` (add `--zap` to also delete settings and clipboard history).

## Manual

1. Download `T-Utilities-x.y.z.zip` from the [latest release](https://github.com/mordol/T-Utilities/releases/latest) and unzip it.
2. Move `T-Utilities.app` to `/Applications`.
3. Remove the download quarantine flag (Terminal):
   ```sh
   xattr -dr com.apple.quarantine /Applications/T-Utilities.app
   ```
4. Open T-Utilities. A cup icon appears in the menu bar; left-click opens the panel, right-click the quick menu.
5. Grant permissions when asked (System Settings → Privacy & Security):
   - **Accessibility** — Clipboard paste-on-Return and the Windows module (Maximize, move between displays).
   The Settings → 권한 page shows what is missing.

## Updates

T-Utilities checks GitHub once a day. When a new version exists, an "업데이트" button appears in the panel footer and in Settings → 일반.
Clicking it downloads the release, verifies it is signed by the same certificate, replaces the app and relaunches.
Permissions you granted stay valid because the signing certificate does not change.

## Uninstall

Quit T-Utilities, delete the app, and optionally remove its data:
```sh
rm -rf ~/Library/Application\ Support/T-Utilities
defaults delete com.taegyu.tutilities
```
