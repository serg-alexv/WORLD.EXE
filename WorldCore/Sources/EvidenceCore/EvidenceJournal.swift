import Foundation

/// Fixed-capacity, O(1) append. Export allocates at most capacity entries per lane.
private struct EvidenceRing<Element: Sendable>: Sendable {
    private var storage: [Element?]
    private var next = 0
    private(set) var count = 0
    private(set) var dropped: UInt64 = 0
    init(capacity: Int) { storage = Array(repeating: nil, count: capacity) }
    mutating func append(_ value: Element) {
        if count == storage.count { if dropped < .max { dropped += 1 } } else { count += 1 }
        storage[next] = value; next = (next + 1) % storage.count
    }
    var elements: [Element] { (0..<count).compactMap { storage[(next - count + storage.count + $0) % storage.count] } }
}

public struct EvidenceSnapshot: Codable, Sendable {
    public let schemaVersion: Int
    public let session: UUID
    public let observations: [ObservationRecord]
    public let telemetry: [TelemetryRecord]
    public let gameplay: [GameEventRecord]
    public let observationEvictions: UInt64
    public let telemetryEvictions: UInt64
    public let gameplayEvictions: UInt64
    public var isValid: Bool {
        guard schemaVersion == 1, observations.count <= 1024, telemetry.count <= 1024, gameplay.count <= 1024,
              observations.allSatisfy({ $0.isValid }), telemetry.allSatisfy({ $0.isValid }), gameplay.allSatisfy({ $0.isValid }) else { return false }
        let stamps = observations.map(\.stamp) + telemetry.map(\.stamp) + gameplay.map(\.stamp)
        return stamps.allSatisfy({ $0.session == session }) && Set(stamps.map(\.id)).count == stamps.count &&
            Set(stamps.map(\.sequence)).count == stamps.count
    }
    public func encoded() throws -> Data {
        guard isValid else { throw EvidenceError.invalidRecord }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> EvidenceSnapshot {
        guard data.count <= 4 * 1024 * 1024 else { throw EvidenceError.tooLarge }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(Self.self, from: data)
        guard value.isValid else { throw EvidenceError.invalidRecord }
        return value
    }
    /// An observations-only export cannot contain telemetry, scores or model responses.
    public func observationData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        guard isValid else { throw EvidenceError.invalidRecord }
        return try encoder.encode(observations)
    }
    public func telemetryData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        guard isValid else { throw EvidenceError.invalidRecord }; return try encoder.encode(telemetry)
    }
    public func gameplayData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        guard isValid else { throw EvidenceError.invalidRecord }; return try encoder.encode(gameplay)
    }
}

/// No dependency on gameplay, UI, ARKit, networking or a model runtime.
/// Callers own serialization/thread confinement. No generic append(Any) exists.
public struct EvidenceJournal: Sendable {
    public let session: UUID
    private let capacity: Int
    private var observations: EvidenceRing<ObservationRecord>
    private var telemetry: EvidenceRing<TelemetryRecord>
    private var gameplay: EvidenceRing<GameEventRecord>
    public private(set) var lastSequence: UInt64 = 0
    private var lastUptime: Double = 0
    public init(session: UUID = UUID(), capacityPerLane: Int = 128) throws {
        guard (1...1024).contains(capacityPerLane) else { throw EvidenceError.invalidCapacity }
        _ = try EvidenceStamp(session: session, sequence: 1, recordedAt: Date(), uptime: 0)
        self.session = session; capacity = capacityPerLane; observations = .init(capacity: capacityPerLane)
        telemetry = .init(capacity: capacityPerLane); gameplay = .init(capacity: capacityPerLane)
    }
    private mutating func accept(_ stamp: EvidenceStamp) throws {
        guard stamp.isValid else { throw EvidenceError.invalidRecord }
        guard stamp.session == session else { throw EvidenceError.wrongSession }
        guard stamp.sequence > lastSequence, stamp.uptime >= lastUptime else { throw EvidenceError.staleSequence }
        lastSequence = stamp.sequence; lastUptime = stamp.uptime
    }
    public mutating func append(_ record: ObservationRecord) throws {
        guard record.isValid else { throw EvidenceError.invalidRecord }; try accept(record.stamp); observations.append(record)
    }
    public mutating func append(_ record: TelemetryRecord) throws {
        guard record.isValid else { throw EvidenceError.invalidRecord }; try accept(record.stamp); telemetry.append(record)
    }
    public mutating func append(_ record: GameEventRecord) throws {
        guard record.isValid else { throw EvidenceError.invalidRecord }; try accept(record.stamp); gameplay.append(record)
    }
    /// Clearing a lane never touches sensor archives, model weights or mission state.
    public mutating func clear(_ lane: EvidenceLane) {
        switch lane {
        case .observation: observations = .init(capacity: capacity)
        case .telemetry: telemetry = .init(capacity: capacity)
        case .gameplay: gameplay = .init(capacity: capacity)
        }
    }
    public var snapshot: EvidenceSnapshot {
        EvidenceSnapshot(schemaVersion: 1, session: session, observations: observations.elements,
                         telemetry: telemetry.elements, gameplay: gameplay.elements,
                         observationEvictions: observations.dropped, telemetryEvictions: telemetry.dropped, gameplayEvictions: gameplay.dropped)
    }
}
