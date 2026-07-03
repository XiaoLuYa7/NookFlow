# NookFlow

[English](README.md) | [简体中文](README.zh-CN.md)

NookFlow is a lightweight macOS dynamic island app built with SwiftUI and AppKit. It places a compact, notch-aware panel near the menu bar and expands into a focused control surface for music, lyrics, reminders, calendar, weather, files, quick apps, and shortcuts.

The app is designed around native macOS behavior: low idle resource usage, smooth panel transitions, predictable window focus, and clear permission boundaries.

## Features

- Compact and expanded island panel for macOS.
- Music playback display, transport controls, artwork, and synchronized lyrics.
- Desktop lyrics window and notch lyric presentation.
- Calendar, reminders, weather, todo, file staging, quick app launch, and shortcuts modules.
- Settings window for general behavior, notifications, quick apps, and shortcuts.
- SwiftPM regression tests for core parsing and presentation logic.

## Requirements

- macOS 14 or later.
- Xcode 16 or later is recommended.
- Swift 6 toolchain.

Some features require macOS permissions such as Location, Calendar, Reminders, Automation, or Accessibility depending on the module you enable.

## Build And Run

Open the Xcode project:

```sh
open NookFlow.xcodeproj
```

Then select the `NookFlow` scheme and run the app.

You can also run the regression tests with Swift Package Manager:

```sh
swift test
```

## Project Structure

```text
App/              App entry point and application delegate
Panel/            AppKit window and panel controllers
Views/            SwiftUI island, settings, lyrics, and module views
Models/           State, providers, parsing, playback, files, and settings logic
Assets.xcassets/  App icons and bundled visual assets
Tests/            SwiftPM regression tests
TestsSupport/     Test support types
```

## Development Notes

- Keep island updates event-driven and incremental.
- Avoid high-frequency polling for ordinary UI refreshes.
- Cancel tasks, timers, and listeners when panels close or modules become inactive.
- Do not perform file scanning, networking, or large parsing work on the main thread.
- Keep caches bounded and scoped to the feature that owns them.

## License

No license has been added yet.
