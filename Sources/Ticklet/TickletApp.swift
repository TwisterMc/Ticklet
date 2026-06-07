import SwiftUI

@main
struct TickletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.openPreferences()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
