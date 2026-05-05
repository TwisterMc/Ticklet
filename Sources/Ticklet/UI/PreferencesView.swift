import SwiftUI

struct PreferencesView: View {
    @AppStorage("pollIntervalSeconds") private var pollInterval = 1.0
    @AppStorage("use12HourTimeDisplay") private var use12Hour = false
    @AppStorage("redactWindowTitles") private var redactWindowTitles = false
    @AppStorage("showDockIcon") private var showDockIcon = true
    @AppStorage("showStatusItem") private var showStatusItem = true

    var body: some View {
        Form {
            Stepper("Sampling interval: \(pollInterval, specifier: "%.1f") seconds", value: $pollInterval, in: 0.1...60.0, step: 0.5)
                .accessibilityValue("\(pollInterval, specifier: "%.1f") seconds")
                .accessibilityHint("Adjustable from 0.1 to 60 seconds, step 0.5")

            Divider()

            Toggle("Use 12-hour time in app display", isOn: $use12Hour)
            Toggle("Only log app names (hide window titles)", isOn: $redactWindowTitles)
            Toggle("Show Dock icon", isOn: $showDockIcon)
            Toggle("Show status item in menu bar", isOn: $showStatusItem)
        }
        .padding(20)
        .frame(width: 400)
        .onChange(of: pollInterval) {
            (NSApp.delegate as? AppDelegate)?.setPollInterval(pollInterval)
        }
        .onChange(of: redactWindowTitles) {
            (NSApp.delegate as? AppDelegate)?.setRedactWindowTitles(redactWindowTitles)
        }
        .onChange(of: showDockIcon) {
            (NSApp.delegate as? AppDelegate)?.setShowDockIcon(showDockIcon)
        }
        .onChange(of: showStatusItem) {
            (NSApp.delegate as? AppDelegate)?.showStatusItem = showStatusItem
        }
    }
}
