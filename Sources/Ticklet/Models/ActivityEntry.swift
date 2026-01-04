import Foundation

public struct ActivityEntry: Codable, Equatable {
    public let appName: String
    public let windowTitle: String
    public let startTime: Date
    public var endTime: Date?

    public init(appName: String, windowTitle: String, startTime: Date = Date(), endTime: Date? = nil) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.startTime = startTime
        self.endTime = endTime
    }

    public var durationSeconds: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
}
