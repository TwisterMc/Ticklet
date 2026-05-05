import Foundation

@MainActor
final class ActivityManager {
    private let logger: LogWriter
    private let tracker: ActivityTracker

    init(logger: LogWriter, tracker: ActivityTracker) {
        self.logger = logger
        self.tracker = tracker

        tracker.onEntryFinalized = { [weak self] entry in
            // Ensure we invoke the handler on the MainActor since ActivityManager is @MainActor
            Task { @MainActor in
                self?.handleFinalized(entry)
            }
        }
    }

    func start() {
        tracker.start()
    }

    func stop() {
        tracker.stop()
    }

    @MainActor func handleFinalized(_ entry: ActivityEntry) {
        if isExcludedApp(entry.appName) {
            return
        }

        do {
            try logger.append(entries: [entry], for: entry.startTime)
        } catch {
            NSLog("[Ticklet] Error appending entry to log: \(error)")
        }

        NotificationCenter.default.post(name: .tickletEntryFinalized, object: entry)
    }

    private func isExcludedApp(_ appName: String) -> Bool {
        let rawValue = UserDefaults.standard.string(forKey: "excludedApps") ?? ""
        let excludedApps = rawValue
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return excludedApps.contains(appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
