import AppKit
import ApplicationServices

/// Helper to get app display name from bundle info, preferring CFBundleDisplayName over executable name
private func bundleDisplayName() -> String {
    return (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)
        ?? ProcessInfo.processInfo.processName
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var logger: CSVLogger?
    var tracker: ActivityTracker?
    var manager: ActivityManager?
    private var accessibilityPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Log startup for debugging
        NSLog("[Ticklet] applicationDidFinishLaunching")

        // Run as a regular macOS app (Dock + app menu)
        NSApp.setActivationPolicy(.regular)

        // Application main menu (About | Preferences | Quit)
        // Prefer a user-facing name from Info.plist (CFBundleDisplayName) or the bundle's executable name
        // This avoids showing build artifact names like "Ticklet-<arch>" when an arch‑specific
        // app bundle is used. Fall back to ProcessInfo if needed.
        let appName = bundleDisplayName()
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: appName)
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(quit), keyEquivalent: "q")

        // File menu (standard Close Window with Cmd-W)
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        // Use NSWindow.performClose: so the key window will close
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // View menu (Reload logs shortcut)
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        let reloadItem = NSMenuItem(title: "Reload Logs", action: #selector(reloadLogs), keyEquivalent: "r")
        reloadItem.target = self
        // Ensure it's Cmd-R
        reloadItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(reloadItem)

        NSApp.mainMenu = mainMenu

        // Status/menu for the status item (keeps existing items)
        let menu = NSMenu()

        // Accessibility status item (always visible so user can see current state)
        let accessItem = NSMenuItem(title: "Accessibility: Checking…", action: #selector(openAccessibilityPreferences), keyEquivalent: "")
        accessItem.target = self
        menu.addItem(accessItem)

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

        // Check accessibility permission and notify user if needed
        let hasAccessibility = AXIsProcessTrusted()
        if !hasAccessibility {
            // Show a user-friendly alert about needing Accessibility permission
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "Ticklet needs Accessibility permission to track window titles.\n\nClick OK to open System Settings, then:\n1. Click the + button\n2. Add Ticklet.app\n3. Enable the checkbox\n4. Restart Ticklet\n\nNote: After each app update, you'll need to re-authorize Ticklet."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // Open System Settings to Accessibility
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        // initialize tracker, logger, and UI
        do {
            logger = try CSVLogger()
            tracker = ActivityTracker()
            // Apply user-configured poll interval (seconds) if present
            let savedInterval = UserDefaults.standard.double(forKey: "pollIntervalSeconds")
            if savedInterval > 0 {
                tracker?.setPollInterval(savedInterval)
            }
            manager = ActivityManager(logger: logger!, tracker: tracker!)
            tracker?.start()

            // observe finalized entries to update status indicator
            NotificationCenter.default.addObserver(forName: .tickletEntryFinalized, object: nil, queue: .main) { [weak self] n in
                guard let entry = n.object as? ActivityEntry else { return }
                // Capture the app name (a Sendable type) so we don't send the whole entry into the MainActor task
                let appName = entry.appName
                Task { @MainActor in
                    if appName == "[IDLE]" {
                        self?.updateStatusIcon(isIdle: true)
                    } else {
                        self?.updateStatusIcon(isIdle: false)
                    }
                }
            }

            // Update accessibility menu item visibility
            updateAccessibilityMenuItem()

        } catch {
            print("Failed to initialize logger: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.stop()
    }

    // Preferences
    private var preferencesWindowController: PreferencesWindowController?
    private var logViewerWindowController: LogViewerWindowController?
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

    private func updateAccessibilityMenuItem() {
        let trusted = AXIsProcessTrusted()
        if trusted {
            // If accessibility is enabled, hide the prompt and debug items to reduce menu clutter
            accessibilityMenuItem?.isHidden = true
            accessibilityMenuItem?.isEnabled = false
            accessibilityMenuItem?.title = "✅ Accessibility: Enabled"

            // Hide any visible copy of the accessibility item in the actual menu so it cannot show stale text
            if let first = statusItem?.menu?.items.first {
                first.isHidden = true
                first.title = accessibilityMenuItem?.title ?? "✅ Accessibility: Enabled"
                first.isEnabled = false
                first.target = nil
                first.action = nil
            }
        } else {
            accessibilityMenuItem?.isHidden = false
            accessibilityMenuItem?.title = "⚠️ Accessibility permission required — Enable…"
            accessibilityMenuItem?.isEnabled = true


            // Ensure the visible first menu item is present and invites enabling
            if let first = statusItem?.menu?.items.first {
                first.isHidden = false
                first.title = accessibilityMenuItem?.title ?? "⚠️ Accessibility permission required — Enable…"
                first.isEnabled = true
                first.target = self
                first.action = #selector(openAccessibilityPreferences)
            }
        }
        NSLog("[Ticklet] accessibilityMenuItem now: \(accessibilityMenuItem?.title ?? "<nil>") hidden=\(accessibilityMenuItem?.isHidden ?? false)")
    }

    @objc private func openAccessibilityPreferences() {
        // Prompt the system dialog and open System Settings to Accessibility
        let options = ["AXTrustedCheckOptionPrompt" as String: true] as CFDictionary
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
                // Ensure mutation and UI updates happen on the MainActor
                Task { @MainActor in
                    self.accessibilityPollTimer = nil
                    self.updateAccessibilityMenuItem()
                }
            }
        }

        // Also schedule a final update in case polling didn't catch it (timeout after 15s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            Task { @MainActor in
                self?.accessibilityPollTimer?.invalidate()
                self?.accessibilityPollTimer = nil
                self?.updateAccessibilityMenuItem()
            }
        }
    }


    @objc private func openLogsViewer() {
        guard let logger = logger else { return }
        // Reuse existing window controller if present
        if let existing = logViewerWindowController {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let vc = LogViewerWindowController(logger: logger)
            logViewerWindowController = vc
            vc.showWindow(nil)
            vc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        // Refresh accessibility status when the user opens the logs menu/view
        updateAccessibilityMenuItem()
    }

    /// Called by `LogViewerWindowController` when the window closes so the AppDelegate can release its reference
    func logViewerDidClose(_ controller: LogViewerWindowController) {
        if logViewerWindowController === controller {
            logViewerWindowController = nil
        }
    }

    @objc private func reloadLogs() {
        // If the log viewer is open, tell it to refresh; otherwise open, then refresh
        if let existing = logViewerWindowController {
            existing.refresh()
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else if let logger = logger {
            let vc = LogViewerWindowController(logger: logger)
            logViewerWindowController = vc
            vc.showWindow(nil)
            vc.window?.makeKeyAndOrderFront(nil)
            vc.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
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
