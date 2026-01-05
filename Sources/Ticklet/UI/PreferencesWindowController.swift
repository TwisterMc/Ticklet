import AppKit

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let checkbox = NSButton(checkboxWithTitle: "Show status item in menu bar", target: nil, action: nil)
    private let pollLabel = NSTextField(labelWithString: "Sampling interval (seconds):")
    private let pollField = NSTextField(string: "")
    private let pollStepper = NSStepper()
    private let frameDefaultsKey = "PreferencesWindowFrame"

    init() {
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
        checkbox.frame = NSRect(x: 20, y: 64, width: 380, height: 18)
        checkbox.target = self
        checkbox.action = #selector(toggleStatusItem(_:))
        content.addSubview(checkbox)

        let show = UserDefaults.standard.object(forKey: "showStatusItem") as? Bool ?? true
        checkbox.state = show ? .on : .off

        // Poll interval controls
        pollLabel.frame = NSRect(x: 20, y: 28, width: 200, height: 18)
        content.addSubview(pollLabel)

        pollField.frame = NSRect(x: 220, y: 24, width: 50, height: 22)
        pollField.isEditable = true
        pollField.alignment = .right
        pollField.target = self
        pollField.action = #selector(pollFieldChanged(_:))
        content.addSubview(pollField)

        pollStepper.frame = NSRect(x: 276, y: 24, width: 18, height: 22)
        pollStepper.minValue = 1
        pollStepper.maxValue = 60
        pollStepper.increment = 1
        pollStepper.valueWraps = false
        pollStepper.target = self
        pollStepper.action = #selector(pollStepperChanged(_:))
        content.addSubview(pollStepper)

        // Initialize value from UserDefaults or fallback
        let saved = UserDefaults.standard.double(forKey: "pollIntervalSeconds")
        let initial = saved > 0 ? saved : 1.0
        pollField.stringValue = String(Int(initial))
        pollStepper.integerValue = Int(initial)
    }

    // MARK: - Window frame persistence
    private func restoreWindowFrame() {
        guard let w = window else { return }
        if let rectString = UserDefaults.standard.string(forKey: frameDefaultsKey) {
            let r = NSRectFromString(rectString)
            w.setFrame(r, display: false)
        } else {
            w.center()
        }
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }

    private func saveWindowFrame() {
        guard let w = window else { return }
        let s = NSStringFromRect(w.frame)
        UserDefaults.standard.set(s, forKey: frameDefaultsKey)
    }

    @objc private func toggleStatusItem(_ sender: NSButton) {
        let show = (sender.state == .on)
        UserDefaults.standard.set(show, forKey: "showStatusItem")
        if let app = NSApp.delegate as? AppDelegate {
            app.showStatusItem = show
        }
    }

    @objc private func pollStepperChanged(_ sender: NSStepper) {
        let val = sender.doubleValue
        pollField.stringValue = String(Int(val))
        savePollInterval(val)
    }

    @objc private func pollFieldChanged(_ sender: NSTextField) {
        let s = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Double(s), v >= 1.0 {
            let val = floor(v)
            pollStepper.doubleValue = val
            pollField.stringValue = String(Int(val))
            savePollInterval(val)
        } else {
            // reset to stepper's value
            pollField.stringValue = String(Int(pollStepper.doubleValue))
        }
    }

    private func savePollInterval(_ seconds: Double) {
        UserDefaults.standard.set(seconds, forKey: "pollIntervalSeconds")
        if let app = NSApp.delegate as? AppDelegate {
            app.tracker?.setPollInterval(seconds)
        }
    }
}
