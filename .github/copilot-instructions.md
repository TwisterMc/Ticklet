# Ticklet - macOS Window Activity Logger

## Project Specification & Feature List

---

## 🎯 Purpose

Answer one question reliably:

> **"What apps and windows did I spend my time on today, and for how long?"**

Ticklet is a lightweight macOS menu bar app that logs your frontmost application and focused window title over time, producing a clean timeline of your daily activity.

---

## ✨ Core Features

### Automatic Activity Tracking

- **Logs frontmost app name and focused window title**
- **Groups time by continuous focus** - each entry represents uninterrupted time in one window
- **Debounces noisy title changes** - 5-second stability threshold prevents log pollution
- **Runs automatically when app is open** - no play/pause needed, just quit if you don't want tracking

### Idle Detection

- **5-minute idle threshold** - automatically detects when you step away
- **Logs idle periods as `[IDLE]`** - see gaps in your day
- **Resumes tracking on activity** - seamlessly picks up when you return

### Data Management

- **Daily log rotation** - one CSV file per day
- **Structured CSV format** - easy to parse, grep, or import into spreadsheets
- **Local storage only** - all data stays in `~/Library/Logs/Ticklet/`
- **RFC 4180 CSV escaping** - handles commas, quotes, and newlines correctly
- **Minimum duration threshold** - entries shorter than 5 seconds are filtered out

### Menu Bar Presence

- **Simple menu bar icon** - gray dot when running, visual confirmation
- **Clean menu interface:**
  - 📊 View Logs...
  - ⚙️ Open Logs Folder
  - ❌ Quit Ticklet

### Log Viewer Window

- **Date picker with navigation** - browse any date with Previous/Next/Today buttons
- **Activity table** - shows Time, Duration, App, Window for each entry
- **Daily summary statistics:**
  - Total time per app
  - Window count per app
  - Total logged time for the day
  - Idle time breakdown
- **Sorted by time spent** - most-used apps appear first

---

## 🚫 Non-Features (Intentionally Excluded)

This project explicitly does **not**:

- Ship to the Mac App Store
- Sync data to the cloud
- Use third-party libraries or frameworks
- Perform AI categorization or analysis
- Track keystrokes, mouse input, or screen contents
- Take screenshots or record screen activity
- Send telemetry or analytics
- Require user accounts or authentication
- Group or categorize windows automatically (shows raw data)

**Privacy-first philosophy:** Only observes application focus and window titles. No behavioral analytics, no surveillance features.

---

## 📋 Technical Specifications

### System Requirements

- **macOS 12.0+** (Monterey or later)
- **Universal Binary** - runs natively on Intel and Apple Silicon Macs
- **Accessibility permission required** - to read window titles

### Architecture

- **Pure Swift** - no Objective-C, no dependencies
- **Native AppKit** - follows macOS Human Interface Guidelines
- **Single-responsibility design** - clean separation of concerns
- **Memory efficient** - minimal footprint, optimized polling

### Timing & Performance

- **Poll interval:** 1 second
- **Minimum entry duration:** 5 seconds (entries shorter than this are discarded)
- **Idle threshold:** 5 minutes (no changes → log `[IDLE]`)
- **Debounce window:** Title must be stable for 5 seconds before logging
- **CPU usage:** Negligible (<0.1% average)
- **Memory footprint:** <20MB typical

### Data Model

```swift
struct ActivityEntry {
    let appName: String        // "Slack"
    let windowTitle: String    // "#company"
    let startTime: Date        // ISO8601 timestamp
    var endTime: Date?         // ISO8601 timestamp
}
```

### CSV Format

```csv
start_time,end_time,duration_seconds,app_name,window_title
2026-01-03 08:10:23,2026-01-03 08:15:12,289,Slack,#company
2026-01-03 08:15:12,2026-01-03 08:19:45,273,Slack,#help
2026-01-03 08:19:45,2026-01-03 08:24:33,288,Figma,"Design Doc, v12"
2026-01-03 08:24:33,2026-01-03 08:29:01,268,[IDLE],[IDLE]

```

**Note:** App name always comes first, matching user's request.

### File Locations

- **Logs directory:** `~/Library/Logs/Ticklet/`
- **Log files:** `ticklet-YYYY-MM-DD.csv` (one per day)
- **No configuration files** - settings are constants in code

---

## 🔐 Security & Privacy

### Permissions

- **Accessibility API** - required to read window titles
- **No network access** - app never communicates with external servers
- **No location services** - doesn't use GPS or location data
- **No camera/microphone** - only monitors app/window focus

### Data Protection

- **Local-only storage** - logs never leave your Mac
- **No encryption needed** - data is already private to your user account
- **User-controlled deletion** - just delete CSV files to remove history
- **No backups by app** - relies on Time Machine/user backups

### Noise Filtering

Ignored apps (hardcoded):

- Spotlight
- Notification Center
- Control Center

Also filters:

- Empty window titles
- Entries shorter than 5 seconds
- System UI transients

---

