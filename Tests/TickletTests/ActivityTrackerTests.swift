import XCTest
@testable import Ticklet

@MainActor
final class ActivityTrackerTests: XCTestCase {
    func testDebouncePreventsNoise() {
        var now = Date()
        let tracker = ActivityTracker(now: { now })

        var finalized: [ActivityEntry] = []
        tracker.onEntryFinalized = { entry in
            finalized.append(entry)
        }

        // Start with App A
        tracker.observe(app: "A", windowTitle: "win1", at: now)

        // Change to B briefly (1s), then back to A — should not create a new finalized entry
        tracker.observe(app: "B", windowTitle: "win2", at: now.addingTimeInterval(1))
        now = now.addingTimeInterval(2)
        tracker.observe(app: "A", windowTitle: "win1", at: now)

        // advance time to ensure debounce would have fired if it were stable
        now = now.addingTimeInterval(10)
        tracker.observe(app: "A", windowTitle: "win1", at: now)

        XCTAssertTrue(finalized.isEmpty, "Transient change should not have finalized an entry")
    }

    func testStableChangeFinalizesPrevious() {
        var now = Date()
        let tracker = ActivityTracker(now: { now })

        var finalized: [ActivityEntry] = []
        tracker.onEntryFinalized = { entry in
            finalized.append(entry)
        }

        // Start with App A
        tracker.observe(app: "A", windowTitle: "win1", at: now)

        // New app B appears and remains for > debounceWindow
        let seen = now.addingTimeInterval(1)
        tracker.observe(app: "B", windowTitle: "win2", at: seen)

        // move forward to after debounce window
        now = seen.addingTimeInterval(tracker.debounceWindow + 1)
        tracker.observe(app: "B", windowTitle: "win2", at: now)

        XCTAssertEqual(finalized.count, 1)
        let prev = finalized[0]
        XCTAssertEqual(prev.appName, "A")
        XCTAssertNotNil(prev.endTime)
    }

    func testIdleDetectionFinalizesAndCreatesIdleEntry() {
        var now = Date()
        let tracker = ActivityTracker(now: { now })

        var finalized: [ActivityEntry] = []
        tracker.onEntryFinalized = { entry in
            finalized.append(entry)
        }

        // Start with App A at t0
        tracker.observe(app: "A", windowTitle: "win1", at: now)

        // Advance time to cross idle threshold
        now = now.addingTimeInterval(tracker.idleThreshold + 10)
        tracker.tick() // perform idle check

        XCTAssertEqual(finalized.count, 1)
        XCTAssertEqual(finalized[0].appName, "A")
        // Now there should be a currentEntry which is [IDLE]
    }
}
