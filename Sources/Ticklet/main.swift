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
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var logger: CSVLogger?
    private var tracker: ActivityTracker?
    private var manager: ActivityManager?
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
        let aboutItem = NSMenuItem(title: "About \(appName)", action: #selector(openAboutPanel), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")
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

        // Build and retain the status-bar menu so it can be reused if the
        // user toggles the status item off and back on via Preferences.
        let menu = buildStatusMenu()
        statusMenu = menu

        // Read preference to determine if we should show status item (default: true)
        let show = UserDefaults.standard.object(forKey: "showStatusItem") as? Bool ?? true
        self.showStatusItem = show
        if show {
            createStatusItem(with: menu)
        }

        // Check accessibility permission; start polling immediately so the menu
        // updates as soon as permission is granted regardless of how the user gets there.
        if !AXIsProcessTrusted() {
            startAccessibilityPolling()
            // Brief delay so the app finishes launching before presenting the alert
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.promptForAccessibilityIfNeeded()
            }
        }

        // initialize tracker, logger, and UI
        do {
            logger = try CSVLogger()
            // Apply saved privacy preference
            logger?.redactWindowTitles = UserDefaults.standard.bool(forKey: "redactWindowTitles")
            tracker = ActivityTracker()
            // Apply user-configured poll interval (seconds) if present, with bounds check
            let savedInterval = UserDefaults.standard.double(forKey: "pollIntervalSeconds")
            if savedInterval >= 0.1 && savedInterval <= 60.0 {
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
                    self?.updateStatusIcon(isIdle: appName == "[IDLE]")
                }
            }

            // Update accessibility menu item visibility
            updateAccessibilityMenuItem()

        } catch {
            print("Failed to initialize logger: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        manager?.stop()
    }

    // MARK: - Status menu

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        // Accessibility status item — visible until permission is granted
        let accessItem = NSMenuItem(title: "Accessibility Access Required — Enable…", action: #selector(openAccessibilityPreferences), keyEquivalent: "")
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

        let about = NSMenuItem(title: "About", action: #selector(openAboutPanel), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openPreferences), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        let donate = NSMenuItem(title: "Donate", action: #selector(openDonate), keyEquivalent: "")
        donate.target = self
        menu.addItem(donate)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Ticklet", action: #selector(self.quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // Preferences
    private var preferencesWindowController: PreferencesWindowController?
    private var logViewerWindowController: LogViewerWindowController?
    var showStatusItem: Bool = true {
        didSet {
            UserDefaults.standard.set(showStatusItem, forKey: "showStatusItem")
            if showStatusItem {
                let menu = statusMenu ?? buildStatusMenu()
                statusMenu = menu
                createStatusItem(with: menu)
            } else {
                removeStatusItem()
            }
        }
    }

    private func createStatusItem(with menu: NSMenu) {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        menu.delegate = self
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
            btn.setAccessibilityLabel("Ticklet — activity tracking")
        }

        // Ensure accessibility label is updated right away so menu shows a human-readable first item
        updateAccessibilityMenuItem()
    }

    private func removeStatusItem() {
        if let si = statusItem {
            NSStatusBar.system.removeStatusItem(si)
            statusItem = nil
        }
    }

    private func makeStatusImage() -> NSImage? {
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular, scale: .medium)
            return NSImage(systemSymbolName: "person.crop.circle.badge.clock", accessibilityDescription: "Ticklet")?.withSymbolConfiguration(config)
        } else {
            return nil
        }
    }

    private func updateStatusIcon(isIdle: Bool) {
        guard let btn = statusItem?.button else { return }
        // Use alpha to dim for idle; system tints template image to correct light/dark color automatically
        btn.alphaValue = isIdle ? 0.6 : 1.0
    }

    private var accessibilityMenuItem: NSMenuItem?

    private func updateAccessibilityMenuItem() {
        if AXIsProcessTrusted() {
            accessibilityMenuItem?.isHidden = true
            accessibilityMenuItem?.isEnabled = false
        } else {
            accessibilityMenuItem?.isHidden = false
            accessibilityMenuItem?.isEnabled = true
        }
    }

    /// Shows an alert explaining why Ticklet needs Accessibility access, then triggers
    /// the system grant flow if the user agrees.  Only called when not yet trusted.
    private func promptForAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "Ticklet needs Accessibility access to track which apps and windows you use.\n\nClick \"Grant Access\" to open System Settings, then enable Ticklet in the Accessibility list. Tracking will start automatically — no restart required.\n\nNote: After each app update you may need to re-enable access."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Grant Access")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        requestAccessibilityAccess()
    }

    /// Calls the system API that opens System Settings → Privacy → Accessibility
    /// (or shows the TCC prompt on older macOS).  Single entry-point for all grant flows.
    private func requestAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc private func openAccessibilityPreferences() {
        requestAccessibilityAccess()
        startAccessibilityPolling()
    }

    /// Starts a 1-second repeating timer that updates the menu item as soon as
    /// the user grants Accessibility access.  Safe to call multiple times — a
    /// running timer is invalidated before starting a new one.
    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            Task { @MainActor in
                self.accessibilityPollTimer = nil
                self.updateAccessibilityMenuItem()
            }
        }
        // .common mode fires even while the status-bar menu is open (.eventTracking)
        RunLoop.main.add(timer, forMode: .common)
        accessibilityPollTimer = timer
    }

    // MARK: - Window management

    private func bringToFront(_ windowController: NSWindowController) {
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openLogsViewer() {
        guard let logger = logger else { return }
        let vc = logViewerWindowController ?? LogViewerWindowController(logger: logger)
        logViewerWindowController = vc
        bringToFront(vc)
        updateAccessibilityMenuItem()
    }

    /// Called by `LogViewerWindowController` when the window closes so the AppDelegate can release its reference
    func logViewerDidClose(_ controller: LogViewerWindowController) {
        if logViewerWindowController === controller {
            logViewerWindowController = nil
        }
    }

    @objc private func reloadLogs() {
        guard let logger = logger else { return }
        let vc = logViewerWindowController ?? LogViewerWindowController(logger: logger)
        logViewerWindowController = vc
        bringToFront(vc)
        vc.refresh()
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        bringToFront(preferencesWindowController!)
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        updateAccessibilityMenuItem()
    }

    @objc private func openLogsFolder() {
        if let url = logger?.logsDirectory {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openDonate() {
        if let url = URL(string: "https://ko-fi.com/twistermc") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openAboutPanel() {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.3"
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.size = NSSize(width: 128, height: 128)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: icon,
            .applicationName: bundleDisplayName(),
            .applicationVersion: version,
            .version: "",
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Settings API for PreferencesWindowController

    func setRedactWindowTitles(_ redact: Bool) {
        logger?.redactWindowTitles = redact
    }

    func setPollInterval(_ seconds: Double) {
        tracker?.setPollInterval(seconds)
    }
}


// Top-level application startup (keeps SwiftPM happy for tests)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
