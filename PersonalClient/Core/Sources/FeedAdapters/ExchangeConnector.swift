import Foundation
import FeedDomain

/// Our own explicit exchange schema; NOT a claimed native Hornet/Grindr format.
public struct ExchangeDocument: Codable, Sendable {
    public let format: String
    public let records: [ExchangeItem]
    public init(records: [ExchangeItem]) { self.format = "personal-feed-exchange/v1"; self.records = records }
    public func encode() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data, source: FeedSource) throws -> [IncomingItem] {
        guard source.isValid, source.provider == .other, source.acquisition == .userEndpoint else { throw FeedError.sourceMismatch }
        guard data.count <= ImportTable.maxBytes else { throw FeedError.tooLarge }
        let doc: Self
        do { doc = try JSONDecoder().decode(Self.self, from: data) } catch { throw FeedError.malformed }
        guard doc.format == "personal-feed-exchange/v1" else { throw FeedError.unsupportedFormat }
        guard doc.records.count <= ImportTable.maxRows else { throw FeedError.tooLarge }
        return try doc.records.map { r in
            let date = try r.timestamp.map { try ImportTable.parseDate($0, format: .iso8601) }
            let item = IncomingItem(key: .init(sourceID: source.id, externalID: r.id), title: r.title ?? "", body: r.text,
                                    author: r.author, occurredAt: date, direction: r.direction ?? .unspecified)
            guard item.isValid else { throw FeedError.invalidRecord }
            return item
        }
    }
}
public struct ExchangeItem: Codable, Sendable {
    public let id: String
    public let text: String
    public let title: String?
    public let author: String?
    public let timestamp: String?
    public let direction: Direction?
    public init(id: String, text: String, title: String? = nil, author: String? = nil, timestamp: String? = nil, direction: Direction? = nil) {
        self.id = id; self.text = text; self.title = title; self.author = author; self.timestamp = timestamp; self.direction = direction
    }
}
