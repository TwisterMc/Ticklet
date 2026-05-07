import AppKit
import ApplicationServices
import SwiftUI

private func bundleDisplayName() -> String {
    return (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)
        ?? ProcessInfo.processInfo.processName
}

@MainActor
private final class PreferencesWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private let model: PreferencesWindowModel
    private let hostingController: NSHostingController<PreferencesContainerView>

    override init(window: NSWindow?) {
        let model = PreferencesWindowModel()
        self.model = model
        self.hostingController = NSHostingController(rootView: PreferencesContainerView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "TickletPreferencesToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        toolbar.centeredItemIdentifier = model.selectedPane.toolbarIdentifier
        toolbar.selectedItemIdentifier = model.selectedPane.toolbarIdentifier

        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        window.delegate = self
        window.center()

        resizeWindow(for: model.selectedPane, animate: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(selectedPane: PreferencesPane = .general) {
        selectPane(selectedPane, animate: false)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Keep controller alive for reopen while allowing normal close behavior.
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        PreferencesPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        PreferencesPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        PreferencesPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = PreferencesPane.allCases.first(where: { $0.toolbarIdentifier == itemIdentifier }) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.toolTip = pane.title
        item.image = NSImage(systemSymbolName: pane.systemImage, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(selectPaneFromToolbar(_:))
        return item
    }

    @objc private func selectPaneFromToolbar(_ sender: NSToolbarItem) {
        guard let pane = PreferencesPane.allCases.first(where: { $0.toolbarIdentifier == sender.itemIdentifier }) else {
            return
        }
        selectPane(pane, animate: true)
    }

    private func selectPane(_ pane: PreferencesPane, animate: Bool) {
        model.selectedPane = pane
        window?.toolbar?.selectedItemIdentifier = pane.toolbarIdentifier
        window?.toolbar?.centeredItemIdentifier = pane.toolbarIdentifier
        resizeWindow(for: pane, animate: animate)
    }

    private func resizeWindow(for pane: PreferencesPane, animate: Bool) {
        guard let window else { return }

        let targetContentSize = measuredContentSize(for: pane)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize))
        frame.origin.x = window.frame.origin.x
        frame.origin.y = window.frame.maxY - frame.size.height
        window.setFrame(frame, display: true, animate: animate)
    }

    private func measuredContentSize(for pane: PreferencesPane) -> NSSize {
        let measuringView = NSHostingView(rootView: PreferencesContentView(selectedPane: pane))
        measuringView.layoutSubtreeIfNeeded()

        var fittingSize = measuringView.fittingSize
        fittingSize.width = max(fittingSize.width, pane.contentWidth)
        return fittingSize
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var logger: CSVLogger?
    private var tracker: ActivityTracker?
    private var manager: ActivityManager?
    private var accessibilityPollTimer: Timer?
    private lazy var preferencesWindowController = PreferencesWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[Ticklet] applicationDidFinishLaunching")

        let showDock = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)

        let appName = bundleDisplayName()
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: appName)
        appMenuItem.submenu = appMenu
        let aboutItem = NSMenuItem(title: "About \(appName)", action: #selector(openAboutPanel), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        let checkUpdatesAppItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdatesAppItem.target = self
        appMenu.addItem(checkUpdatesAppItem)
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(quit), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        let reloadItem = NSMenuItem(title: "Reload Logs", action: #selector(reloadLogs), keyEquivalent: "r")
        reloadItem.target = self
        reloadItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(reloadItem)

        NSApp.mainMenu = mainMenu

        let menu = buildStatusMenu()
        statusMenu = menu

        let show = UserDefaults.standard.object(forKey: "showStatusItem") as? Bool ?? true
        self.showStatusItem = show
        if show {
            createStatusItem(with: menu)
        }

        if !AXIsProcessTrusted() {
            startAccessibilityPolling()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.promptForAccessibilityIfNeeded()
            }
        }

        do {
            logger = try CSVLogger()
            logger?.redactWindowTitles = UserDefaults.standard.bool(forKey: "redactWindowTitles")
            tracker = ActivityTracker()
            let savedInterval = UserDefaults.standard.double(forKey: "pollIntervalSeconds")
            if savedInterval >= 0.1 && savedInterval <= 60.0 {
                tracker?.setPollInterval(savedInterval)
            }
            manager = ActivityManager(logger: logger!, tracker: tracker!)
            tracker?.start()
            applyRetentionPolicy()

            NotificationCenter.default.addObserver(forName: .tickletEntryFinalized, object: nil, queue: .main) { [weak self] n in
                guard let entry = n.object as? ActivityEntry else { return }
                let appName = entry.appName
                Task { @MainActor in
                    self?.updateStatusIcon(isIdle: appName == "[IDLE]")
                }
            }

            updateAccessibilityMenuItem()
            if UserDefaults.standard.object(forKey: "automaticallyCheckForUpdates") as? Bool ?? true {
                UpdateChecker.shared.checkForUpdates(silentIfCurrent: true)
            }

        } catch {
            print("Failed to initialize logger: \(error)")
            let alert = NSAlert()
            alert.messageText = "Ticklet Could Not Start Logging"
            alert.informativeText = "The log storage location could not be initialized.\n\n\(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.runModal()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let confirmBeforeQuit = UserDefaults.standard.object(forKey: "confirmBeforeQuit") as? Bool ?? true
        guard confirmBeforeQuit else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Quit Ticklet?"
        alert.informativeText = "Activity will no longer be logged while Ticklet is not running."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        manager?.stop()
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

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

        let checkUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdates.target = self
        menu.addItem(checkUpdates)

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
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }
        menu.delegate = self
        statusItem?.menu = menu

        if let btn = statusItem?.button {
            if let img = makeStatusImage() {
                img.isTemplate = true
                btn.image = img
            }
            btn.imagePosition = .imageOnly
            btn.alphaValue = 1.0
            btn.setAccessibilityLabel("Ticklet — activity tracking")
        }

        updateAccessibilityMenuItem()
    }

    private func removeStatusItem() {
        if let si = statusItem {
            NSStatusBar.system.removeStatusItem(si)
            statusItem = nil
        }
    }

    private func makeStatusImage() -> NSImage? {
        NSImage(systemSymbolName: "person.crop.circle.badge.clock", accessibilityDescription: "Ticklet")
    }

    private func updateStatusIcon(isIdle: Bool) {
        guard let btn = statusItem?.button else { return }
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

    private func requestAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc private func openAccessibilityPreferences() {
        requestAccessibilityAccess()
        startAccessibilityPolling()
    }

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
        RunLoop.main.add(timer, forMode: .common)
        accessibilityPollTimer = timer
    }

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
        preferencesWindowController.show()
    }

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

    @objc private func checkForUpdates() {
        UpdateChecker.shared.checkForUpdates()
    }

    @objc private func openAboutPanel() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: bundleDisplayName(),
        ]
        if let icon = NSApp.applicationIconImage {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func setRedactWindowTitles(_ redact: Bool) {
        logger?.redactWindowTitles = redact
    }

    func setPollInterval(_ seconds: Double) {
        tracker?.setPollInterval(seconds)
    }

    func setShowDockIcon(_ show: Bool) {
        UserDefaults.standard.set(show, forKey: "showDockIcon")
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    func applyRetentionPolicy() {
        let retentionDays = UserDefaults.standard.integer(forKey: "logRetentionDays")
        guard let logger else { return }

        do {
            try logger.applyRetentionPolicy(retentionDays: retentionDays)
            logViewerWindowController?.refresh()
        } catch {
            NSLog("[Ticklet] Failed applying retention policy: \(error)")
        }
    }

    func deleteHistory() {
        guard let logger else { return }

        do {
            try logger.deleteAllLogs()
            logViewerWindowController?.refresh()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Delete History"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