## 🎨 User Interface Design

### Menu Bar Icon

- **Gray dot:** Running normally
- **Dim gray:** Idle state (optional future enhancement)
- **Red:** Missing Accessibility permission (error state)

### Log Viewer Window

- **Window size:** 800×600 (resizable)
- **Layout:**
  - Top: Date navigation (Previous | Date | Next | Today)
  - Middle: Activity table (scrollable)
  - Bottom: Summary statistics
- **Follows system appearance** - auto-adapts to light/dark mode
- **Native controls** - standard macOS buttons, table views, text fields

### Accessibility

- **Keyboard navigation** - full support for keyboard-only operation
- **VoiceOver compatible** - properly labeled elements
- **High contrast support** - respects system accessibility settings
- **Focus indicators** - clear visual focus states

---

## 🚀 Future Enhancements (Roadmap)

### Phase 2 - Analysis

- Search/filter in log viewer
- Export options (JSON, SQLite)
- Charts and visualizations (bar charts, pie charts)
- Multi-day comparisons

### Phase 3 - Intelligence

- Rule-based grouping ("Terminal" + "VS Code" → "Coding")
- Smart categories (automatic work/personal detection)
- Weekly/monthly reports
- Productivity insights

### Phase 4 - Integration

- AppleScript support
- Shortcuts integration
- CSV export automation
- iCloud sync (opt-in, privacy-preserving)

**Philosophy:** Each phase must maintain simplicity and user control. No features become mandatory.

---

## 🛠️ Development Guidelines

### Code Style

- **Prefer clarity over cleverness**
- **Use descriptive variable names** (except standard loop indices)
- **Comment complex logic** especially Accessibility API usage
- **Keep functions small** - single responsibility principle
- **Avoid premature optimization** - readable first, fast second

### Testing Strategy

- **Manual testing primary** - run the app, verify logs
- **Test edge cases:**
  - Rapid app switching
  - Long window titles (>1000 chars)
  - Special characters in titles (emoji, unicode)
  - Missing Accessibility permission
  - Disk full scenarios
  - Midnight log rotation

### Version Control

- Use semantic versioning (1.0.0)
- Tag releases
- Keep CHANGELOG.md updated
- Document breaking changes

---

## 📦 Distribution

### Development

- Build in Xcode
- Code signing with personal certificate
- Run locally from Applications folder

### Future Distribution Options

1. **GitHub Releases** - signed .app in .dmg
2. **Homebrew Cask** - `brew install --cask ticklet`
3. **Direct download** - from project website
4. **Not App Store** - intentionally avoiding sandboxing restrictions

---

## 📄 License

Choose an appropriate open-source license:

- **MIT** - maximum freedom, minimal restrictions
- **Apache 2.0** - includes patent grant
- **GPL v3** - copyleft, requires derivative works to be open

Recommendation: **MIT** for simplicity and broad adoption.

---

## 🤝 Contributing

### Contribution Guidelines

- Follow existing code style
- Test on both Intel and Apple Silicon
- Update documentation for new features
- Keep backward compatibility with CSV format
- Don't add dependencies without discussion

### Bug Reports Should Include

- macOS version
- Mac model (Intel/Apple Silicon)
- Steps to reproduce
- Expected vs actual behavior
- Relevant log entries

---

## 📞 Support & Contact

### Getting Help

1. Check documentation
2. Search existing GitHub issues
3. Open new issue with details

### Feature Requests

- Open GitHub issue with `[Feature Request]` tag
- Describe use case, not implementation
- Consider if it aligns with project philosophy

---

## 🎓 Learning Resources

For developers wanting to understand the code:

**macOS Concepts:**

- NSApplication lifecycle
- NSStatusItem (menu bar items)
- NSTableView (data display)
- Accessibility API (AX framework)

**Swift Patterns:**

- Protocol-oriented design
- Value types (structs) vs reference types (classes)
- Memory management (weak references)
- File I/O and error handling

**Relevant Apple Documentation:**

- [Accessibility Programming Guide](https://developer.apple.com/documentation/accessibility)
- [AppKit Framework](https://developer.apple.com/documentation/appkit)
- [File System Programming Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/)
- [Human Interface Guidelines - macOS](https://developer.apple.com/design/human-interface-guidelines/macos)

---

## 📊 Success Metrics

How we measure if Ticklet is successful:

1. **It works reliably** - logs every app switch accurately
2. **It's invisible** - users forget it's running
3. **Logs are useful** - users reference them to understand their day
4. **No complaints about performance** - negligible system impact
5. **Privacy is maintained** - no data leaks, no surprises

---

## 🔄 Version History

### v1.0.0 - Initial Release

- Core logging functionality
- Daily CSV rotation
- Idle detection
- Log viewer with date picker
- Menu bar presence
- Universal binary (Intel + Apple Silicon)
- Full Accessibility API integration
- MacOS 15+

---

**Last Updated:** January 3, 2026  
**Project Status:** Active Development  
**Maintainer:** Thomas McMahon
