import Foundation

public protocol LogWriter {
    func write(entries: [ActivityEntry], for date: Date) throws
    func readEntries(for date: Date) throws -> [ActivityEntry]
    func append(entries: [ActivityEntry], for date: Date) throws
}
