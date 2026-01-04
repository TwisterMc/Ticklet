import XCTest
@testable import Ticklet

final class MockLogger: LogWriter {
    var written: [(date: Date, entries: [ActivityEntry])] = []
    func write(entries: [ActivityEntry], for date: Date) throws {
        written.append((date: date, entries: entries))
    }
    func readEntries(for date: Date) throws -> [ActivityEntry] {
        return written.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?.entries ?? []
    }
    func append(entries: [ActivityEntry], for date: Date) throws {
        if let idx = written.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            var existing = written[idx].entries
            existing.append(contentsOf: entries)
            written[idx].entries = existing
        } else {
            written.append((date: date, entries: entries))
        }
    }
}

final class ActivityManagerTests: XCTestCase {
    func testManagerWritesOnFinalized() {
        var now = Date()
        let tracker = ActivityTracker(now: { now })
        let mock = MockLogger()
        let manager = ActivityManager(logger: mock, tracker: tracker, now: { now })

        // Simulate finalized entry
        let entry = ActivityEntry(appName: "A", windowTitle: "win", startTime: now)
        var e = entry
        e.endTime = now.addingTimeInterval(60)
        manager.handleFinalized(e)

        XCTAssertEqual(mock.written.count, 1)
        XCTAssertEqual(mock.written[0].entries.count, 1)
    }

    func testHandleFinalizedMergesExistingFileEntries() throws {
        // create a temporary directory for logs
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let logger = try CSVLogger(logsDirectory: tmp)
        let tracker = ActivityTracker()
        let manager = ActivityManager(logger: logger, tracker: tracker)

        // create an existing entry and write it to disk to simulate prior run
        let cal = Calendar.current
        let date = cal.startOfDay(for: Date())
        let e1 = ActivityEntry(appName: "AppA", windowTitle: "win1", startTime: date.addingTimeInterval(3600), endTime: date.addingTimeInterval(3610))
        try logger.write(entries: [e1], for: e1.startTime)

        // Now finalize a new entry for the same date
        let e2 = ActivityEntry(appName: "AppB", windowTitle: "win2", startTime: date.addingTimeInterval(3620), endTime: date.addingTimeInterval(3625))
        manager.handleFinalized(e2)

        // Read back file and assert both entries present
        let read = try logger.readEntries(for: e2.startTime)
        XCTAssertTrue(read.contains(where: { $0.appName == "AppA" && $0.windowTitle == "win1" }))
        XCTAssertTrue(read.contains(where: { $0.appName == "AppB" && $0.windowTitle == "win2" }))
        XCTAssertEqual(read.count, 2)
    }
}
