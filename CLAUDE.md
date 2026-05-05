# Claude Code Instructions

## Project

Ticklet is a macOS menu bar app that tracks active application usage. Built with Swift 6.0, targeting macOS 15+. Uses SwiftUI for views with an AppKit-managed app lifecycle (`@NSApplicationDelegateAdaptor`).

## Standards

All code must meet these standards by default — do not wait to be asked:

- **Accessibility**: All UI must be VoiceOver-compatible. Use `Form` for settings, associate labels with controls, provide `accessibilityLabel`, `accessibilityValue`, and `accessibilityHint` where the default introspection falls short. Test with accessibility in mind.
- **Platform conventions**: Follow current Apple Human Interface Guidelines and use the latest APIs available for the deployment target (macOS 15). When newer APIs exist but require a higher target, note it in code comments and use the best available alternative.
- **Performance**: Avoid unnecessary work on the main thread. Prefer `async`/`await` over Combine. Don't poll when observation or notifications suffice.
- **Security**: Never store sensitive data in plain text. Validate external input. Follow OWASP guidelines. This app handles user activity data — treat it as sensitive.
- **Privacy**: Ticklet logs user activity. Any changes to what is logged, how it's stored, or how it's transmitted must be flagged and discussed before implementation.

## Architecture

- `AppDelegate` manages the AppKit lifecycle: status item, menus, window management.
- `TickletApp` is the SwiftUI entry point (`@main`) with `@NSApplicationDelegateAdaptor`.
- Settings window is hosted via `NSHostingController` wrapping `PreferencesView` (the SwiftUI `Settings` scene can't be opened programmatically from AppKit on macOS 15).
- `@AppStorage` for user preferences, `onChange` handlers bridge to `AppDelegate` methods.

## Code style

- Swift API Design Guidelines. PascalCase types, camelCase members.
- `async`/`await` over Combine.
- `@MainActor` for UI-facing code.
- Minimal comments — only explain *why*, not *what*.

## Testing

- Use the Swift Testing framework (`import Testing`), not XCTest.
- Tests in `Tests/TickletTests/`. Prefer temporary directories for file-based tests.
