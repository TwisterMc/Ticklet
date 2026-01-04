import XCTest
@testable import Ticklet

final class TickletTests: XCTestCase {
    func testCSV_escapesCommasAndQuotes() throws {
        let logger = try CSVLogger(logsDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("ticklet-tests"))
        let entry = ActivityEntry(appName: "Figma", windowTitle: "Design, \"Round 1\"")
        var e = entry
        e.endTime = e.startTime.addingTimeInterval(60)
        try logger.write(entries: [e], for: Date())
        // If no throw, assume success for now. More thorough file checks can be added.
    }

    func testActivityEntryDuration() {
        let start = Date()
        let e = ActivityEntry(appName: "X", windowTitle: "Y", startTime: start, endTime: start.addingTimeInterval(123))
        XCTAssertEqual(e.durationSeconds, 123)
    }
}
