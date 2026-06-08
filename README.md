# Ticklet

Ticklet quietly records which applications and windows you use during the day and saves the results to simple CSV files so you can answer te question: "What did I do today?"

It's great for anyone who has to fill in a timesheet and bounces around between clients and projects.

## What Ticklet does

- Runs in the background and records the frontmost app and focused window title at short intervals.
- Saves entries to daily CSV files at: `~/Library/Application Support/Ticklet/` (one file per date).
- Provides a built-in **Logs** viewer for inspecting and navigating days.

## Privacy & Permissions

- Ticklet requires **Accessibility** permission to read window titles. Without this permission Ticklet will still run but window titles may be empty or incomplete.
- Window titles may contain sensitive information (document names, emails, etc.). You should:
  - Review the data stored in `~/Library/Application Support/Ticklet/` and delete files you don’t want to keep
  - Use the Preferences to disable the status item if you prefer minimal UI
  - Use the **Only log app names (hide window titles)** preference if you do not want window titles written to new log entries
  - Use the retention, delete-history, and excluded-app controls in Preferences to minimize what gets stored

## Install

- Download the latest release from the <a href="https://github.com/TwisterMc/Ticklet/releases">releases page</a>. Releases include both **Intel (x86_64)** and **Apple Silicon (arm64)** builds.
- Drag the application to your Applications folder.
- Open Ticklet and grant accessibility permissions.

## Granting Accessibility permission

When you launchh Ticklet for the first time, macOS will prompt you to grant Accessibility permission so the app can read window titles. Follow the steps in the app.

When Accessibility is enabled, Ticklet will be able to read window titles and produce richer logs.

## Features

- Ticklet can run in your dock or in the menu bar.
- Sampling interval: set the recording interval (seconds). Default is 1 second (supported range: 0.1–60).
- Optional: **Only log app names (hide window titles)** if you want new log entries to omit window titles.
- You can set the retention period for logs, delete all recorded history, and exclude specific apps from logging if desired. Default is to retain logs indefinitely and include all apps.
- Enable **Use 12 or 24-hour time** in the log display.
- Automatically checks for updates.
- Includes a log viewer.
  - Use the date controls (Back / Forward / Today) to navigate days.
  - Click column headers to sort entries.
  - When sorted by **Time**, the viewer draws a separator between hour blocks for easier scanning.
  - The **Duration** column shows a compact, human-friendly format (e.g., `30s`, `1m 30s`, `1h 30s`); the underlying CSV stores duration as seconds.
  - Each row shows the app name **with its icon** (when available) for easier scanning.
- Logs are stored as CSVs iin your Application Support folder. Eac day iis a new CSV file.

## Donate

If you find Ticklet useful and would like to support its development, consider making a [donation](https://ko-fi.com/twistermc). Every bit helps and is greatly appreciated!

## Troubleshooting

- If logs are empty or missing titles: verify Accessibility permission and restart the app.
- If Ticklet doesn’t appear in Accessibility list: use Finder to open the `.app` once (this registers it with Launch Services), then add it in System Settings.
- If the app behaves oddly after granting permission, quit it and re-open it from Finder.

## Support & Feedback

- Found a bug or want a feature? <a href="https://github.com/TwisterMc/Ticklet/issues">Open an issue</a>.

## Contributing

- Contributions are welcome! Please create a pull request or open an issue to discuss your ideas.

## AI

- Ticklet exists because of AI. I built it for myself to track my time and I wanted to share it with others too. I used AI to write the code, but I don't settle for AI slop. I've done my best to try and create a quality app.

## License

Ticklet is open source — see the repository license for details.

## Developers

If you prefer a developer-oriented README (build & test instructions), see the `DEVELOPER.md` file in this repo.
