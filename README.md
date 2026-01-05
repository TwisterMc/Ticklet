# Ticklet

Ticklet quietly records which applications and windows you use during the day and saves the results to simple CSV files so you can answer: "What did I spend my time on today?"

This README is for end users — concise install and usage instructions are below.

---

## What Ticklet does

- Runs in the background and records the frontmost app and focused window title at short intervals.
- Saves entries to daily CSV files at: `~/Library/Logs/Ticklet/` (one file per date).
- Provides a built-in **Logs** viewer for inspecting and navigating days.

---

## Privacy & Permissions

- Ticklet requires **Accessibility** permission to read window titles. Without this permission Ticklet will still run but window titles may be empty or incomplete.
- Window titles may contain sensitive information (document names, emails, etc.). You should:
  - Review the data stored in `~/Library/Logs/Ticklet/` and delete files you don’t want to keep
  - Use the Preferences to disable the status item if you prefer minimal UI
  - Contact support if you want a data-redaction option (available upon request)

---

## Install

- Preferred: download a prebuilt `.app` from the project's GitHub Releases page — releases may include both **Intel (x86_64)** and **Apple Silicon (arm64)** builds when available; artifacts may be named like `Ticklet-<arch>.zip` (recommended for non‑developers).
- Alternative (developer): build locally with Swift and use the included bundle helper script to create an `.app` wrapper (see **DEVELOPER.md** for details).

If you install from a release, double‑click the `.app` and allow system prompts as needed.

---

## Granting Accessibility permission

1. Launch Ticklet (double‑click the app in Finder).
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Click the **+** button and add **Ticklet.app**, then ensure the checkbox next to it is enabled.
4. Quit and re-open Ticklet (or log out and log back in) so the permission takes effect.

When Accessibility is enabled, Ticklet will be able to read window titles and produce richer logs.

**⚠️ Important Note About Updates:**

- If you build/download a new version of Ticklet, macOS will treat it as a different app
- You'll need to re-authorize Accessibility permissions for each new build
- This is because the app uses ad-hoc signing (code signature changes with each build)
- To avoid this: install Ticklet to a fixed location (e.g., `/Applications/Ticklet.app`) and always replace the same file when updating

---

## Using the app

- Menu Bar: Ticklet can run with an optional status item (icon) — toggle this in Preferences.
- Sampling interval: set the recording interval (seconds) in **Preferences** — default is 1 second (supported range: 1–60). Higher frequency produces more detailed logs but may increase disk usage and CPU.
- Logs Viewer: choose **View Logs…** from the Ticklet menu to open the Log Viewer window.
  - Use the date controls (Back / Forward / Today) to navigate days.
  - Click column headers to sort entries; sorting is remembered.
  - The **Duration** column shows a compact, human-friendly format (e.g., `30s`, `1m 30s`, `1h 30s`); the underlying CSV stores duration as seconds.
  - Each row shows the app name **with its icon** (when available) for easier scanning.
  - Use the **Refresh** button to reload the current day's logs, or press **⌘R** (Reload Logs) — it performs the same refresh action.
  - When you open **View Logs…**, Ticklet activates and the Log Viewer window is brought to the front.
  - Window position and size are remembered between launches.
- Logs are stored as CSV; each row includes start time, end time, duration (seconds), app name, and window title.

---

## Troubleshooting

- If logs are empty or missing titles: verify Accessibility permission and restart the app.
- If Ticklet doesn’t appear in Accessibility list: use Finder to open the `.app` once (this registers it with Launch Services), then add it in System Settings.
- If the app behaves oddly after granting permission, quit it and re-open it from Finder.

### App Permissions & Security

- When you install Ticklet, macOS may ask you to grant Accessibility permission so the app can read window titles — this is normal. Follow the steps under **Granting Accessibility permission** above to enable it.
- If Ticklet asks for permission again after an update, open it from your **Applications** folder and re-enable the permission; if prompts continue, download the official build from the project's Releases page or contact the maintainer for help.

(Developer note: More technical signing and notarization guidance is available in `DEVELOPER.md`.)

## Packaging & Signing (developer note) 🔐

- For local builds the included packaging helper (`./scripts/make_app_bundle.sh`) will perform an **ad‑hoc sign by default** so the produced `.app` behaves better when double‑clicked for testing (you do not need to set `SIGN_IDENTITY` to get an ad‑hoc sign).

- To explicitly perform ad‑hoc signing (testing):

```bash
./scripts/make_app_bundle.sh .build/release/Ticklet ./artifacts/Ticklet.app com.thomas.Ticklet
```

- To sign for distribution, set `SIGN_IDENTITY` to your Developer ID identity. You can also provide `ENTITLEMENTS` and `SIGN_OPTIONS` for hardened runtime / notarization, for example:

```bash
ENTITLEMENTS='resources/entitlements.plist' SIGN_OPTIONS='--options runtime --timestamp' \
  SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/make_app_bundle.sh .build/release/Ticklet ./artifacts/Ticklet.app com.thomas.Ticklet
```

- For full signing & notarization instructions (CI integration, exporting `.p12`, verifying with `codesign -dvvv` and `spctl`), see `DEVELOPER.md`.

---

## Support & Feedback

- Found a bug or want a feature (redaction, retention rules, or compacting logs)? Open an issue on the GitHub repo or email the maintainer.

---

## License

Ticklet is open source — see the repository license for details.

---

If you prefer a developer-oriented README (build & test instructions), see the `DEVELOPER.md` file in this repo.
