import Foundation

public struct GridPoint: Codable, Hashable, Sendable {
    public let x: Int
    public let y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    public var neighbors: [GridPoint] {
        [GridPoint(x, y - 1), GridPoint(x + 1, y),
         GridPoint(x, y + 1), GridPoint(x - 1, y)]
    }
}

public struct Sector: Sendable {
    public static let training = Sector()
    public let seed = 731
    public let width = 9
    public let height = 9
    public let extraction = GridPoint(4, 8)
    public let relics = [GridPoint(1, 1), GridPoint(7, 1), GridPoint(7, 6)]
    public let obstacles: Set<GridPoint> = [
        GridPoint(3, 2), GridPoint(3, 3), GridPoint(3, 4), GridPoint(3, 5),
        GridPoint(5, 3), GridPoint(6, 3), GridPoint(7, 3),
        GridPoint(1, 5), GridPoint(1, 6), GridPoint(5, 6)
    ]
    public init() {}
    public func contains(_ point: GridPoint) -> Bool {
        (0..<width).contains(point.x) && (0..<height).contains(point.y)
    }
    public func isWalkable(_ point: GridPoint) -> Bool {
        contains(point) && !obstacles.contains(point)
    }
    /// Fixed-size BFS preserving N/E/S/W tie-breaking. Includes both endpoints.
    public func path(from start: GridPoint, to goal: GridPoint) -> [GridPoint]? {
        CompactPathfinder.path(from: start, to: goal)
    }
    public func path(from start: GridPoint, to goal: GridPoint,
                     avoiding extra: Set<GridPoint>) -> [GridPoint]? {
        CompactPathfinder.path(from: start, to: goal, avoiding: extra)
    }
}

public enum MissionPhase: String, Codable, Sendable {
    case briefing, active, success
}

public enum MissionError: String, Error, LocalizedError {
    case inactive = "Begin the expedition first."
    case unreachable = "No route to that tile."
    case insufficientActions = "Insufficient AP. Choose a closer tile or End Turn."
    case noRelic = "There is no unrecovered relic on this tile."
    case missingRelics = "Recover all three relics before extraction."
    case wrongExtraction = "Return to the landing pad to extract."
    public var errorDescription: String? { rawValue }
}

public struct Mission: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let actionsPerTurn = 6
    public private(set) var version = schemaVersion
    public private(set) var phase: MissionPhase = .briefing
    public private(set) var position = Sector.training.extraction
    public private(set) var recovered: Set<GridPoint> = []
    public private(set) var actions = actionsPerTurn
    public private(set) var turn = 1
    public init() {}
    public var isValid: Bool {
        let sector = Sector.training
        guard version == Self.schemaVersion, sector.isWalkable(position),
              (0...Self.actionsPerTurn).contains(actions), turn >= 1,
              recovered.isSubset(of: Set(sector.relics)) else { return false }
        if phase == .briefing { return self == Mission() }
        if phase == .success {
            return position == sector.extraction && recovered.count == sector.relics.count
        }
        return true
    }
    public mutating func begin() {
        guard phase == .briefing else { return }
        phase = .active
    }
    public mutating func reset() { self = Mission() }
    @discardableResult
    public mutating func move(to destination: GridPoint) throws -> [GridPoint] {
        guard phase == .active else { throw MissionError.inactive }
        guard let route = Sector.training.path(from: position, to: destination)
        else { throw MissionError.unreachable }
        let cost = route.count - 1
        guard cost <= actions else { throw MissionError.insufficientActions }
        position = destination
        actions -= cost
        return route
    }
    public mutating func recover() throws {
        guard phase == .active else { throw MissionError.inactive }
        guard Sector.training.relics.contains(position), !recovered.contains(position)
        else { throw MissionError.noRelic }
        guard actions >= 1 else { throw MissionError.insufficientActions }
        recovered.insert(position)
        actions -= 1
    }
    public mutating func extract() throws {
        guard phase == .active else { throw MissionError.inactive }
        guard position == Sector.training.extraction else { throw MissionError.wrongExtraction }
        guard recovered.count == Sector.training.relics.count else { throw MissionError.missingRelics }
        guard actions >= 1 else { throw MissionError.insufficientActions }
        actions -= 1
        phase = .success
    }
    public mutating func endTurn() throws {
        guard phase == .active else { throw MissionError.inactive }
        actions = Self.actionsPerTurn
        if turn < Int.max { turn += 1 }
    }
}

public enum CompactMissionError: Error {
    case invalidLength, invalidHeader, checksumMismatch, invalidState
}

extension Mission {
    /// 19-byte payload: WE, version, phase, cell, relic bits, AP, UInt64 turn LE, CRC32 LE.
    /// CRC detects accidental corruption; it is not an authenticity/security mechanism.
    public func compactData() throws -> Data {
        guard isValid else { throw CompactMissionError.invalidState }
        let phaseByte: UInt8
        switch phase { case .briefing: phaseByte = 0; case .active: phaseByte = 1; case .success: phaseByte = 2 }
        var relicBits: UInt8 = 0
        for (i, point) in Sector.training.relics.enumerated() where recovered.contains(point) {
            relicBits |= UInt8(1) << UInt8(i)
        }
        var data = Data(capacity: 19)
        data.append(contentsOf: [0x57, 0x45, 1, phaseByte, UInt8(position.y * 9 + position.x), relicBits, UInt8(actions)])
        let turns = UInt64(turn)
        for shift in stride(from: 0, through: 56, by: 8) { data.append(UInt8(truncatingIfNeeded: turns >> shift)) }
        let checksum = Self.compactChecksum(data)
        for shift in stride(from: 0, through: 24, by: 8) { data.append(UInt8(truncatingIfNeeded: checksum >> shift)) }
        return data
    }
    public init(compactData data: Data) throws {
        guard data.count == 19 else { throw CompactMissionError.invalidLength }
        // Normalize indexing: callers may pass a Data slice whose startIndex is not zero.
        let bytes = [UInt8](data)
        guard bytes[0] == 0x57, bytes[1] == 0x45, bytes[2] == 1 else { throw CompactMissionError.invalidHeader }
        var checksum: UInt32 = 0
        for i in 0..<4 { checksum |= UInt32(bytes[15+i]) << (i*8) }
        guard Self.compactChecksum(bytes.prefix(15)) == checksum else { throw CompactMissionError.checksumMismatch }
        guard bytes[3] <= 2, bytes[4] < 81, bytes[5] < 8, bytes[6] <= 6 else { throw CompactMissionError.invalidState }
        var turns: UInt64 = 0
        for i in 0..<8 { turns |= UInt64(bytes[7+i]) << (i*8) }
        guard turns > 0, turns <= UInt64(Int.max) else { throw CompactMissionError.invalidState }
        self.init()
        phase = bytes[3] == 0 ? .briefing : (bytes[3] == 1 ? .active : .success)
        position = GridPoint(Int(bytes[4]) % 9, Int(bytes[4]) / 9)
        recovered = []
        for (i, point) in Sector.training.relics.enumerated() where bytes[5] & (UInt8(1) << UInt8(i)) != 0 {
            recovered.insert(point)
        }
        actions = Int(bytes[6]); turn = Int(turns)
        guard isValid else { throw CompactMissionError.invalidState }
    }
    private static func compactChecksum<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
        var crc: UInt32 = .max
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xEDB88320) }
        }
        return ~crc
    }
}
