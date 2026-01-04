# Development Guide

This document contains developer-oriented instructions for building, testing, packaging, and contributing to Ticklet.

## Quick start

- Requires: Swift 6.0+, macOS 15.0+ (Big Sur+ compatibility not guaranteed).
- Clone the repo and build:

  - Build (debug):
    ```bash
    swift build
    ```
  - Build (release):
    ```bash
    swift build -c release
    ```
  - Run the app from source:
    ```bash
    swift run
    ```

## Tests

- Run unit tests:

  ```bash
  swift test
  ```

Tests cover CSV logging behavior (reads, writes, append semantics) and core manager/trackers. If you add file-based tests, prefer temporary directories (`FileManager.default.temporaryDirectory`) so tests remain hermetic.

## Packaging and local installation

- Create an `.app` wrapper (helper script included):

  ```bash
  ./scripts/make_app_bundle.sh --binary .build/release/Ticklet --out ./Ticklet.app
  ```

- Install to /Applications (for testing):

  ```bash
  sudo cp -R ./Ticklet.app /Applications/
  xattr -d com.apple.quarantine /Applications/Ticklet.app || true
  codesign --force --deep --sign - /Applications/Ticklet.app
  ```

Notes:

- The script will add `CFBundleIconFile` to the Info.plist if an `.icns` is present in `Assets/`.
- Don't commit binary icons to the repo without maintainers' consent; keep them local or add via releases.

## Accessibility & Debugging

- Ticklet uses Accessibility APIs to read window titles. Grant permission via System Settings → Privacy & Security → Accessibility.
- If permission doesn't appear, open the `.app` from Finder once to register it with LaunchServices, then add it to Accessibility.
- Logs are written to: `~/Library/Logs/Ticklet/` (one CSV per date).

## CI and platform targets

- CI is configured to target macOS 15 and Swift 6.0. If you change the platform or Swift language version, update `.github/workflows/ci.yml` and `Package.swift` accordingly.

## Contributing

- Fork & open a PR. Keep changes focused and tests green.
- Avoid committing large binary files; use Releases for app bundles and icons.
- If your change affects privacy or logging behavior (redaction, retention, compacting), describe the privacy rationale in the PR.

## Release and notarization (maintainer notes)

- For releases, sign the app with a Developer ID certificate and submit for notarization.
- Ensure privacy-sensitive features are documented and that opt-in/opt-out UX is in place before shipping.

## Code style & formatting

- Follow Swift API design guidelines and prefer value types where appropriate.
- Run `swiftformat` or your preferred formatter if available. Keep tests and CI green.

## Notes & troubleshooting

- If you see CSV data loss during local testing, verify that `CSVLogger.append` semantics are used (append-on-write) and that no external merge/replace logic overwrote files.
- There are existing main-actor warnings; please mark UI-facing methods `@MainActor` or use `MainActor.run {}` where appropriate.

---

If you'd like additions (CI matrix, release checklist, or contributor checklist), tell me what to include and I'll add it here.
