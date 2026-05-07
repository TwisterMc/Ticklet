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
        // Prevent a stalled target app from blocking the main thread for more than 100ms
        AXUIElementSetMessagingTimeout(appElement, 0.1)

        func attributeString(_ attribute: CFString, from element: AXUIElement) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
                return nil
            }
            guard let stringValue = value as? String else {
                return nil
            }

            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            if attribute == kAXDocumentAttribute as CFString, trimmed.contains("/") {
                return (trimmed as NSString).lastPathComponent
            }
            return trimmed
        }

        func children(of element: AXUIElement) -> [AXUIElement] {
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement] else {
                return []
            }
            return children
        }

        func parent(of element: AXUIElement) -> AXUIElement? {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success else {
                return nil
            }
            return parentRef as! AXUIElement?
        }

        func role(of element: AXUIElement) -> String? {
            attributeString(kAXRoleAttribute as CFString, from: element)
        }

        func titleFromElement(_ element: AXUIElement) -> String? {
            let directAttributes: [CFString] = [
                kAXTitleAttribute as CFString,
                kAXDescriptionAttribute as CFString,
                kAXValueAttribute as CFString,
                kAXDocumentAttribute as CFString
            ]

            for attribute in directAttributes {
                if let title = attributeString(attribute, from: element) {
                    return title
                }
            }

            var titleUIRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXTitleUIElementAttribute as CFString, &titleUIRef) == .success,
               let titleUIElement = titleUIRef as! AXUIElement? {
                if let title = titleFromElement(titleUIElement) {
                    return title
                }
            }

            // Some apps expose the visible title on descendants of the focused element or toolbar.
            var queue: [(element: AXUIElement, depth: Int)] = children(of: element).map { ($0, 1) }
            var visited = 0
            while !queue.isEmpty && visited < 150 {
                let current = queue.removeFirst()
                visited += 1

                if let currentRole = role(of: current.element),
                   currentRole == kAXStaticTextRole as String || currentRole == kAXTextFieldRole as String || currentRole == kAXToolbarRole as String {
                    for attribute in [kAXValueAttribute as CFString, kAXTitleAttribute as CFString, kAXDescriptionAttribute as CFString] {
                        if let title = attributeString(attribute, from: current.element) {
                            return title
                        }
                    }
                }

                if current.depth < 4 {
                    queue.append(contentsOf: children(of: current.element).map { ($0, current.depth + 1) })
                }
            }

            return nil
        }

        func containingWindow(for element: AXUIElement) -> AXUIElement? {
            var current: AXUIElement? = element
            var traversed = 0
            while let node = current, traversed < 20 {
                if role(of: node) == kAXWindowRole as String {
                    return node
                }
                current = parent(of: node)
                traversed += 1
            }
            return nil
        }

        // Try focused window first (catches active tabs, focused documents)
        var focusedWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success, focusedWindow != nil {
            let window = focusedWindow as! AXUIElement
            if let t = titleFromElement(window) { return (appName, t) }
        }

        // Fallback to main window
        var mainWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow) == .success, mainWindow != nil {
            let mwin = mainWindow as! AXUIElement
            if let t = titleFromElement(mwin) { return (appName, t) }
        }
        
        // For apps with multiple windows but no focused/main window, try the windows list
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
            // Try first visible window (often the frontmost)
            if let t = titleFromElement(windows[0]) { return (appName, t) }
        }

        // Try getting a title from the application itself (menu bar apps, status items)
        if let title = titleFromElement(appElement) {
            return (appName, title)
        }

        // Last resort: return app name with empty title
        return (appName, "")
    }
}
