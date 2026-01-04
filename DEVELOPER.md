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
  # build for the current host arch (x86_64 or arm64)
  swift build -c release --build-path .build-<arch>
  ./scripts/make_app_bundle.sh .build-<arch>/release/Ticklet ./artifacts/Ticklet-<arch>.app com.thomas.Ticklet
  ```

- Example: locally building an Intel release on an Intel Mac:

  ```bash
  swift build -c release --build-path .build-x86
  ./scripts/make_app_bundle.sh .build-x86/release/Ticklet ./artifacts/Ticklet-x86_64.app com.thomas.Ticklet
  ditto -c -k --sequesterRsrc --keepParent ./artifacts/Ticklet-x86_64.app ./artifacts/Ticklet-x86_64.zip
  ```

- Install to /Applications (for testing):

  ```bash
  sudo cp -R ./artifacts/Ticklet-x86_64.app /Applications/
  xattr -d com.apple.quarantine /Applications/Ticklet-x86_64.app || true
  codesign --force --deep --sign - /Applications/Ticklet-x86_64.app
  ```

Notes:

- The script will add `CFBundleIconFile` to the Info.plist if an `.icns` is present in `Assets/`.
- Don't commit binary icons or build artifacts to the repo; use `artifacts/` for temporary local zips (and keep it in `.gitignore`).
- We provide a GitHub Actions workflow `/.github/workflows/release.yml` that can build per-arch artifacts and create a draft GitHub Release (it builds per-arch when appropriate runners are available and uploads per-arch zips as artifacts).
- To provide both Intel and Apple Silicon binaries, build on a machine of the respective architecture (or use CI runners for each arch). You can then create a universal binary with `lipo` by combining two single-arch binaries, if desired.

## Icon verification

- Verify `.icns` contents and sizes:

  ```bash
  # extract iconset
  iconutil -c iconset Assets/AppIcon.icns -o /tmp/AppIcon.iconset
  ls -la /tmp/AppIcon.iconset

  # regenerate clean icns from iconset
  iconutil -c icns /tmp/AppIcon.iconset -o Assets/AppIcon.regenerated.icns
  ```

- Make sure `Assets/AppIcon.icns` contains the standard sizes (16, 32, 128, 256, 512 + @2x retina variants). If not, add missing sizes or replace with a complete icns set.

## Accessibility & Debugging

- Ticklet uses Accessibility APIs to read window titles. Grant permission via System Settings → Privacy & Security → Accessibility.
- If permission doesn't appear, open the `.app` from Finder once to register it with LaunchServices, then add it to Accessibility.
- Logs are written to: `~/Library/Logs/Ticklet/` (one CSV per date).

## CI and platform targets

- CI is configured to target macOS 15 and Swift 6.0. If you change the platform or Swift language version, update `.github/workflows/ci.yml` and `Package.swift` accordingly.
- There's also a `/.github/workflows/release.yml` workflow (manual dispatch) that builds per-arch artifacts, uploads per-arch zips, and can create a draft GitHub Release attaching any produced zips. It will skip a matrix job if a runner for the requested architecture isn't available; for predictable multi-arch builds consider using self-hosted runners for each arch.

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
