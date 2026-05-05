import XCTest
@testable import Ticklet

final class CSVLoggerTests: XCTestCase {
    func testWriteAndReadRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ticklet-test-\(UUID().uuidString)")
        let logger = try CSVLogger(logsDirectory: tempDir)

        let now = Date()
        var e = ActivityEntry(appName: "Figma", windowTitle: "Design, \"Round 1\"", startTime: now)
        e.endTime = now.addingTimeInterval(120)
        try logger.write(entries: [e], for: now)

        let read = try logger.readEntries(for: now)
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].appName, "Figma")
        XCTAssertEqual(read[0].windowTitle, "Design, \"Round 1\"")
    }

    func testReadMissingFileReturnsEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ticklet-test-\(UUID().uuidString)")
        let logger = try CSVLogger(logsDirectory: tempDir)

        let dateWithoutFile = Date()
        let read = try logger.readEntries(for: dateWithoutFile)
        XCTAssertTrue(read.isEmpty)
    }

    func testWriteAndReadRoundTripWithMultilineWindowTitle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ticklet-test-\(UUID().uuidString)")
        let logger = try CSVLogger(logsDirectory: tempDir)

        let now = Date()
        var entry = ActivityEntry(
            appName: "Notes",
            windowTitle: "Daily Notes\nLine Two\nLine Three",
            startTime: now
        )
        entry.endTime = now.addingTimeInterval(120)

        try logger.write(entries: [entry], for: now)

        let read = try logger.readEntries(for: now)
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].windowTitle, "Daily Notes\nLine Two\nLine Three")
    }

    func testRetentionDeletesOldFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ticklet-test-\(UUID().uuidString)")
        let logger = try CSVLogger(logsDirectory: tempDir)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let oldDate = calendar.date(byAdding: .day, value: -45, to: today)!
        let recentDate = calendar.date(byAdding: .day, value: -5, to: today)!

        var oldEntry = ActivityEntry(appName: "Old", windowTitle: "Old", startTime: oldDate)
        oldEntry.endTime = oldDate.addingTimeInterval(60)
        var recentEntry = ActivityEntry(appName: "Recent", windowTitle: "Recent", startTime: recentDate)
        recentEntry.endTime = recentDate.addingTimeInterval(60)

        try logger.write(entries: [oldEntry], for: oldDate)
        try logger.write(entries: [recentEntry], for: recentDate)
        try logger.applyRetentionPolicy(retentionDays: 30)

        XCTAssertTrue(try logger.readEntries(for: oldDate).isEmpty)
        XCTAssertEqual(try logger.readEntries(for: recentDate).count, 1)
    }

    func testDeleteAllLogsRemovesEveryCSV() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ticklet-test-\(UUID().uuidString)")
        let logger = try CSVLogger(logsDirectory: tempDir)

        let now = Date()
        var firstEntry = ActivityEntry(appName: "A", windowTitle: "A", startTime: now)
        firstEntry.endTime = now.addingTimeInterval(60)
        let later = now.addingTimeInterval(86_400)
        var secondEntry = ActivityEntry(appName: "B", windowTitle: "B", startTime: later)
        secondEntry.endTime = later.addingTimeInterval(60)

        try logger.write(entries: [firstEntry], for: now)
        try logger.write(entries: [secondEntry], for: later)
        try logger.deleteAllLogs()

        XCTAssertTrue(try logger.readEntries(for: now).isEmpty)
        XCTAssertTrue(try logger.readEntries(for: later).isEmpty)
    }

    func testLegacyLogsAreMigratedToApplicationSupportLocation() throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("ticklet-test-\(UUID().uuidString)")
        let logsDir = baseDir.appendingPathComponent("current", isDirectory: true)
        let legacyDir = baseDir.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        let now = Date()
        let filename = "ticklet-\(formattedDate(now)).csv"
        let csv = "start_time,end_time,duration_seconds,app_name,window_title\n"
            + "2025-01-01 10:00:00,2025-01-01 10:01:00,60,Figma,Design\n"
        try csv.write(to: legacyDir.appendingPathComponent(filename), atomically: true, encoding: .utf8)

        let logger = try CSVLogger(logsDirectory: logsDir, legacyLogsDirectory: legacyDir)
        let entries = try logger.readEntries(for: now)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.appName, "Figma")
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
