import Foundation

final class CSVLogger: LogWriter {
    private let directory: URL
    private let legacyDirectory: URL?

    /// Exposed for UI actions (Open Logs Folder)
    var logsDirectory: URL { directory }

    /// When true, window titles are omitted from CSV output (only app names are logged).
    var redactWindowTitles: Bool = false
    private let fileDateFormatter: DateFormatter
    private let lineDateFormatter: DateFormatter
    private let fileManager = FileManager.default

    init(logsDirectory: URL? = nil, legacyLogsDirectory: URL? = nil) throws {
        if let dir = logsDirectory {
            directory = dir
            self.legacyDirectory = legacyLogsDirectory
        } else {
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            directory = appSupportURL.appendingPathComponent("Ticklet", isDirectory: true)
            let libraryURL = try fileManager.url(
                for: .libraryDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            self.legacyDirectory = libraryURL.appendingPathComponent("Logs/Ticklet", isDirectory: true)
        }

        fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"

        lineDateFormatter = DateFormatter()
        lineDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try migrateLegacyLogsIfNeeded()
    }

    func write(entries: [ActivityEntry], for date: Date) throws {
        let filename = "ticklet-\(fileDateFormatter.string(from: date)).csv"
        let fileURL = directory.appendingPathComponent(filename)

        var csv = "start_time,end_time,duration_seconds,app_name,window_title\n"
        for e in entries.sorted(by: { $0.startTime < $1.startTime }) {
            guard let end = e.endTime else { continue }
            let duration = Int(end.timeIntervalSince(e.startTime))
            let start = lineDateFormatter.string(from: e.startTime)
            let endStr = lineDateFormatter.string(from: end)
            let app = escape(e.appName)
            let win = redactWindowTitles ? "" : escape(e.windowTitle)
            csv += "\(start),\(endStr),\(duration),\(app),\(win)\n"
        }

        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // Append entries to existing CSV file safely. Creates the file with header if missing.
    func append(entries: [ActivityEntry], for date: Date) throws {
        let filename = "ticklet-\(fileDateFormatter.string(from: date)).csv"
        let fileURL = directory.appendingPathComponent(filename)

        var toWrite = ""
        for e in entries.sorted(by: { $0.startTime < $1.startTime }) {
            guard let end = e.endTime else { continue }
            let duration = Int(end.timeIntervalSince(e.startTime))
            let start = lineDateFormatter.string(from: e.startTime)
            let endStr = lineDateFormatter.string(from: end)
            let app = escape(e.appName)
            let win = redactWindowTitles ? "" : escape(e.windowTitle)
            toWrite += "\(start),\(endStr),\(duration),\(app),\(win)\n"
        }

        // Ensure directory exists
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: fileURL.path) {
            // write header + entries
            let csv = "start_time,end_time,duration_seconds,app_name,window_title\n" + toWrite
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }

        // Append to existing file using FileHandle
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = toWrite.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    func readEntries(for date: Date) throws -> [ActivityEntry] {
        let filename = "ticklet-\(fileDateFormatter.string(from: date)).csv"
        let fileURL = directory.appendingPathComponent(filename)
        let data: String
        do {
            data = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // Missing file is expected for dates with no activity yet.
            if let cocoaError = error as? CocoaError, cocoaError.code == .fileReadNoSuchFile {
                return []
            }
            throw error
        }
        var entries: [ActivityEntry] = []
        let records = parseCSVRecords(data)
        
        // Validate header
        guard records.count > 1 else { return [] }
        let headerFields = records[0]
        let expectedHeader = ["start_time", "end_time", "duration_seconds", "app_name", "window_title"]
        guard headerFields == expectedHeader else {
            NSLog("[Ticklet] Warning: CSV header mismatch for \(filename). Expected: \(expectedHeader.joined(separator: ",")), Got: \(headerFields.joined(separator: ","))")
            return []
        }
        
        var skippedCount = 0
        for fields in records.dropFirst() {
            if fields.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            guard fields.count >= 5 else {
                skippedCount += 1
                continue
            }
            let startStr = fields[0]
            let endStr = fields[1]
            let app = fields[3]
            let win = fields[4]
            if let start = lineDateFormatter.date(from: startStr), let end = lineDateFormatter.date(from: endStr) {
                let e = ActivityEntry(appName: app, windowTitle: win, startTime: start, endTime: end)
                entries.append(e)
            } else {
                skippedCount += 1
            }
        }
        
        if skippedCount > 0 {
            NSLog("[Ticklet] Skipped \(skippedCount) malformed entries in \(filename)")
        }
        
        return entries
    }

    func applyRetentionPolicy(retentionDays: Int) throws {
        guard retentionDays > 0 else { return }

        let cutoffDate = Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(-Double(retentionDays) * 86_400)
        for fileURL in try csvFiles(in: directory) {
            guard let fileDate = dateFromFilename(fileURL.lastPathComponent) else { continue }
            if fileDate < cutoffDate {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }

    func deleteAllLogs() throws {
        for fileURL in try csvFiles(in: directory) {
            try fileManager.trashItem(at: fileURL, resultingItemURL: nil)
        }
    }

    private func parseCSVRecords(_ csv: String) -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = csv.startIndex
        let quote: Character = "\""
        let comma: Character = ","
        let newline: Character = "\n"
        let carriageReturn: Character = "\r"

        while i < csv.endIndex {
            let character = csv[i]

            if inQuotes {
                if character == quote {
                    let next = csv.index(after: i)
                    if next < csv.endIndex && csv[next] == quote {
                        currentField.append(quote)
                        i = csv.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    currentField.append(character)
                }
                i = csv.index(after: i)
                continue
            }

            switch character {
            case quote:
                inQuotes = true
            case comma:
                fields.append(currentField)
                currentField = ""
            case newline:
                fields.append(currentField)
                currentField = ""
                if !fields.isEmpty {
                    records.append(fields)
                }
                fields = []
            case carriageReturn:
                break
            default:
                currentField.append(character)
            }

            i = csv.index(after: i)
        }

        if inQuotes {
            fields.append(currentField)
            records.append(fields)
        } else if !currentField.isEmpty || !fields.isEmpty {
            fields.append(currentField)
            records.append(fields)
        }

        return records
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var cur = ""
        var inQuotes = false
        var i = line.startIndex
        let quote: Character = "\""
        let comma: Character = ","
        while i < line.endIndex {
            let c = line[i]
            if inQuotes {
                if c == quote {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == quote {
                        cur.append(String(quote))
                        i = line.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                        i = line.index(after: i)
                        continue
                    }
                } else {
                    cur.append(c)
                    i = line.index(after: i)
                    continue
                }
            } else {
                if c == quote {
                    inQuotes = true
                    i = line.index(after: i)
                    continue
                } else if c == comma {
                    fields.append(cur)
                    cur = ""
                    i = line.index(after: i)
                    continue
                } else {
                    cur.append(c)
                    i = line.index(after: i)
                    continue
                }
            }
        }
        fields.append(cur)
        return fields
    }
    private func escape(_ field: String) -> String {
        // RFC 4180 escaping: fields with commas, quotes, or newlines must be quoted, and interior quotes doubled
        var needsQuotes = false
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            needsQuotes = true
        }
        var out = field.replacingOccurrences(of: "\"", with: "\"\"")
        if needsQuotes {
            out = "\"\(out)\""
        }
        return out
    }

    private func migrateLegacyLogsIfNeeded() throws {
        guard let legacyDirectory else { return }
        guard fileManager.fileExists(atPath: legacyDirectory.path) else { return }

        for legacyFile in try csvFiles(in: legacyDirectory) {
            let destinationFile = directory.appendingPathComponent(legacyFile.lastPathComponent)
            guard !fileManager.fileExists(atPath: destinationFile.path) else { continue }
            try fileManager.copyItem(at: legacyFile, to: destinationFile)
        }
    }

    private func csvFiles(in directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "csv" }
    }

    private func dateFromFilename(_ filename: String) -> Date? {
        guard filename.hasPrefix("ticklet-"), filename.hasSuffix(".csv") else { return nil }
        let startIndex = filename.index(filename.startIndex, offsetBy: 8)
        let endIndex = filename.index(filename.endIndex, offsetBy: -4)
        return fileDateFormatter.date(from: String(filename[startIndex..<endIndex]))
    }
}
