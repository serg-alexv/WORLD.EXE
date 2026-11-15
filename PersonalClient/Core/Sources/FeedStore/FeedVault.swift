import Foundation
import FeedDomain

public struct ImportReceipt: Equatable, Sendable {
    public let inserted: Int
    public let updated: Int
    public let unchanged: Int
    public let invalidatedAnnotations: Int
}
public struct SourceState: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { source.id }
    public let source: FeedSource
    public var lastImportedAt: Date?
    public var lastBatchCount: Int?
    public init(source: FeedSource) { self.source = source }
}
public struct FeedVault: Codable, Equatable, Sendable {
    public static let maximumItems = 2_000
    public static let maximumBytes = 12 * 1024 * 1024
    public private(set) var schemaVersion = 1
    public private(set) var sources: [SourceState] = []
    public private(set) var items: [FeedItem] = []
    public private(set) var annotations: [FeedAnnotation] = []
    public init() {}
    public mutating func addSource(_ source: FeedSource) throws {
        guard source.isValid else { throw FeedError.unsupportedSource }
        guard sources.count < 32 else { throw FeedError.capacity }
        guard !sources.contains(where: { $0.id == source.id }) else { throw FeedError.sourceMismatch }
        sources.append(.init(source: source))
    }
    @discardableResult public mutating func ingest(_ batch: [IncomingItem], sourceID: UUID, at date: Date = Date()) throws -> ImportReceipt {
        guard validDate(date), let sourceIndex = sources.firstIndex(where: { $0.id == sourceID }) else { throw FeedError.sourceMismatch }
        guard batch.count <= Self.maximumItems else { throw FeedError.capacity }
        var unique: [ItemKey: IncomingItem] = [:]
        for item in batch {
            guard item.isValid else { throw FeedError.invalidRecord }
            guard item.key.sourceID == sourceID else { throw FeedError.sourceMismatch }
            if let previous = unique[item.key], previous != item { throw FeedError.duplicateConflict }
            unique[item.key] = item
        }
        var candidate = self, indices = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.key, $0.offset) })
        var inserted = 0, updated = 0, unchanged = batch.count - unique.count
        var changedKeys = Set<ItemKey>()
        for key in unique.keys.sorted(by: { $0.externalID < $1.externalID }) {
            let item = unique[key]!
            if let index = indices[key] {
                if candidate.items[index].incoming == item { unchanged += 1; continue }
                guard candidate.items[index].revision < UInt64.max else { throw FeedError.capacity }
                candidate.items[index] = FeedItem(item, revision: candidate.items[index].revision + 1, importedAt: date,
                                                  acquisition: sources[sourceIndex].source.acquisition)
                updated += 1; changedKeys.insert(key)
            } else {
                guard candidate.items.count < Self.maximumItems else { throw FeedError.capacity }
                indices[key] = candidate.items.count
                candidate.items.append(FeedItem(item, revision: 1, importedAt: date, acquisition: sources[sourceIndex].source.acquisition))
                inserted += 1
            }
        }
        let before = candidate.annotations.count
        candidate.annotations.removeAll { $0.references.contains { changedKeys.contains($0.key) } }
        candidate.sources[sourceIndex].lastImportedAt = date
        candidate.sources[sourceIndex].lastBatchCount = batch.count
        _ = try candidate.encoded()
        self = candidate
        return .init(inserted: inserted, updated: updated, unchanged: unchanged, invalidatedAnnotations: before - candidate.annotations.count)
    }
    public mutating func annotate(_ annotation: FeedAnnotation) throws {
        guard annotation.isValid, !annotations.contains(where: { $0.id == annotation.id }) else { throw FeedError.invalidAnnotation }
        guard annotations.count < 2_000 else { throw FeedError.capacity }
        for reference in annotation.references {
            guard items.contains(where: { $0.key == reference.key && $0.revision == reference.revision }) else { throw FeedError.staleReference }
        }
        var candidate = self; candidate.annotations.append(annotation); _ = try candidate.encoded(); self = candidate
    }
    public mutating func deleteAnnotation(_ id: UUID) { annotations.removeAll { $0.id == id } }
    public mutating func deleteSource(_ id: UUID) {
        sources.removeAll { $0.id == id }; items.removeAll { $0.key.sourceID == id }
        annotations.removeAll { $0.references.contains { $0.key.sourceID == id } }
    }
    public func feed(sourceID: UUID? = nil, query: String = "") -> [FeedItem] {
        items.filter { item in
            (sourceID == nil || item.key.sourceID == sourceID) &&
            (query.isEmpty || [item.title, item.body, item.author ?? ""].contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt { return (lhs.occurredAt ?? .distantPast) > (rhs.occurredAt ?? .distantPast) }
            if lhs.importedAt != rhs.importedAt { return lhs.importedAt > rhs.importedAt }
            if lhs.key.sourceID != rhs.key.sourceID { return lhs.key.sourceID.uuidString < rhs.key.sourceID.uuidString }
            return lhs.key.externalID < rhs.key.externalID
        }
    }
    public var isValid: Bool {
        guard schemaVersion == 1, sources.count <= 32, items.count <= Self.maximumItems, annotations.count <= 2_000,
              sources.allSatisfy({ $0.source.isValid && ($0.lastImportedAt.map(validDate) ?? true) && ($0.lastBatchCount.map { (0...Self.maximumItems).contains($0) } ?? true) }),
              Set(sources.map(\.id)).count == sources.count, items.allSatisfy(\.isValid), Set(items.map(\.key)).count == items.count,
              Set(annotations.map(\.id)).count == annotations.count else { return false }
        let profiles = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.source) })
        let revisions = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0.revision) })
        return items.allSatisfy({ profiles[$0.key.sourceID]?.acquisition == $0.acquisition }) &&
        annotations.allSatisfy { $0.isValid && $0.references.allSatisfy { revisions[$0.key] == $0.revision } }
    }
    public func encoded() throws -> Data {
        guard isValid else { throw FeedError.invalidArchive }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw FeedError.tooLarge }
        return data
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, sources, items, annotations }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else { throw FeedError.invalidArchive }
        func bounded<T: Decodable>(_ key: CodingKeys, limit: Int, as: T.Type) throws -> [T] {
            var values = try c.nestedUnkeyedContainer(forKey: key)
            if let count = values.count, count > limit { throw FeedError.tooLarge }
            var result: [T] = []
            while !values.isAtEnd {
                guard result.count < limit else { throw FeedError.tooLarge }
                result.append(try values.decode(T.self))
            }
            return result
        }
        sources = try bounded(.sources, limit: 32, as: SourceState.self)
        items = try bounded(.items, limit: Self.maximumItems, as: FeedItem.self)
        annotations = try bounded(.annotations, limit: 2_000, as: FeedAnnotation.self)
        guard isValid else { throw FeedError.invalidArchive }
    }
    public init(data: Data) throws {
        guard data.count <= Self.maximumBytes else { throw FeedError.tooLarge }
        do { self = try JSONDecoder().decode(Self.self, from: data) } catch { throw FeedError.invalidArchive }
        guard isValid else { throw FeedError.invalidArchive }
    }
}
