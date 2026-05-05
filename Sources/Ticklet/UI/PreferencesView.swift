import SwiftUI

struct PreferencesView: View {
    @AppStorage("pollIntervalSeconds") private var pollInterval = 1.0
    @AppStorage("use12HourTimeDisplay") private var use12Hour = false
    @AppStorage("redactWindowTitles") private var redactWindowTitles = false
    @AppStorage("showDockIcon") private var showDockIcon = true
    @AppStorage("showStatusItem") private var showStatusItem = true
    @AppStorage("automaticallyCheckForUpdates") private var automaticallyCheckForUpdates = true
    @AppStorage("logRetentionDays") private var logRetentionDays = 0
    @AppStorage("excludedApps") private var excludedApps = ""
    @State private var showingDeleteHistoryAlert = false

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
            Toggle("Automatically check for updates on launch", isOn: $automaticallyCheckForUpdates)

            Picker("Keep activity history", selection: $logRetentionDays) {
                Text("Forever").tag(0)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("1 year").tag(365)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Excluded apps (one per line)")
                TextEditor(text: $excludedApps)
                    .font(.body.monospaced())
                    .frame(minHeight: 110)
            }

            Button("Delete all recorded history…") {
                showingDeleteHistoryAlert = true
            }
        }
        .padding(20)
        .frame(width: 460)
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
        .onChange(of: logRetentionDays) {
            (NSApp.delegate as? AppDelegate)?.applyRetentionPolicy()
        }
        .alert("Delete all recorded history?", isPresented: $showingDeleteHistoryAlert) {
            Button("Delete", role: .destructive) {
                (NSApp.delegate as? AppDelegate)?.deleteHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every stored Ticklet CSV file from Application Support.")
        }
    }
}
