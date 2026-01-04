# Ticklet

Ticklet is a lightweight macOS menu bar app that logs the frontmost app and focused window title into daily CSV files so you can answer: "What apps and windows did I spend my time on today, and for how long?"

This repository follows the project spec in `.github/copilot-instructions.md.md`.

## Build & Run

Requires macOS 12+ and Swift 5.7+. You can build with SwiftPM or open in Xcode (recommended for AppKit apps).

- Build with SwiftPM: `swift build`
- Run in Xcode: open the folder in Xcode and run the `Ticklet` executable target (use a macOS scheme)
- Run tests locally: `swift test` (CI runs tests on macOS runners)

⚠️ Accessibility permission: To read window titles you must grant Accessibility permission to the built app in System Settings → Privacy & Security → Accessibility. If the app has no permission, Ticklet will still run but window titles may be empty or truncated.

Debugging as a `.app` bundle (recommended when testing permissions)

If you run the raw executable from Xcode or from SwiftPM's build dir, macOS may not persist Accessibility permissions because the process has no bundle identifier. You can create a minimal `.app` wrapper around the built executable to make permission grants reliable.

- A helper script is included: `scripts/make_app_bundle.sh`
- Example usage:

  ```bash
  # build your executable
  swift build

  # make an app wrapper (adjust paths as needed)
  ./scripts/make_app_bundle.sh .build/x86_64-apple-macosx/debug/Ticklet ./Ticklet.app com.thomas.Ticklet

  # double-click ./Ticklet.app, then add it in System Settings → Privacy & Security → Accessibility
  ```

This avoids the "no bundle identifier" issue when granting Accessibility permissions.

App bundle & UI mode

Ticklet now runs as a regular macOS app (Dock + app menu) and also provides an optional status item in the menu bar. Use the Preferences window (App menu → Preferences…) to toggle whether the status item is shown in the menu bar. This mode is recommended for development and production so Accessibility permissions behave correctly.

## Packaging & Release

- Build a Release configuration in Xcode and export a signed `.app` or `.dmg`.
- Code sign with your Developer ID when creating distributable builds.
- Recommended distribution: GitHub Releases with a signed `.dmg` attached (include SHA256 checksum and release notes).

For a reproducible release, prefer building on an ARM and Intel machine or build universal binary with `lipo`/`xcodebuild` to combine slices.

## Current status

- Project scaffold created
- Core model (`ActivityEntry`) and `CSVLogger` implemented
- `ActivityTracker` stub created (AX and idle logic to be implemented)
- Basic unit tests added for CSV escaping and duration

Next: implement the accessibility polling, debouncing and idle detection, wire the tracker to the CSVLogger, add menu bar UI and a log viewer window.
