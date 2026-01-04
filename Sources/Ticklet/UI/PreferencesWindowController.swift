import AppKit

public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let checkbox = NSButton(checkboxWithTitle: "Show status item in menu bar", target: nil, action: nil)
    private let frameDefaultsKey = "PreferencesWindowFrame"

    public init() {
        let defaultRect = NSRect(x: 0, y: 0, width: 420, height: 120)
        let window = NSWindow(contentRect: defaultRect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Preferences"
        window.delegate = self
        restoreWindowFrame()
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        checkbox.frame = NSRect(x: 20, y: 40, width: 380, height: 18)
        checkbox.target = self
        checkbox.action = #selector(toggleStatusItem(_:))
        content.addSubview(checkbox)

        let show = UserDefaults.standard.object(forKey: "showStatusItem") as? Bool ?? true
        checkbox.state = show ? .on : .off
    }

    // MARK: - Window frame persistence
    private func restoreWindowFrame() {
        guard let w = window else { return }
        if let rectString = UserDefaults.standard.string(forKey: frameDefaultsKey) {
            let r = NSRectFromString(rectString)
            w.setFrame(r, display: false)
            NSLog("[Ticklet] Preferences window restored frame: \(r)")
        } else {
            w.center()
            NSLog("[Ticklet] Preferences window centered")
        }
    }

    public func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
    }

    public func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }

    private func saveWindowFrame() {
        guard let w = window else { return }
        let s = NSStringFromRect(w.frame)
        UserDefaults.standard.set(s, forKey: frameDefaultsKey)
        NSLog("[Ticklet] Preferences window saved frame: \(w.frame)")
    }

    @objc private func toggleStatusItem(_ sender: NSButton) {
        let show = (sender.state == .on)
        UserDefaults.standard.set(show, forKey: "showStatusItem")
        if let app = NSApp.delegate as? AppDelegate {
            app.showStatusItem = show
        }
    }
}
