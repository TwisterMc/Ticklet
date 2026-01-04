import Foundation

public final class CSVLogger: LogWriter {
    private let directory: URL

    /// Exposed for UI actions (Open Logs Folder)
    public var logsDirectory: URL { directory }
    private let fileDateFormatter: DateFormatter
    private let lineDateFormatter: DateFormatter
    private let fileManager = FileManager.default

    public init(logsDirectory: URL? = nil) throws {
        if let dir = logsDirectory {
            directory = dir
        } else {
            let urls = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)
            directory = urls[0].appendingPathComponent("Logs/Ticklet", isDirectory: true)
        }

        fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"

        lineDateFormatter = DateFormatter()
        lineDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func write(entries: [ActivityEntry], for date: Date) throws {
        let filename = "ticklet-\(fileDateFormatter.string(from: date)).csv"
        let fileURL = directory.appendingPathComponent(filename)

        var csv = "start_time,end_time,duration_seconds,app_name,window_title\n"
        for e in entries.sorted(by: { $0.startTime < $1.startTime }) {
            guard let end = e.endTime else { continue }
            let duration = Int(end.timeIntervalSince(e.startTime))
            let start = lineDateFormatter.string(from: e.startTime)
            let endStr = lineDateFormatter.string(from: end)
            let app = escape(e.appName)
            let win = escape(e.windowTitle)
            csv += "\(start),\(endStr),\(duration),\(app),\(win)\n"
        }

        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // Append entries to existing CSV file safely. Creates the file with header if missing.
    public func append(entries: [ActivityEntry], for date: Date) throws {
        let filename = "ticklet-\(fileDateFormatter.string(from: date)).csv"
        let fileURL = directory.appendingPathComponent(filename)

        var toWrite = ""
        for e in entries.sorted(by: { $0.startTime < $1.startTime }) {
            guard let end = e.endTime else { continue }
            let duration = Int(end.timeIntervalSince(e.startTime))
            let start = lineDateFormatter.string(from: e.startTime)
            let endStr = lineDateFormatter.string(from: end)
            let app = escape(e.appName)
            let win = escape(e.windowTitle)
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

    public func readEntries(for date: Date) throws -> [ActivityEntry] {
        let filename = "ticklet-\(fileDateFormatter.string(from: date)).csv"
        let fileURL = directory.appendingPathComponent(filename)
        NSLog("[Ticklet] CSVLogger.readEntries reading file: \(fileURL.path)")
        let data = try String(contentsOf: fileURL, encoding: .utf8)
        var entries: [ActivityEntry] = []
        let lines = data.components(separatedBy: CharacterSet.newlines)
        NSLog("[Ticklet] CSVLogger.readEntries: lines=\(lines.count)")
        guard lines.count > 1 else { return [] }
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let fields = parseCSVLine(line)
            guard fields.count >= 5 else { continue }
            let startStr = fields[0]
            let endStr = fields[1]
            let app = fields[3]
            let win = fields[4]
            if let start = lineDateFormatter.date(from: startStr), let end = lineDateFormatter.date(from: endStr) {
                let e = ActivityEntry(appName: app, windowTitle: win, startTime: start, endTime: end)
                entries.append(e)
            }
        }
        NSLog("[Ticklet] CSVLogger.readEntries: parsedEntries=\(entries.count)")
        return entries
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
}
