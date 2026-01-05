import Foundation

struct ActivityEntry: Codable, Equatable {
    let appName: String
    let windowTitle: String
    let startTime: Date
    var endTime: Date?

    init(appName: String, windowTitle: String, startTime: Date = Date(), endTime: Date? = nil) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.startTime = startTime
        self.endTime = endTime
    }

    var durationSeconds: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
}
