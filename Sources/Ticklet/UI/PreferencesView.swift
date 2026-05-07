import AppKit
import SwiftUI

enum PreferencesPane: String, CaseIterable, Identifiable {
    case tracking
    case display
    case privacy
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .tracking: return "Tracking"
        case .display: return "Display"
        case .privacy: return "Privacy"
        case .general: return "General"
        }
    }

    var systemImage: String {
        switch self {
        case .tracking: return "clock"
        case .display: return "display"
        case .privacy: return "hand.raised"
        case .general: return "gearshape"
        }
    }

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue: rawValue)
    }

    var contentWidth: CGFloat {
        switch self {
        case .tracking, .display, .privacy, .general:
            return 520
        }
    }
}

final class PreferencesWindowModel: ObservableObject {
    @Published var selectedPane: PreferencesPane = .general
}

struct PreferencesView: View {
    var body: some View {
        PreferencesContainerView(model: PreferencesWindowModel())
    }
}

struct PreferencesContainerView: View {
    @ObservedObject var model: PreferencesWindowModel

    var body: some View {
        PreferencesContentView(selectedPane: model.selectedPane)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct PreferencesContentView: View {
    let selectedPane: PreferencesPane

    var body: some View {
        Group {
            switch selectedPane {
            case .tracking:
                TrackingPrefsView()
            case .display:
                DisplayPrefsView()
            case .privacy:
                PrivacyPrefsView()
            case .general:
                GeneralPrefsView()
            }
        }
        .frame(width: selectedPane.contentWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TrackingPrefsView: View {
    @AppStorage("pollIntervalSeconds") private var pollInterval = 1.0
    @AppStorage("logRetentionDays") private var logRetentionDays = 0

    var body: some View {
        Form {
            Section {
                LabeledContent("Sampling interval") {
                    Stepper("\(pollInterval, specifier: "%.1f") seconds", value: $pollInterval, in: 0.1...60.0, step: 0.5)
                        .accessibilityValue("\(pollInterval, specifier: "%.1f") seconds")
                        .accessibilityHint("Adjustable from 0.1 to 60 seconds, step 0.5")
                        .frame(width: 160, alignment: .trailing)
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
                    .frame(width: 140, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: pollInterval) {
            (NSApp.delegate as? AppDelegate)?.setPollInterval(pollInterval)
        }
        .onChange(of: logRetentionDays) {
            (NSApp.delegate as? AppDelegate)?.applyRetentionPolicy()
        }
    }
}

private struct DisplayPrefsView: View {
    @AppStorage("use12HourTimeDisplay") private var use12Hour = false
    @AppStorage("showDockIcon") private var showDockIcon = true
    @AppStorage("showStatusItem") private var showStatusItem = true

    var body: some View {
        Form {
            Section {
                Toggle("Use 12-hour time in app display", isOn: $use12Hour)
                Toggle("Show Dock icon", isOn: $showDockIcon)
                Toggle("Show status item in menu bar", isOn: $showStatusItem)
            }
        }
        .formStyle(.grouped)
        .onChange(of: showDockIcon) {
            (NSApp.delegate as? AppDelegate)?.setShowDockIcon(showDockIcon)
        }
        .onChange(of: showStatusItem) {
            (NSApp.delegate as? AppDelegate)?.showStatusItem = showStatusItem
        }
    }
}

private struct PrivacyPrefsView: View {
    @AppStorage("redactWindowTitles") private var redactWindowTitles = false
    @AppStorage("excludedApps") private var excludedApps = ""

    var body: some View {
        Form {
            Section {
                Toggle("Only log app names (hide window titles)", isOn: $redactWindowTitles)
            }
            Section("Excluded Apps") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One app name per line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $excludedApps)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Excluded apps")
                        .accessibilityHint("Enter one app name per line to exclude it from tracking")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .onChange(of: redactWindowTitles) {
            (NSApp.delegate as? AppDelegate)?.setRedactWindowTitles(redactWindowTitles)
        }
    }
}

private struct GeneralPrefsView: View {
    @AppStorage("automaticallyCheckForUpdates") private var automaticallyCheckForUpdates = true
    @AppStorage("confirmBeforeQuit") private var confirmBeforeQuit = true
    @State private var showingDeleteHistoryAlert = false

    var body: some View {
        Form {
            Section {
                Toggle("Automatically check for updates on launch", isOn: $automaticallyCheckForUpdates)
                Toggle("Confirm before quitting", isOn: $confirmBeforeQuit)
            }
            Section {
                HStack {
                    Button("Delete All Recorded History…", role: .destructive) {
                        showingDeleteHistoryAlert = true
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .alert("Delete all recorded history?", isPresented: $showingDeleteHistoryAlert) {
            Button("Delete", role: .destructive) {
                (NSApp.delegate as? AppDelegate)?.deleteHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves every stored Ticklet CSV file to the Trash.")
        }
    }
}
