# T-Utilities

A modular macOS menu bar app (macOS 26+, Apple Silicon) that bundles the small utilities I use every day into one app.
Each module can be turned on/off and reordered in Settings; disabled modules are stopped and released from memory.

| Module | What it does | Based on |
|---|---|---|
| Clipboard | Clipboard history, search, quick slots (⌘1–0), OCR, Quick Look, optional paste-on-Return | [CopyNinja](https://github.com/dwyi84/CopyNinja) |
| Awake | Keep the Mac awake manually or while AI coding agents (Claude, Codex, Cursor, Paseo) work — also with the lid closed | idea from [eclam](https://github.com/jadhvank/eclam) |
| Clock | Second time zone next to the menu bar icon (`NY 00:33`) | — |
| Windows | Maximize, next/previous display | [Rectangle](https://github.com/rxhanson/Rectangle) |
| Cable | USB-C port, cable and charger diagnostics | [WhatCable](https://github.com/darrylmorley/whatcable) |

Install: `brew install --cask mordol/tap/t-utilities`, or see [INSTALL.md](INSTALL.md). Plan and design notes: [PLAN.md](PLAN.md).

## Build

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project T-Utilities.xcodeproj -scheme T-Utilities -configuration Release build
```

Builds are signed with a self-signed certificate named "T-Utilities Dev" so macOS permissions survive updates.

## License

MIT — see [LICENSE](LICENSE). Third-party code and licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
