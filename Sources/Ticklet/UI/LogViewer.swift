import AppKit

public final class LogViewerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let scroll = NSScrollView()
    private let datePicker = NSDatePicker()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let todayButton = NSButton(title: "Today", target: nil, action: nil)
    private var entries: [ActivityEntry] = []
    private let logger: CSVLogger

    // History for back/forward navigation (stores startOfDay dates)
    private var history: [Date] = []
    private var historyIndex: Int = -1

    public init(logger: CSVLogger) {
        self.logger = logger
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Ticklet Logs"
        setupUI()
        // initialize history with today
        let today = Calendar.current.startOfDay(for: Date())
        pushToHistory(today)
        datePicker.dateValue = today
        load(date: today, recordHistory: false)
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
        tableView.addTableColumn(col1)

        let col2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("duration"))
        col2.title = "Duration"
        col2.width = 100
        tableView.addTableColumn(col2)

        let col3 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        col3.title = "App"
        col3.width = 200
        tableView.addTableColumn(col3)

        let col4 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        col4.title = "Window"
        col4.width = 300
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

    public func load(date: Date, recordHistory: Bool = true) {
        // normalize to start of day for consistent file lookup
        let keyDate = Calendar.current.startOfDay(for: date)
        if recordHistory {
            pushToHistory(keyDate)
        }
        do {
            entries = try logger.readEntries(for: keyDate)
            NSLog("[Ticklet] LogViewer.load date=\(keyDate) entries=\(entries.count)")
            tableView.reloadData()
            // diagnostic: log frames and row count so we can see whether the table is visible
            NSLog("[Ticklet] LogViewer diagnostics: rows=\(tableView.numberOfRows) tableFrame=\(tableView.frame) scrollFrame=\(scroll.frame) visibleRect=\(tableView.visibleRect) contentBounds=\(window?.contentView?.bounds ?? NSRect.zero)")
            // Ensure table is scrolled to top and inspect a few cell views for debugging
            DispatchQueue.main.async {
                if self.tableView.numberOfRows > 0 {
                    self.tableView.scrollRowToVisible(0)
                    let cols = self.tableView.tableColumns
                    for row in 0 ..< min(self.tableView.numberOfRows, 10) {
                        for (ci, col) in cols.enumerated() {
                            if let v = self.tableView.view(atColumn: ci, row: row, makeIfNecessary: false) {
                                NSLog("[Ticklet] cell view (row=\(row) col=\(col.identifier.rawValue)): \(v) subviews=\(v.subviews)")
                                if let tv = v.subviews.compactMap({ $0 as? NSTextField }).first {
                                    NSLog("[Ticklet] cell text (row=\(row) col=\(col.identifier.rawValue)): '\(tv.stringValue)'")
                                }
                            } else {
                                NSLog("[Ticklet] no cell view for row=\(row) col=\(col.identifier.rawValue)")
                            }
                        }
                    }
                }
                self.updateNavigationButtons()
            }
        } catch {
            NSLog("[Ticklet] LogViewer.load error: \(error)")
            entries = []
            tableView.reloadData()
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
                text = String(Int(d))
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

    // MARK: - Navigation
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
        NSLog("[Ticklet] history push: index=\(historyIndex) count=\(history.count) date=\(date)")
    }

    private func updateNavigationButtons() {
        let today = Calendar.current.startOfDay(for: Date())
        let selected = Calendar.current.startOfDay(for: datePicker.dateValue)
        // Back / Forward now move the date picker by one day
        backButton.isEnabled = true
        // Forward only allowed when the selected date is before today
        forwardButton.isEnabled = selected < today
        todayButton.isEnabled = !Calendar.current.isDate(selected, inSameDayAs: today)
        NSLog("[Ticklet] LogViewer navigation buttons - selected=\(selected) backEnabled=\(backButton.isEnabled) forwardEnabled=\(forwardButton.isEnabled) todayEnabled=\(todayButton.isEnabled)")
    }

    @objc private func goBack() {
        NSLog("[Ticklet] LogViewer.goBack invoked (current=\(datePicker.dateValue))")
        let current = datePicker.dateValue
        if let prev = Calendar.current.date(byAdding: .day, value: -1, to: current) {
            datePicker.dateValue = prev
            load(date: prev, recordHistory: false)
            NSLog("[Ticklet] navigation: back -> \(prev)")
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
                NSLog("[Ticklet] navigation: forward -> \(next)")
            }
        }
    }

    @objc private func goToday() {
        let today = Calendar.current.startOfDay(for: Date())
        datePicker.dateValue = today
        load(date: today)
        NSLog("[Ticklet] navigation: today -> \(today)")
    }
}
