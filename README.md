# T-Utilities

A modular macOS menu bar app (macOS 26+, Apple Silicon) that bundles the small utilities I use every day into one app.
Each module can be turned on/off and reordered in Settings; disabled modules are stopped and released from memory.

> **Personal project.** T-Utilities is built for my own use. It is public in case it helps someone else, but it is provided as is, without support, and features follow my own needs.

| Module | What it does | Based on |
|---|---|---|
| Clipboard | Clipboard history, search, quick slots (⌘1–0), OCR, Quick Look, optional paste-on-Return | [CopyNinja](https://github.com/dwyi84/CopyNinja) |
| Awake | Keep the Mac awake manually or while AI coding agents (Claude, Codex, Cursor, Paseo) work — also with the lid closed | idea from [eclam](https://github.com/jadhvank/eclam) |
| Clock | Second time zone next to the menu bar icon (`NY 00:33`) | — |
| Windows | Maximize, next/previous display, hold ⌥ and drag anywhere to move (right-drag to resize) | [Rectangle](https://github.com/rxhanson/Rectangle), [easy-move-resize](https://github.com/dmarcotte/easy-move-resize) |
| Cable | USB-C port, cable and charger diagnostics | [WhatCable](https://github.com/darrylmorley/whatcable) |
| Mouse | Pointer speed/acceleration, side buttons → Mission Control / Show Desktop, wheel reverse/linear, Logitech battery (HID++) | [LinearMouse](https://github.com/linearmouse/linearmouse) |
| Dictionary | Global hotkey (⌥⌘Space) opens a small Naver / Daum dictionary panel (⌘1 / ⌘2 to switch); off by default | idea from [allkdic](https://github.com/devxoul/allkdic) |

Install: `brew install --cask mordol/tap/t-utilities`, or see [INSTALL.md](INSTALL.md). Plan and design notes: [PLAN.md](PLAN.md).

## Resource usage

Measured on 2026-10-20 on a MacBook Pro (M5 Max, macOS 27.0.1). The build was a Release build of v0.1.2 plus the on-demand Cable refresh. The app was idle, and each value is the median of three 120 s runs ([Scripts/measure.sh](Scripts/measure.sh)).

| Configuration | Memory (phys_footprint) | CPU (average) |
|---|---|---|
| No modules | 12–13 MB | ~0 % |
| One module | 13–15 MB | ≤ 0.02 % |
| All six modules | 16 MB | ~0.1 % |

In use, memory grows once and then stays flat. The first time you open the popover adds about 30 MB, Settings about 19 MB, and the first OCR about 17 MB, which is SwiftUI/AppKit and Vision setup. With every feature used once, the app settles around 80 MB, and repeating those actions adds nothing. `leaks` reports only about 20 KB, all in a system XPC connection, none in the app's own code. Short spikes are expected:

- OCR uses about 250 MB for 1–2 s.
- Showing a popover or window adds about 200 MB of macOS-owned graphics memory for about 1 s with three displays. Finder shows the same spike.

Details: [Docs/OPTIMIZATION.md](Docs/OPTIMIZATION.md).

## Build

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project T-Utilities.xcodeproj -scheme T-Utilities -configuration Release build
```

Builds are signed with a self-signed certificate named "T-Utilities Dev" so macOS permissions survive updates.

## License

MIT — see [LICENSE](LICENSE). Third-party code and licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
