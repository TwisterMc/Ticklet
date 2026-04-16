import Cocoa

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    private let releasesURL = URL(string: "https://api.github.com/repos/TwisterMc/Ticklet/releases?per_page=1")!
    private let releasesPageURL = URL(string: "https://github.com/TwisterMc/Ticklet/releases")!

    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)
            ?? "Ticklet"
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    private init() {}

    func checkForUpdates(silentIfCurrent: Bool = false) {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("\(appName)/\(appVersion)", forHTTPHeaderField: "User-Agent")

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    if http.statusCode == 404 {
                        if !silentIfCurrent { showNoReleases() }
                    } else if !silentIfCurrent {
                        showError(detail: "HTTP \(http.statusCode)")
                    }
                    return
                }

                guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    if !silentIfCurrent { showError(detail: "Unexpected response from GitHub.") }
                    return
                }

                guard let tagName = releases.first?["tag_name"] as? String else {
                    if !silentIfCurrent { showNoReleases() }
                    return
                }

                let latestVersion = tagName.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("v")
                    ? String(tagName.dropFirst())
                    : tagName

                presentResult(latestVersion: latestVersion, silentIfCurrent: silentIfCurrent)
            } catch {
                if !silentIfCurrent { showError(detail: error.localizedDescription) }
            }
        }
    }

    private func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        return alert
    }

    private func presentResult(latestVersion: String, silentIfCurrent: Bool) {
        let current = appVersion

        if isNewerVersion(latestVersion, than: current) {
            let alert = makeAlert()
            alert.messageText = "Update Available"
            alert.informativeText = "A new version of \(appName) is available: \(latestVersion)\n\nYou're currently running version \(current)."
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Not Now")
            alert.alertStyle = .informational
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releasesPageURL)
            }
        } else if !silentIfCurrent {
            let alert = makeAlert()
            alert.messageText = "\(appName) is Up to Date"
            alert.informativeText = "You're running the latest version (\(current))."
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    private func showNoReleases() {
        let alert = makeAlert()
        alert.messageText = "No Releases Found"
        alert.informativeText = "There are no published releases for \(appName) yet."
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func showError(detail: String = "") {
        let alert = makeAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not reach GitHub to check for updates. Please try again later."
            + (detail.isEmpty ? "" : "\n\n(\(detail))")
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let lhs = versionComponents(candidate)
        let rhs = versionComponents(current)
        let maxLen = max(lhs.count, rhs.count)
        for i in 0..<maxLen {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private func versionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }
}
