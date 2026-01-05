import Foundation
import AppKit

@MainActor
final class ActivityTracker {
    var pollInterval: TimeInterval = 1.0
    var debounceWindow: TimeInterval = 3.0
    var minEntryDuration: TimeInterval = 3.0
    var idleThreshold: TimeInterval = 300.0 // 5 minutes

    // Callbacks
    var onEntryFinalized: ((ActivityEntry) -> Void)?

    private var timer: Timer?
    private var eventMonitor: Any?
    private var currentEntry: ActivityEntry?

    // pending observation that's waiting to become stable
    private var pendingObservation: (app: String, title: String, firstSeen: Date)?

    // last user activity timestamp
    private var lastUserActivity: Date = Date()

    // for testability, inject a clock
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now

    }

    func start() {
        // start must be called from the main thread / main actor
        precondition(Thread.isMainThread, "ActivityTracker.start() must be called on the main thread")

        // Schedule the timer
        scheduleTimer()

        // Only add the global event monitor once
        if eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
                self?.lastUserActivity = self?.now() ?? Date()
            }
        }

        // Initialize current entry based on current frontmost app
        if let (app, title) = currentFocusedAppAndTitle() {
            currentEntry = ActivityEntry(appName: app, windowTitle: title, startTime: now())
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            // Ensure tick runs on the main actor
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Update the poll interval at runtime. If the tracker is running this will reschedule the timer.
    func setPollInterval(_ seconds: TimeInterval) {
        pollInterval = seconds
        if timer != nil {
            scheduleTimer()
        }
    }

    // Method useful for tests: observe an incoming state at a given time
    func observe(app: String, windowTitle: String, at time: Date) {
        lastUserActivity = time

        // If we don't have a current entry yet, start one immediately
        if currentEntry == nil {
            currentEntry = ActivityEntry(appName: app, windowTitle: windowTitle, startTime: time)
            pendingObservation = nil
            return
        }

        // If currently idle, and we get activity, finalize the idle entry and start a new one
        if let cur = currentEntry, cur.appName == "[IDLE]" {
            // finalize idle entry
            var finalized = cur
            finalized.endTime = time
            onEntryFinalized?(finalized)
            // start new entry immediately
            currentEntry = ActivityEntry(appName: app, windowTitle: windowTitle, startTime: time)
            pendingObservation = nil
            return
        }

        // if same as current, nothing to do
        if let cur = currentEntry, cur.appName == app && cur.windowTitle == windowTitle {
            pendingObservation = nil
            return
        }

        // if no pending or different pending, set pending
        if pendingObservation == nil || pendingObservation!.app != app || pendingObservation!.title != windowTitle {
            pendingObservation = (app: app, title: windowTitle, firstSeen: time)
            return
        }

        // pending exists and matches current observation; check stability
        if let pending = pendingObservation, time.timeIntervalSince(pending.firstSeen) >= debounceWindow {
            // commit the change: finalize currentEntry and start new
            if var cur = currentEntry {
                cur.endTime = time
                // only finalize if duration meets min threshold
                if let dur = cur.durationSeconds, dur >= minEntryDuration {
                    onEntryFinalized?(cur)
                }
            }
            currentEntry = ActivityEntry(appName: pending.app, windowTitle: pending.title, startTime: time)
            pendingObservation = nil
        }
    }

    @MainActor func tick() {
        let t = now()

        // Idle detection
        if t.timeIntervalSince(lastUserActivity) >= idleThreshold {
            // if not already idle, create idle entry
            if let cur = currentEntry, cur.appName != "[IDLE]" {
                var finalized = cur
                finalized.endTime = lastUserActivity.addingTimeInterval(idleThreshold)
                if let dur = finalized.durationSeconds, dur >= minEntryDuration {
                    onEntryFinalized?(finalized)
                }
                // start idle entry
                currentEntry = ActivityEntry(appName: "[IDLE]", windowTitle: "[IDLE]", startTime: finalized.endTime!)
            }
            return
        }

        guard let (app, title) = currentFocusedAppAndTitle() else { return }
        observe(app: app, windowTitle: title, at: t)
    }

    // Accessibility helper: returns (appName, windowTitle) for the frontmost app when available
    private func currentFocusedAppAndTitle() -> (String, String)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = app.localizedName ?? "Unknown"

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        func titleFromWindow(_ window: AXUIElement) -> String? {
            // Try AXTitle first (most common)
            var titleRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success, let s = titleRef as? String, !s.isEmpty {
                return s
            }
            
            // Try AXDescription (some apps use this)
            if AXUIElementCopyAttributeValue(window, kAXDescriptionAttribute as CFString, &titleRef) == .success, let s = titleRef as? String, !s.isEmpty {
                return s
            }
            
            // Try AXValue
            if AXUIElementCopyAttributeValue(window, kAXValueAttribute as CFString, &titleRef) == .success, let s = titleRef as? String, !s.isEmpty {
                return s
            }
            
            // Try AXDocument (document-based apps often set this to the file path or document name)
            if AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &titleRef) == .success, let s = titleRef as? String, !s.isEmpty {
                // Extract filename from path if it looks like a file path
                let docString = s
                if docString.contains("/") {
                    return (docString as NSString).lastPathComponent
                }
                return docString
            }
            
            // For Electron apps and some complex UIs: try to find title in toolbar or title UI element
            var titleUIRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXTitleUIElementAttribute as CFString, &titleUIRef) == .success, let titleUI = titleUIRef {
                let titleUIElement = titleUI as! AXUIElement
                var titleUIValue: AnyObject?
                if AXUIElementCopyAttributeValue(titleUIElement, kAXValueAttribute as CFString, &titleUIValue) == .success, let s = titleUIValue as? String, !s.isEmpty {
                    return s
                }
                if AXUIElementCopyAttributeValue(titleUIElement, kAXTitleAttribute as CFString, &titleUIValue) == .success, let s = titleUIValue as? String, !s.isEmpty {
                    return s
                }
            }
            
            // Try children for static text (dialogs, alerts, some Electron windows)
            var childrenRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success, let children = childrenRef as? [AXUIElement] {
                for child in children {
                    var roleRef: AnyObject?
                    if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success, let role = roleRef as? String {
                        // Check static text or toolbar elements
                        if role == kAXStaticTextRole as String || role == kAXToolbarRole as String {
                            var val: AnyObject?
                            if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &val) == .success, let s = val as? String, !s.isEmpty {
                                return s
                            }
                            if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &val) == .success, let s = val as? String, !s.isEmpty {
                                return s
                            }
                        }
                    }
                }
            }
            return nil
        }

        // Try focused window first (catches active tabs, focused documents)
        var focusedWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success, focusedWindow != nil {
            let window = focusedWindow as! AXUIElement
            if let t = titleFromWindow(window) { return (appName, t) }
        }

        // Fallback to main window
        var mainWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow) == .success, mainWindow != nil {
            let mwin = mainWindow as! AXUIElement
            if let t = titleFromWindow(mwin) { return (appName, t) }
        }
        
        // For apps with multiple windows but no focused/main window, try the windows list
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
            // Try first visible window (often the frontmost)
            if let t = titleFromWindow(windows[0]) { return (appName, t) }
        }

        // Try getting a title from the application itself (menu bar apps, status items)
        var appTitleRef: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXTitleAttribute as CFString, &appTitleRef) == .success, let s = appTitleRef as? String, !s.isEmpty {
            return (appName, s)
        }

        // Last resort: return app name with empty title
        return (appName, "")
    }
}
