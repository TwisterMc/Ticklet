import AppKit
import UniformTypeIdentifiers

public final class LogViewerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let tableView = NSTableView()
    private let scroll = NSScrollView()
    private let datePicker = NSDatePicker()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let todayButton = NSButton(title: "Today", target: nil, action: nil)
    private let refreshButton = NSButton()
    private var entries: [ActivityEntry] = []
    private let logger: CSVLogger
    private let frameDefaultsKey = "LogViewerWindowFrame"

    // Cache app icons by app name for performance
    private var appIconCache: [String: NSImage] = [:]


    // History for back/forward navigation (stores startOfDay dates)
    private var history: [Date] = []
    private var historyIndex: Int = -1

    public init(logger: CSVLogger) {
        self.logger = logger
        let defaultRect = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: defaultRect, styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Ticklet Logs"
        window.delegate = self
        restoreWindowFrame()
        setupUI()
        // initialize history with today
        let today = Calendar.current.startOfDay(for: Date())
        pushToHistory(today)
        datePicker.dateValue = today
        load(date: today, recordHistory: false)
        // restore any previously saved sort descriptor
        restoreSortDescriptor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        // Back / Forward / Today controls
        if let backImage = NSImage(systemSymbolName: "arrowshape.backward.fill", accessibilityDescription: "Back") {
            backImage.isTemplate = true
            backButton.image = backImage
            backButton.imagePosition = .imageOnly
            backButton.contentTintColor = .labelColor
            backButton.setButtonType(.momentaryPushIn)
            backButton.bezelStyle = .texturedRounded
            backButton.isBordered = true
            backButton.frame = NSRect(x: 10, y: content.bounds.height - 40, width: 28, height: 24)
            backButton.autoresizingMask = [.minYMargin]
            backButton.target = self
            backButton.action = #selector(goBack)
            backButton.toolTip = "Back (previous date)"
            content.addSubview(backButton)
        } else {
            // Fallback to text if SF Symbol not available
            backButton.title = "◀"
            backButton.setButtonType(.momentaryPushIn)
            backButton.bezelStyle = .rounded
            backButton.frame = NSRect(x: 10, y: content.bounds.height - 40, width: 28, height: 24)
            backButton.autoresizingMask = [.minYMargin]
            backButton.target = self
            backButton.action = #selector(goBack)
            backButton.toolTip = "Back (previous date)"
            content.addSubview(backButton)
        }

        if let fwdImage = NSImage(systemSymbolName: "arrowshape.forward.fill", accessibilityDescription: "Forward") {
            fwdImage.isTemplate = true
            forwardButton.image = fwdImage
            forwardButton.imagePosition = .imageOnly
            forwardButton.contentTintColor = .labelColor
            forwardButton.setButtonType(.momentaryPushIn)
            forwardButton.bezelStyle = .texturedRounded
            forwardButton.isBordered = true
            forwardButton.frame = NSRect(x: 44, y: content.bounds.height - 40, width: 28, height: 24)
            forwardButton.autoresizingMask = [.minYMargin]
            forwardButton.target = self
            forwardButton.action = #selector(goForward)
            forwardButton.toolTip = "Forward (next date)"
            content.addSubview(forwardButton)
        } else {
            forwardButton.title = "▶"
            forwardButton.setButtonType(.momentaryPushIn)
            forwardButton.bezelStyle = .rounded
            forwardButton.frame = NSRect(x: 44, y: content.bounds.height - 40, width: 28, height: 24)
            forwardButton.autoresizingMask = [.minYMargin]
            forwardButton.target = self
            forwardButton.action = #selector(goForward)
            forwardButton.toolTip = "Forward (next date)"
            content.addSubview(forwardButton)
        }

        // Today button (text)
        todayButton.setButtonType(.momentaryPushIn)
        todayButton.bezelStyle = .rounded
        todayButton.isBordered = true
        todayButton.frame = NSRect(x: 78, y: content.bounds.height - 40, width: 64, height: 24)
        todayButton.autoresizingMask = [.minYMargin]
        todayButton.target = self
        todayButton.action = #selector(goToday)
        todayButton.toolTip = "Go to today"
        content.addSubview(todayButton)

        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.frame = NSRect(x: 150, y: content.bounds.height - 40, width: 200, height: 24)
        datePicker.autoresizingMask = [.minYMargin]
        datePicker.target = self
        datePicker.action = #selector(dateChanged)
        datePicker.dateValue = Date()
        content.addSubview(datePicker)

        // Refresh button to reload current day's logs
        refreshButton.title = "Refresh"
        refreshButton.setButtonType(.momentaryPushIn)
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: content.bounds.width - 90, y: content.bounds.height - 40, width: 80, height: 24)
        refreshButton.autoresizingMask = [.minYMargin, .minXMargin]
        refreshButton.target = self
        refreshButton.action = #selector(refreshLogs)
        refreshButton.toolTip = "Reload logs for selected date"
        content.addSubview(refreshButton)

        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.frame = NSRect(x: 10, y: 10, width: content.bounds.width - 20, height: content.bounds.height - 60)
        scroll.autoresizingMask = [.width, .height]
        // ensure tableView fills the scroll area
        tableView.frame = scroll.bounds
        tableView.autoresizingMask = [.width, .height]
        content.addSubview(scroll)

        let col1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        col1.title = "Time"
        col1.width = 200
        // sort by startTime (newest first by default)
        col1.sortDescriptorPrototype = NSSortDescriptor(key: "startTime", ascending: false)
        tableView.addTableColumn(col1)

        let col2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("duration"))
        col2.title = "Duration"
        col2.width = 100
        col2.sortDescriptorPrototype = NSSortDescriptor(key: "durationSeconds", ascending: false)
        tableView.addTableColumn(col2)

        // App column includes an icon and the app name
        let col3 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        col3.title = "App"
        col3.width = 240
        col3.sortDescriptorPrototype = NSSortDescriptor(key: "appName", ascending: true)
        tableView.addTableColumn(col3)

        let col4 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        col4.title = "Window"
        col4.width = 300
        col4.sortDescriptorPrototype = NSSortDescriptor(key: "windowTitle", ascending: true)
        tableView.addTableColumn(col4)

        // Ensure the table is view-based and has a header
        tableView.headerView = NSTableHeaderView()
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowSizeStyle = .default

        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 22
    }

    @objc private func dateChanged() {
        load(date: datePicker.dateValue)
    }

    @objc private func refreshLogs() {
        load(date: datePicker.dateValue, recordHistory: false)
    }

    /// Public refresh entry point (usable from menu actions)
    @objc public func refresh() {
        refreshLogs()
    }

    public func load(date: Date, recordHistory: Bool = true) {
        // normalize to start of day for consistent file lookup
        let keyDate = Calendar.current.startOfDay(for: date)
        if recordHistory {
            pushToHistory(keyDate)
        }
        do {
            entries = try logger.readEntries(for: keyDate)
            // Apply any current sort descriptor and reload
            sortEntries()
            DispatchQueue.main.async {
                if self.tableView.numberOfRows > 0 {
                    self.tableView.scrollRowToVisible(0)
                }
                self.updateNavigationButtons()
            }
        } catch {
            NSLog("[Ticklet] LogViewer.load error: \(error)")
            entries = []
            sortEntries()
            DispatchQueue.main.async { self.updateNavigationButtons() }
        }
    }

    // MARK: - Table Data
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return entries.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let e = entries[row]
        let id = tableColumn!.identifier.rawValue
        let text: String
        if id == "time" {
            let s = DateFormatter()
            s.dateFormat = "HH:mm:ss"
            text = s.string(from: e.startTime)
        } else if id == "duration" {
            if let d = e.durationSeconds {
                text = formatDuration(Int(d))
            } else {
                text = ""
            }
        } else if id == "app" {
            text = e.appName
        } else {
            text = e.windowTitle
        }
        // Use a view-based cell for more reliable styling across appearances
        let cellView = NSTableCellView()

        if id == "app" {
            // Create an image view for the app icon and a text field for the app name
            let iv = NSImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.imageScaling = .scaleProportionallyDown
            iv.image = appIcon(for: text)
            iv.setContentHuggingPriority(.required, for: .horizontal)
            iv.setContentCompressionResistancePriority(.required, for: .horizontal)
            iv.wantsLayer = false
            cellView.addSubview(iv)

            let tf = NSTextField(labelWithString: text)
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.textColor = .labelColor
            tf.isBezeled = false
            tf.drawsBackground = false
            tf.lineBreakMode = .byTruncatingTail
            cellView.addSubview(tf)

            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 6),
                iv.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 16),
                iv.heightAnchor.constraint(equalToConstant: 16),

                tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
                tf.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -6),
                tf.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 1),
                tf.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -1),
            ])

            cellView.identifier = NSUserInterfaceItemIdentifier(id + "Cell")
            return cellView
        }

        let tf = NSTextField(labelWithString: text)
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.textColor = .labelColor
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.lineBreakMode = .byTruncatingTail
        cellView.addSubview(tf)
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 6),
            tf.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -6),
            tf.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 1),
            tf.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -1),
        ])
        cellView.identifier = NSUserInterfaceItemIdentifier(id + "Cell")
        return cellView
    }

    // MARK: - App icon helpers

    private func formatDuration(_ seconds: Int) -> String {
        var s = seconds
        if s < 0 { s = 0 }
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if secs > 0 { parts.append("\(secs)s") }
        if parts.isEmpty { return "0s" }
        return parts.joined(separator: " ")
    }

    private func appIcon(for appName: String) -> NSImage {
        if let cached = appIconCache[appName] { return cached }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }), let icon = running.icon {
            appIconCache[appName] = icon
            return icon
        }
        // Use the generic application icon as a fallback
        if let generic = NSImage(named: NSImage.applicationIconName) {
            appIconCache[appName] = generic
            return generic
        }
        if #available(macOS 12.0, *) {
            let generic = NSWorkspace.shared.icon(for: UTType.application)
            appIconCache[appName] = generic
            return generic
        } else {
            let generic = NSWorkspace.shared.icon(forFileType: "app")
            appIconCache[appName] = generic
            return generic
        }
    }

    // MARK: - Navigation

    // MARK: - Sorting
    public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        sortEntries()
        saveSortDescriptor()
    }

    private func sortEntries() {
        let sds = tableView.sortDescriptors
        guard let sd = sds.first, let key = sd.key else {
            tableView.reloadData()
            return
        }
        let ascending = sd.ascending
        entries.sort { a, b in
            switch key {
            case "startTime":
                return ascending ? a.startTime < b.startTime : a.startTime > b.startTime
            case "durationSeconds":
                let da = a.durationSeconds ?? -1
                let db = b.durationSeconds ?? -1
                return ascending ? da < db : da > db
            case "appName":
                let cmp = a.appName.localizedCaseInsensitiveCompare(b.appName)
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            case "windowTitle":
                let cmp = a.windowTitle.localizedCaseInsensitiveCompare(b.windowTitle)
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            default:
                return true
            }
        }
        tableView.reloadData()
    }

    private let sortDefaultsKey = "LogViewerSortDescriptor"
    private func saveSortDescriptor() {
        guard let sd = tableView.sortDescriptors.first, let key = sd.key else { return }
        let dict: [String: Any] = ["key": key, "ascending": sd.ascending]
        UserDefaults.standard.set(dict, forKey: sortDefaultsKey)
    }

    private func restoreSortDescriptor() {
        guard let dict = UserDefaults.standard.dictionary(forKey: sortDefaultsKey), let key = dict["key"] as? String, let ascending = dict["ascending"] as? Bool else { return }
        let sd = NSSortDescriptor(key: key, ascending: ascending)
        tableView.sortDescriptors = [sd]
        sortEntries()
    }
    private func pushToHistory(_ date: Date) {
        // collapse any forward history and append
        if historyIndex < history.count - 1 {
            history = Array(history.prefix(upTo: historyIndex + 1))
        }
        // avoid duplicate consecutive entries
        if let last = history.last, Calendar.current.isDate(last, inSameDayAs: date) {
            history[history.count - 1] = date
            historyIndex = history.count - 1
            return
        }
        history.append(date)
        historyIndex = history.count - 1
        updateNavigationButtons()
    }

    private func updateNavigationButtons() {
        let today = Calendar.current.startOfDay(for: Date())
        let selected = Calendar.current.startOfDay(for: datePicker.dateValue)
        // Back / Forward now move the date picker by one day
        backButton.isEnabled = true
        // Forward only allowed when the selected date is before today
        forwardButton.isEnabled = selected < today
        todayButton.isEnabled = !Calendar.current.isDate(selected, inSameDayAs: today)

    }

    @objc private func goBack() {
        let current = datePicker.dateValue
        if let prev = Calendar.current.date(byAdding: .day, value: -1, to: current) {
            datePicker.dateValue = prev
            load(date: prev, recordHistory: false)
        }
    }

    @objc private func goForward() {
        let current = datePicker.dateValue
        if let next = Calendar.current.date(byAdding: .day, value: 1, to: current) {
            let today = Calendar.current.startOfDay(for: Date())
            let nextStart = Calendar.current.startOfDay(for: next)
            // Prevent going into future beyond today
            if nextStart <= today {
                datePicker.dateValue = next
                load(date: next, recordHistory: false)
            }
        }
    }

    @objc private func goToday() {
        let today = Calendar.current.startOfDay(for: Date())
        datePicker.dateValue = today
        load(date: today)
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

    public func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
        if let app = NSApp.delegate as? AppDelegate {
            app.logViewerDidClose(self)
        }
    }

    public func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }

    private func saveWindowFrame() {
        guard let w = window else { return }
        let s = NSStringFromRect(w.frame)
        UserDefaults.standard.set(s, forKey: frameDefaultsKey)
    }
}
