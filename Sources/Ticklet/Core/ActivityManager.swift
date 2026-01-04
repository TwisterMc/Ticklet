import Foundation

@MainActor
public final class ActivityManager {
    private let logger: LogWriter
    private let tracker: ActivityTracker
    private let calendar: Calendar
    private var entriesByDate: [String: [ActivityEntry]] = [:]
    private let fileDateFormatter: DateFormatter
    private let now: () -> Date

    public init(logger: LogWriter, tracker: ActivityTracker, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.logger = logger
        self.tracker = tracker
        self.calendar = calendar
        self.now = now

        fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"

        tracker.onEntryFinalized = { [weak self] entry in
            self?.handleFinalized(entry)
        }
    }

    public func start() {
        tracker.start()
    }

    public func stop() {
        tracker.stop()
        // flush today's entries
        flushAll() // best-effort
    }

    private func dateKey(for date: Date) -> String {
        return fileDateFormatter.string(from: date)
    }

    func handleFinalized(_ entry: ActivityEntry) {
        let key = dateKey(for: entry.startTime)

        // Append to in-memory list
        var list = entriesByDate[key] ?? []
        list.append(entry)
        entriesByDate[key] = list

        // Append to disk using append API to avoid overwriting existing data
        do {
            try logger.append(entries: [entry], for: entry.startTime)
        } catch {
            print("Failed to append log: \(error)")
        }

        NotificationCenter.default.post(name: .tickletEntryFinalized, object: entry)
    }

    public func flushAll() {
        for (key, list) in entriesByDate {
            guard let date = fileDateFormatter.date(from: key) else { continue }
            try? logger.write(entries: list, for: date)
        }
    }
}
