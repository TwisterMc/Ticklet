import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var logger: CSVLogger?
    var tracker: ActivityTracker?
    var manager: ActivityManager?
    private var accessibilityPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Log startup for debugging
        NSLog("[Ticklet] applicationDidFinishLaunching")

        // Optional launch alert when env var is set (useful for debugging runs from Terminal/Xcode)
        if ProcessInfo.processInfo.environment["TICKLET_SHOW_LAUNCH_ALERT"] != nil {
            let alert = NSAlert()
            alert.messageText = "Ticklet launched"
            alert.informativeText = "PID: \(ProcessInfo.processInfo.processIdentifier) — check console for logs"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }

        // Run as a regular macOS app (Dock + app menu)
        NSApp.setActivationPolicy(.regular)

        // Application main menu (About | Preferences | Quit)
        let appName = ProcessInfo.processInfo.processName
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: appName)
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(quit), keyEquivalent: "q")
        NSApp.mainMenu = mainMenu

        // Status/menu for the status item (keeps existing items)
        let menu = NSMenu()

        // Accessibility status item (always visible so user can see current state)
        let accessItem = NSMenuItem(title: "Accessibility: Checking…", action: #selector(openAccessibilityPreferences), keyEquivalent: "")
        accessItem.target = self
        menu.addItem(accessItem)
        self.accessibilityMenuItem = accessItem
        NSLog("[Ticklet] created accessibilityMenuItem: \(accessibilityMenuItem?.title ?? "<nil>")")

        // Debug info item to help diagnose permission issues
        let debugItem = NSMenuItem(title: "Accessibility: Debug Info…", action: #selector(showAccessibilityDebugInfo), keyEquivalent: "")
        debugItem.target = self
        menu.addItem(debugItem)
        NSLog("[Ticklet] created debugMenuItem: \(debugItem.title)")

        menu.addItem(.separator())

        // ensure menu updates when opened
        menu.delegate = self
        NSLog("[Ticklet] menu created with firstItem=\(menu.items.first?.title ?? "<none>") items=\(menu.items.map { $0.title }.joined(separator: " | "))")

        self.debugMenuItem = debugItem
        self.accessibilityMenuItem = accessItem

        let viewLogs = NSMenuItem(title: "View Logs…", action: #selector(openLogsViewer), keyEquivalent: "")
        viewLogs.target = self
        menu.addItem(viewLogs)

        let openFolder = NSMenuItem(title: "Open Logs Folder", action: #selector(openLogsFolder), keyEquivalent: "")
        openFolder.target = self
        menu.addItem(openFolder)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Ticklet", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Read preference to determine if we should show status item (default: true)
        let show = UserDefaults.standard.object(forKey: "showStatusItem") as? Bool ?? true
        self.showStatusItem = show
        if show {
            createStatusItem(with: menu)
        }

        // initialize tracker, logger, and UI
        do {
            logger = try CSVLogger()
            tracker = ActivityTracker()
            manager = ActivityManager(logger: logger!, tracker: tracker!)
            tracker?.start()

            // observe finalized entries to update status indicator
            NotificationCenter.default.addObserver(forName: .tickletEntryFinalized, object: nil, queue: .main) { [weak self] n in
                guard let entry = n.object as? ActivityEntry else { return }
                if entry.appName == "[IDLE]" {
                    self?.updateStatusIcon(isIdle: true)
                } else {
                    self?.updateStatusIcon(isIdle: false)
                }
            }

            // Update accessibility menu item visibility (we do not use the icon for warnings)
            NSLog("[Ticklet] calling updateAccessibilityMenuItem at launch")
            updateAccessibilityMenuItem()
            NSLog("[Ticklet] called updateAccessibilityMenuItem at launch - title=\(accessibilityMenuItem?.title ?? "<nil>")")

        } catch {
            print("Failed to initialize logger: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.stop()
    }

    // Preferences
    private var preferencesWindowController: PreferencesWindowController?
    var showStatusItem: Bool = true {
        didSet {
            UserDefaults.standard.set(showStatusItem, forKey: "showStatusItem")
            if showStatusItem {
                // recreate menu if needed
                if let menu = statusItem?.menu {
                    createStatusItem(with: menu)
                } else {
                    // If we don't have a menu yet, create one similar to existing
                    let menu = NSMenu()
                    let ai = NSMenuItem(title: "Accessibility: Checking…", action: #selector(openAccessibilityPreferences), keyEquivalent: "")
                    ai.target = self
                    menu.addItem(ai)
                    self.accessibilityMenuItem = ai
                    menu.addItem(NSMenuItem(title: "Accessibility: Debug Info…", action: #selector(showAccessibilityDebugInfo), keyEquivalent: ""))
                    menu.addItem(.separator())
                    let viewLogs = NSMenuItem(title: "View Logs…", action: #selector(openLogsViewer), keyEquivalent: "")
                    viewLogs.target = self
                    menu.addItem(viewLogs)
                    let openFolder = NSMenuItem(title: "Open Logs Folder", action: #selector(openLogsFolder), keyEquivalent: "")
                    openFolder.target = self
                    menu.addItem(openFolder)
                    menu.addItem(.separator())
                    menu.addItem(NSMenuItem(title: "Quit Ticklet", action: #selector(quit), keyEquivalent: "q"))
                    createStatusItem(with: menu)
                }
            } else {
                removeStatusItem()
            }
        }
    }

    private func createStatusItem(with menu: NSMenu) {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        statusItem?.menu = menu
        NSLog("[Ticklet] createStatusItem - assigned menu with firstItem=\(menu.items.first?.title ?? "<none>")")
        if let btn = statusItem?.button {
            if let img = makeStatusImage() {
                img.isTemplate = true // let system tint the symbol appropriately for light/dark
                btn.image = img
            }
            btn.imagePosition = .imageOnly
            btn.bezelStyle = .texturedRounded
            btn.isBordered = false
            // use alpha to indicate idle vs active; do not set contentTintColor so system uses the correct menu-bar color
            btn.alphaValue = 1.0
        }

        // Ensure accessibility label is updated right away so menu shows a human-readable first item
        updateAccessibilityMenuItem()    }

    private func removeStatusItem() {
        if let si = statusItem {
            NSStatusBar.system.removeStatusItem(si)
            statusItem = nil
        }
    }

    private func makeStatusImage() -> NSImage? {
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            return NSImage(systemSymbolName: "person.crop.circle.badge.clock", accessibilityDescription: "Ticklet")?.withSymbolConfiguration(config)
        } else {
            return nil
        }
    }

    private func updateStatusIcon(isIdle: Bool) {
        guard let btn = statusItem?.button else { return }
        if btn.image == nil {
            if let img = makeStatusImage() {
                img.isTemplate = true
                btn.image = img
            }
        }
        // Use alpha to dim for idle; system tints template image to correct light/dark color automatically
        btn.alphaValue = isIdle ? 0.6 : 1.0
    }

    private var accessibilityMenuItem: NSMenuItem?
    private var debugMenuItem: NSMenuItem?

    private func updateAccessibilityMenuItem() {
        let trusted = AXIsProcessTrusted()
        NSLog("[Ticklet] updateAccessibilityMenuItem called - trusted: \(trusted) - accessibilityMenuItem exists: \(accessibilityMenuItem != nil) - previousTitle: \(accessibilityMenuItem?.title ?? "<nil>")")
        if trusted {
            // If accessibility is enabled, hide the prompt and debug items to reduce menu clutter
            accessibilityMenuItem?.isHidden = true
            accessibilityMenuItem?.isEnabled = false
            accessibilityMenuItem?.title = "✅ Accessibility: Enabled"
            debugMenuItem?.isHidden = true

            // Hide any visible copy of the accessibility item in the actual menu so it cannot show stale text
            if let first = statusItem?.menu?.items.first {
                first.isHidden = true
                first.title = accessibilityMenuItem?.title ?? "✅ Accessibility: Enabled"
                first.isEnabled = false
                first.target = nil
                first.action = nil
                NSLog("[Ticklet] updateAccessibilityMenuItem: hid visible first menu item")
            }
        } else {
            accessibilityMenuItem?.isHidden = false
            accessibilityMenuItem?.title = "⚠️ Accessibility permission required — Enable…"
            accessibilityMenuItem?.isEnabled = true

            // Keep the debug item visible when troubleshooting
            debugMenuItem?.isHidden = false
            debugMenuItem?.isEnabled = true

            // Ensure the visible first menu item is present and invites enabling
            if let first = statusItem?.menu?.items.first {
                first.isHidden = false
                first.title = accessibilityMenuItem?.title ?? "⚠️ Accessibility permission required — Enable…"
                first.isEnabled = true
                first.target = self
                first.action = #selector(openAccessibilityPreferences)
                NSLog("[Ticklet] updateAccessibilityMenuItem: showed visible first menu item")
            }
        }
        NSLog("[Ticklet] accessibilityMenuItem now: \(accessibilityMenuItem?.title ?? "<nil>") hidden=\(accessibilityMenuItem?.isHidden ?? false)")
    }

    @objc private func openAccessibilityPreferences() {
        // Prompt the system dialog and open System Settings to Accessibility
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // Start a short polling timer so the menu updates immediately when the user grants permission
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.accessibilityPollTimer = nil
                self.updateAccessibilityMenuItem()
            }
        }

        // Also schedule a final update in case polling didn't catch it (timeout after 15s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            self?.accessibilityPollTimer?.invalidate()
            self?.accessibilityPollTimer = nil
            self?.updateAccessibilityMenuItem()
        }
    }

    @objc private func showAccessibilityDebugInfo() {
        // Gather runtime info to help diagnose why the system might not report the permission
        let proc = ProcessInfo.processInfo
        let pid = proc.processIdentifier
        let name = proc.processName
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let execPath = Bundle.main.executableURL?.path ?? "unknown"
        let trusted = AXIsProcessTrusted()

        // sample list of running applications (name and bundle id)
        let running = NSWorkspace.shared.runningApplications.prefix(40).map { "\($0.processIdentifier): \($0.localizedName ?? "?") (\($0.bundleIdentifier ?? ""))" }.joined(separator: "\n")

        let msg = "AXIsProcessTrusted: \(trusted)\nPID: \(pid)\nProcessName: \(name)\nBundleID: \(bundleId)\nExecPath: \(execPath)\n\nRunning apps (sample):\n\(running)"

        NSLog("[Ticklet] Accessibility debug:\n\(msg)")

        let alert = NSAlert()
        alert.messageText = "Accessibility Debug Info"
        alert.informativeText = msg
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openLogsViewer() {
        guard let logger = logger else { return }
        let vc = LogViewerWindowController(logger: logger)
        vc.showWindow(nil)
        vc.window?.makeKeyAndOrderFront(nil)

        // Refresh accessibility status when the user opens the logs menu/view
        updateAccessibilityMenuItem()
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSMenuDelegate
    public func menuWillOpen(_ menu: NSMenu) {
        let itemTitles = menu.items.map { $0.title }.joined(separator: " | ")
        NSLog("[Ticklet] menuWillOpen: firstItem=\(menu.items.first?.title ?? "<none>") items=\(itemTitles) accessibilityMenuItem=\(accessibilityMenuItem?.title ?? "<nil>")")
        updateAccessibilityMenuItem()

        // Ensure the visible first item reflects the CURRENT permission state (avoid stale "Checking…")
        let trusted = AXIsProcessTrusted()
        if let first = menu.items.first {
            if trusted {
                // Show a disabled, affirmative state so the menu doesn't show stale prompts
                first.title = "✅ Accessibility: Enabled"
                first.isEnabled = false
                first.target = nil
                first.action = nil
            } else if let ai = accessibilityMenuItem, ai.isHidden == false {
                // If our internal accessibility item is visible, sync it into the visible menu
                if first !== ai {
                    NSLog("[Ticklet] menuWillOpen: syncing visible first item (\(first.title)) -> (\(ai.title))")
                    first.title = ai.title
                    first.isEnabled = ai.isEnabled
                    first.target = ai.target
                    first.action = ai.action
                }
            } else {
                // No internal accessibility item visible; ensure the first item invites enabling
                first.title = "⚠️ Accessibility permission required — Enable…"
                first.isEnabled = true
                first.target = self
                first.action = #selector(openAccessibilityPreferences)
            }
        }

        // Ensure debug item visibility matches permission state
        if trusted {
            debugMenuItem?.isHidden = true
        } else {
            debugMenuItem?.isHidden = false
            debugMenuItem?.isEnabled = true
        }

        NSLog("[Ticklet] menuWillOpen after update: accessibilityMenuItem=\(accessibilityMenuItem?.title ?? "<nil>") visibleFirst=\(menu.items.first?.title ?? "<none>")")
    }

    @objc private func openLogsFolder() {
        if let url = logger?.logsDirectory {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}


// Top-level application startup (keeps SwiftPM happy for tests)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
