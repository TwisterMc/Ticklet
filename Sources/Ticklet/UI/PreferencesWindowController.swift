import AppKit

public final class PreferencesWindowController: NSWindowController {
    private let checkbox = NSButton(checkboxWithTitle: "Show status item in menu bar", target: nil, action: nil)

    public init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Preferences"
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

    @objc private func toggleStatusItem(_ sender: NSButton) {
        let show = (sender.state == .on)
        UserDefaults.standard.set(show, forKey: "showStatusItem")
        if let app = NSApp.delegate as? AppDelegate {
            app.showStatusItem = show
        }
    }
}
