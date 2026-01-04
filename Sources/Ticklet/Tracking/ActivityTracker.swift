import Foundation
import AppKit

public final class ActivityTracker {
    public var pollInterval: TimeInterval = 1.0
    public var debounceWindow: TimeInterval = 3.0
    public var minEntryDuration: TimeInterval = 3.0
    public var idleThreshold: TimeInterval = 300.0 // 5 minutes

    // Callbacks
    public var onEntryFinalized: ((ActivityEntry) -> Void)?

    private var timer: Timer?
    private var eventMonitor: Any?
    private var currentEntry: ActivityEntry?

    // pending observation that's waiting to become stable
    private var pendingObservation: (app: String, title: String, firstSeen: Date)?

    // last user activity timestamp
    private var lastUserActivity: Date = Date()

    // for testability, inject a clock
    private let now: () -> Date

    public init(now: @escaping () -> Date = { Date() }) {
        self.now = now

    }

    public func start() {
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

    public func stop() {
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
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Update the poll interval at runtime. If the tracker is running this will reschedule the timer.
    public func setPollInterval(_ seconds: TimeInterval) {
        pollInterval = seconds
        if timer != nil {
            scheduleTimer()
        }
    }

    // Public method useful for tests: observe an incoming state at a given time
    public func observe(app: String, windowTitle: String, at time: Date) {
        lastUserActivity = time

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

    @objc private func tick() {
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
            var titleRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success, let s = titleRef as? String, !s.isEmpty {
                return s
            }
            if AXUIElementCopyAttributeValue(window, kAXValueAttribute as CFString, &titleRef) == .success, let s = titleRef as? String, !s.isEmpty {
                return s
            }
            // try children for static text
            var childrenRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success, let children = childrenRef as? [AXUIElement] {
                for child in children {
                    var roleRef: AnyObject?
                    if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success, let role = roleRef as? String, role == kAXStaticTextRole as String {
                        var val: AnyObject?
                        if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &val) == .success, let s = val as? String, !s.isEmpty {
                            return s
                        }
                    }
                }
            }
            return nil
        }

        // Try focused window
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

        // Try getting a title from the application itself
        var appTitleRef: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXTitleAttribute as CFString, &appTitleRef) == .success, let s = appTitleRef as? String, !s.isEmpty {
            return (appName, s)
        }

        // Last resort: return app name with empty title
        return (appName, "")
    }
}
