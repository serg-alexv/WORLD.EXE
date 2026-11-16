import Foundation

public enum SiegeLeaderboardError: Error, Equatable {
    case unsupportedVersion
    case invalidArchive
    case incompleteMission
    case invalidMission
    case capacityReached
}

/// A local result backed by the complete, deterministic mission receipt.
/// There is deliberately no initializer accepting a caller-supplied score.
public struct SiegeScore: Codable, Equatable, Identifiable {
    private let receipt: SignalSiege

    public var id: UUID { sessionID }
    public var sessionID: UUID { receipt.sessionID }
    public var score: Int { receipt.score ?? 0 }
    public var turn: Int { receipt.turn }
    public var seed: UInt64 { receipt.seed }
    public var difficulty: SiegeDifficulty { receipt.difficulty }

    fileprivate init(mission: SignalSiege) { receipt = mission }

    private enum CodingKeys: String, CodingKey {
        case receipt, sessionID, score, turn, seed, difficulty
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let mission = try values.decode(SignalSiege.self, forKey: .receipt)
        guard mission.phase == .victory, mission.isValid, let score = mission.score,
              score >= 0,
              try values.decode(UUID.self, forKey: .sessionID) == mission.sessionID,
              try values.decode(Int.self, forKey: .score) == score,
              try values.decode(Int.self, forKey: .turn) == mission.turn,
              try values.decode(UInt64.self, forKey: .seed) == mission.seed,
              try values.decode(SiegeDifficulty.self, forKey: .difficulty) == mission.difficulty
        else { throw SiegeLeaderboardError.invalidArchive }
        receipt = mission
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(receipt, forKey: .receipt)
        try values.encode(sessionID, forKey: .sessionID)
        try values.encode(score, forKey: .score)
        try values.encode(turn, forKey: .turn)
        try values.encode(seed, forKey: .seed)
        try values.encode(difficulty, forKey: .difficulty)
    }
}

/// On-device Signal Siege results, partitioned by exact seed and difficulty.
/// This is a local convenience archive, not a tamper-proof or global ranking.
public struct SiegeLeaderboard: Codable, Equatable {
    public static let archiveVersion = 1
    public static let mode = "signalSiege"
    public static let maximumRecordedSessions = 4_096
    public static let maximumArchiveBytes = 16 * 1_024 * 1_024
    public static let entriesPerBoard = 10

    private var results: [SiegeScore] = []
    // IDs remain here after a result drops out of its top ten. Never silently prune.
    private var recordedSessionIDs: Set<UUID> = []

    public init() {}

    public init(data: Data) throws {
        guard data.count <= Self.maximumArchiveBytes else {
            throw SiegeLeaderboardError.capacityReached
        }
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    public var recordedSessionCount: Int { recordedSessionIDs.count }
    public var isEmpty: Bool { results.isEmpty }

    public func entries(seed: UInt64, difficulty: SiegeDifficulty) -> [SiegeScore] {
        results.filter { $0.seed == seed && $0.difficulty == difficulty }.sorted(by: Self.ranksBefore)
    }

    /// Only completed victories are eligible. Re-submitting a session is a no-op.
    /// An exhausted archive must be explicitly cleared before admitting new sessions.
    @discardableResult
    public mutating func record(_ mission: SignalSiege) throws -> Bool {
        guard mission.phase == .victory, mission.score != nil else {
            throw SiegeLeaderboardError.incompleteMission
        }
        guard mission.isValid, let score = mission.score, score >= 0 else {
            throw SiegeLeaderboardError.invalidMission
        }
        guard !recordedSessionIDs.contains(mission.sessionID) else { return false }
        guard recordedSessionIDs.count < Self.maximumRecordedSessions else {
            throw SiegeLeaderboardError.capacityReached
        }
        var candidate = self
        candidate.recordedSessionIDs.insert(mission.sessionID)
        candidate.results.append(SiegeScore(mission: mission))
        let ranked = candidate.entries(seed: mission.seed, difficulty: mission.difficulty)
        let retained = Set(ranked.prefix(Self.entriesPerBoard).map(\.sessionID))
        candidate.results.removeAll {
            $0.seed == mission.seed && $0.difficulty == mission.difficulty && !retained.contains($0.sessionID)
        }
        candidate.results.sort(by: Self.ranksBefore)
        // Enforce the byte bound before mutating, so persistence cannot reject a new result.
        _ = try candidate.encoded()
        self = candidate
        return true
    }

    /// Clears both rankings and the anti-duplicate ledger, as an explicit user reset.
    public mutating func clear() {
        results.removeAll()
        recordedSessionIDs.removeAll()
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumArchiveBytes else {
            throw SiegeLeaderboardError.capacityReached
        }
        return data
    }

    private static func ranksBefore(_ lhs: SiegeScore, _ rhs: SiegeScore) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.turn != rhs.turn { return lhs.turn < rhs.turn }
        return lhs.sessionID.uuidString < rhs.sessionID.uuidString
    }

    private enum CodingKeys: String, CodingKey { case version, mode, results, recordedSessionIDs }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .version) == Self.archiveVersion else {
            throw SiegeLeaderboardError.unsupportedVersion
        }
        guard try values.decode(String.self, forKey: .mode) == Self.mode else {
            throw SiegeLeaderboardError.invalidArchive
        }
        var idValues = try values.nestedUnkeyedContainer(forKey: .recordedSessionIDs)
        var scoreValues = try values.nestedUnkeyedContainer(forKey: .results)
        guard (idValues.count ?? Self.maximumRecordedSessions + 1) <= Self.maximumRecordedSessions,
              (scoreValues.count ?? Self.maximumRecordedSessions + 1) <= Self.maximumRecordedSessions else {
            throw SiegeLeaderboardError.invalidArchive
        }
        var ids: [UUID] = []
        var scores: [SiegeScore] = []
        while !idValues.isAtEnd {
            guard ids.count < Self.maximumRecordedSessions else { throw SiegeLeaderboardError.invalidArchive }
            ids.append(try idValues.decode(UUID.self))
        }
        while !scoreValues.isAtEnd {
            guard scores.count < Self.maximumRecordedSessions else { throw SiegeLeaderboardError.invalidArchive }
            scores.append(try scoreValues.decode(SiegeScore.self))
        }
        guard !ids.contains(where: { $0.uuidString == "00000000-0000-0000-0000-000000000000" }),
              Set(ids).count == ids.count,
              Set(scores.map(\.sessionID)).count == scores.count,
              Set(scores.map(\.sessionID)).isSubset(of: Set(ids)),
              ids.isEmpty == scores.isEmpty
        else { throw SiegeLeaderboardError.invalidArchive }
        // At most ten retained results in each exact seed/difficulty bucket.
        var boardCounts: [String: Int] = [:]
        for score in scores {
            let key = "\(score.seed):\(String(describing: score.difficulty))"
            boardCounts[key, default: 0] += 1
            guard boardCounts[key, default: 0] <= Self.entriesPerBoard else {
                throw SiegeLeaderboardError.invalidArchive
            }
        }
        recordedSessionIDs = Set(ids)
        results = scores.sorted(by: Self.ranksBefore)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.archiveVersion, forKey: .version)
        try values.encode(Self.mode, forKey: .mode)
        try values.encode(results.sorted(by: Self.ranksBefore), forKey: .results)
        try values.encode(recordedSessionIDs.sorted { $0.uuidString < $1.uuidString }, forKey: .recordedSessionIDs)
    }
}
