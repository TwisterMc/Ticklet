import XCTest
@testable import Ticklet

final class CSVLoggerTests2: XCTestCase {
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
}
