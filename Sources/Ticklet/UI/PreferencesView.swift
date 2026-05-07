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
        VStack(alignment: .leading, spacing: 0) {
            prefsSection("Tracking") {
                LabeledContent("Sampling interval") {
                    Stepper("\(pollInterval, specifier: "%.1f") seconds", value: $pollInterval, in: 0.1...60.0, step: 0.5)
                        .accessibilityValue("\(pollInterval, specifier: "%.1f") seconds")
                        .accessibilityHint("Adjustable from 0.1 to 60 seconds, step 0.5")
                }
                LabeledContent("Keep activity history") {
                    Picker("", selection: $logRetentionDays) {
                        Text("Forever").tag(0)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                Toggle("Only log app names (hide window titles)", isOn: $redactWindowTitles)
            }

            prefsDivider()

            prefsSection("Display") {
                Toggle("Use 12-hour time in app display", isOn: $use12Hour)
                Toggle("Show Dock icon", isOn: $showDockIcon)
                Toggle("Show status item in menu bar", isOn: $showStatusItem)
            }

            prefsDivider()

            prefsSection("Excluded Apps") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("One app name per line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $excludedApps)
                        .font(.body.monospaced())
                        .frame(minHeight: 90)
                        .accessibilityLabel("Excluded apps")
                        .accessibilityHint("Enter one app name per line to exclude it from tracking")
                }
            }

            prefsDivider()

            prefsSection("Updates") {
                Toggle("Automatically check for updates on launch", isOn: $automaticallyCheckForUpdates)
            }

            prefsDivider()

            prefsSection(nil) {
                Button("Delete All Recorded History…", role: .destructive) {
                    showingDeleteHistoryAlert = true
                }
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
            Text("This moves every stored Ticklet CSV file to the Trash.")
        }
    }

    @ViewBuilder
    private func prefsSection(_ title: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(.vertical, 12)
    }

    private func prefsDivider() -> some View {
        Divider()
    }
}
