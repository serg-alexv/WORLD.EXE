import Foundation
import FeedDomain

public enum DateFormat: String, CaseIterable, Sendable { case iso8601, unixSeconds }
public struct ColumnMapping: Sendable {
    public var id: String
    public var body: String
    public var title: String?
    public var author: String?
    public var timestamp: String?
    public var dateFormat: DateFormat
    public var direction: Direction
    public init(id: String, body: String, title: String? = nil, author: String? = nil, timestamp: String? = nil,
                dateFormat: DateFormat = .iso8601, direction: Direction = .unspecified) {
        self.id = id; self.body = body; self.title = title; self.author = author; self.timestamp = timestamp
        self.dateFormat = dateFormat; self.direction = direction
    }
}
public struct ImportTable: Sendable {
    public static let maxBytes = 4 * 1024 * 1024
    public static let maxRows = 2_000
    public let columns: [String]
    public let rows: [[String: String]]
    public let format: String
    public init(data: Data, fileExtension: String, arrayKey: String? = nil) throws {
        guard data.count <= Self.maxBytes else { throw FeedError.tooLarge }
        switch fileExtension.lowercased() {
        case "csv":
            guard var text = String(data: data, encoding: .utf8) else { throw FeedError.malformed }
            if text.first == "\u{FEFF}" { text.removeFirst() }
            let parsed = try CSVParser.parse(text)
            guard let header = parsed.first, !header.isEmpty, header.count <= 64,
                  header.allSatisfy({ validText($0, maximum: 256, allowEmpty: false) }),
                  Set(header).count == header.count else { throw FeedError.malformed }
            let values = parsed.dropFirst()
            guard !values.isEmpty, values.count <= Self.maxRows else { throw FeedError.tooLarge }
            guard values.allSatisfy({ $0.count == header.count }) else { throw FeedError.malformed }
            columns = header
            rows = values.map { Dictionary(uniqueKeysWithValues: zip(header, $0)) }
            format = "CSV · поля выбраны пользователем"
        case "json":
            let raw: Any
            do { raw = try JSONSerialization.jsonObject(with: data) } catch { throw FeedError.malformed }
            let candidate: Any?
            if let arrayKey, !arrayKey.isEmpty { candidate = (raw as? [String: Any])?[arrayKey] } else { candidate = raw }
            guard let objects = candidate as? [[String: Any]], !objects.isEmpty else { throw FeedError.unsupportedFormat }
            guard objects.count <= Self.maxRows else { throw FeedError.tooLarge }
            var collected = Set<String>(), mapped: [[String: String]] = []
            for object in objects {
                guard object.count <= 64 else { throw FeedError.tooLarge }
                var row: [String: String] = [:]
                for (key, value) in object {
                    guard validText(key, maximum: 256, allowEmpty: false) else { throw FeedError.malformed }
                    if value is NSNull { row[key] = "" }
                    else if let string = value as? String { row[key] = string }
                    else if let number = value as? NSNumber { row[key] = number.stringValue }
                    // Nested objects are deliberately not flattened or interpreted.
                    if let text = row[key] {
                        guard validText(text, maximum: 16_384) else { throw FeedError.tooLarge }
                        collected.insert(key)
                    }
                }
                mapped.append(row)
            }
            guard !collected.isEmpty, collected.count <= 64 else { throw FeedError.unsupportedFormat }
            columns = collected.sorted(); rows = mapped
            format = "JSON · поля выбраны пользователем"
        default: throw FeedError.unsupportedFormat
        }
    }
    public func map(using mapping: ColumnMapping, source: FeedSource) throws -> [IncomingItem] {
        guard source.isValid, source.acquisition == .userMappedFile else { throw FeedError.sourceMismatch }
        guard columns.contains(mapping.id), columns.contains(mapping.body), mapping.id != mapping.body else { throw FeedError.missingColumn }
        for field in [mapping.title, mapping.author, mapping.timestamp].compactMap({ $0 }) {
            guard columns.contains(field) else { throw FeedError.missingColumn }
        }
        return try rows.map { row in
            guard let id = row[mapping.id], let body = row[mapping.body] else { throw FeedError.invalidRecord }
            let date: Date?
            if let field = mapping.timestamp, let text = row[field], !text.isEmpty {
                date = try Self.parseDate(text, format: mapping.dateFormat)
            } else { date = nil }
            let item = IncomingItem(key: .init(sourceID: source.id, externalID: id),
                                    title: mapping.title.flatMap { row[$0] } ?? "", body: body,
                                    author: mapping.author.flatMap { row[$0] }, occurredAt: date, direction: mapping.direction)
            guard item.isValid else { throw FeedError.invalidRecord }
            return item
        }
    }
    public static func parseDate(_ text: String, format: DateFormat) throws -> Date {
        let date: Date?
        switch format {
        case .unixSeconds:
            date = Double(text).map { Date(timeIntervalSince1970: $0) }
        case .iso8601:
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = iso.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        }
        guard let date, validDate(date) else { throw FeedError.invalidDate }
        return date
    }
}

private enum CSVParser {
    static func parse(_ original: String) throws -> [[String]] {
        let text = original.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false, closedQuote = false, atStart = true
        var i = text.startIndex
        func checkedField() throws {
            guard field.utf8.count <= 16_384, row.count < 64 else { throw FeedError.tooLarge }
        }
        while i < text.endIndex {
            let c = text[i], next = text.index(after: i)
            if inQuotes {
                if c == "\"" {
                    if next < text.endIndex && text[next] == "\"" { field.append("\""); i = text.index(after: next); continue }
                    inQuotes = false; closedQuote = true
                } else { field.append(c) }
            } else if c == "," || c == "\n" {
                try checkedField(); row.append(field); field = ""; closedQuote = false; atStart = true
                if c == "\n" {
                    if row != [""] { rows.append(row) }
                    row = []
                    guard rows.count <= ImportTable.maxRows + 1 else { throw FeedError.tooLarge }
                }
            } else if c == "\"" {
                guard atStart && !closedQuote else { throw FeedError.malformed }
                inQuotes = true; atStart = false
            } else {
                guard !closedQuote else { throw FeedError.malformed }
                field.append(c); atStart = false
            }
            i = next
        }
        guard !inQuotes else { throw FeedError.malformed }
        if !field.isEmpty || !row.isEmpty || closedQuote {
            try checkedField(); row.append(field); rows.append(row)
        }
        guard rows.count <= ImportTable.maxRows + 1 else { throw FeedError.tooLarge }
        return rows
    }
}
