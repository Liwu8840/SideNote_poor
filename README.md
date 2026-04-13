# SideNote

SideNote is a native macOS side-panel notebook built with Swift, AppKit, and SwiftUI. It stays docked on the screen edge and gives you three always-available panels for work, development, and life, with lightweight AI inbox support through plain text files.

[中文说明](README.zh.md) | [AI Integration Doc (ZH)](AI_INTEGRATION.zh.md) | [Packaging Guide (ZH)](PACKAGING.zh.md)

## Features

- Three persistent note spaces: `Work`, `Dev`, and `Life`
- Edge panel interaction with quick show/hide behavior
- Weekly archive rollover under `~/Documents/SideNote_Archive`
- Plain-text exports for the current week and per-day slices
- AI inbox files that can append actionable tasks into each panel
- Menu bar control and login-at-startup toggle

## Requirements

- macOS 13 or later
- Swift 6 toolchain / Xcode with Swift Package Manager support

## Build

```bash
swift build
swift run
```

## Packaged App

A prebuilt packaged app archive is included as:

- `SideNote.app.zip`

If you want to rebuild the app bundle yourself, use:

```bash
./package.sh
```

The packaging details are documented in [PACKAGING.zh.md](PACKAGING.zh.md).

## Project Structure

- `Sources/main.swift`: app bootstrap and menu bar lifecycle
- `Sources/SidePanel.swift`: panel UI, note storage, archive logic
- `demo_ai_skill.py`: example script for AI workflow integration

## Data and AI Integration

SideNote stores its working files in:

```text
~/Documents/SideNote_Archive/Current_Week/
```

The app writes weekly plain text files, daily slices, and listens for AI inbox files such as `work_ai_append.txt`, `dev_ai_append.txt`, and `life_ai_append.txt`.

For the full Chinese integration reference, see [AI_INTEGRATION.zh.md](AI_INTEGRATION.zh.md).
