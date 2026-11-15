import Foundation

/// Integer board coordinates. The board is fictional and never uses sensor observations.
public struct SiegeCell: Hashable, Codable, Sendable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public init(_ x: Int, _ y: Int) { self.init(x: x, y: y) }
}

public enum SiegeDifficulty: String, Codable, CaseIterable, Sendable {
    case standard, hardened
    public var turnLimit: Int { self == .standard ? 12 : 10 }
    public var sentryDamage: Int { self == .standard ? 2 : 3 }
    public var sentryHealth: Int { self == .standard ? 4 : 6 }
}

public enum SiegePhase: String, Codable, Sendable { case active, victory, defeat }
public enum SiegeTerrain: String, Sendable { case floor, wall, cover, relay, extraction }
public enum SiegeCommand: Codable, Equatable, Sendable {
    case move(SiegeCell), pulse, brace, secureRelay, extract, endTurn
}
public enum SiegeError: String, Error, LocalizedError, Sendable {
    case terminal, outOfBounds, blocked, insufficientActions, outOfRange, noLineOfSight
    case alreadyBraced, prerequisite, invalidReceipt, unsupportedVersion, exhausted
    public var errorDescription: String? {
        switch self {
        case .terminal: return "This mission has ended. Replay to try again."
        case .outOfBounds: return "Choose a tile inside the tactical board."
        case .blocked: return "That tile is blocked or already occupied."
        case .insufficientActions: return "Not enough action points. End the turn to refresh AP."
        case .outOfRange: return "The sentry is outside the pulse's four-tile range."
        case .noLineOfSight: return "A wall blocks the pulse. Choose a clear firing position."
        case .alreadyBraced: return "Brace is already active for this turn."
        case .prerequisite: return "That action is unavailable at this location or mission stage."
        case .invalidReceipt: return "This mission receipt failed validation."
        case .unsupportedVersion: return "This mission receipt uses an unsupported rules version."
        case .exhausted: return "This mission receipt exceeds the action limit."
        }
    }
}

/// Signal Siege rules v1: four AP per turn, deterministic movement and damage, and a
/// fully visible patrol / hazard forecast. Only explicit End Turn advances enemies.
/// Codable stores a bounded command receipt and reconstructs state by replay; it
/// never trusts caller-supplied health, victory, score, or board geometry.
public struct SignalSiege: Codable, Equatable, Sendable {
    public static let rulesVersion = 1
    public static let width = 7
    public static let height = 7
    public static let actionsPerTurn = 4
    public static let maximumCommands = 256
    public static let start = SiegeCell(1, 5)
    public static let relay = SiegeCell(5, 1)

    public let seed: UInt64
    public let difficulty: SiegeDifficulty
    public let sessionID: UUID
    public private(set) var phase: SiegePhase = .active
    public private(set) var position = SignalSiege.start
    public private(set) var actions = SignalSiege.actionsPerTurn
    public private(set) var turn = 1
    public private(set) var health = 8
    public private(set) var relaySecured = false
    public private(set) var sentryHealth: Int
    public private(set) var isBraced = false
    public private(set) var commandHistory: [SiegeCommand] = []
    private var patrolStep = 0

    public init(seed: UInt64 = 731, difficulty: SiegeDifficulty = .standard, sessionID: UUID = UUID()) {
        self.seed = seed; self.difficulty = difficulty; self.sessionID = sessionID
        sentryHealth = difficulty.sentryHealth
    }

    public var maxHealth: Int { 8 }
    public var turnLimit: Int { difficulty.turnLimit }
    public var walls: Set<SiegeCell> { [SiegeCell(3, 2), SiegeCell(3, 3), SiegeCell(3, 4)] }
    public var cover: Set<SiegeCell> {
        [SiegeCell(2, 1), SiegeCell(4, 1), SiegeCell(2, 5), SiegeCell(4, 5), SiegeCell(1, 3), SiegeCell(5, 3)]
    }
    private var patrol: [SiegeCell] {
        [SiegeCell(5, 4), SiegeCell(5, 3), SiegeCell(5, 2), SiegeCell(4, 2), SiegeCell(4, 3), SiegeCell(4, 4)]
    }
    public var sentryPosition: SiegeCell { patrol[(Int((seed / 5) % 6) + patrolStep) % patrol.count] }
    public var upcomingSentryPosition: SiegeCell {
        guard sentryHealth > 0 else { return sentryPosition }
        let next = patrol[(Int((seed / 5) % 6) + patrolStep + 1) % patrol.count]
        return next == position ? sentryPosition : next
    }
    /// The row that pulses when the player next ends their turn. The extraction pad is shielded.
    public var upcomingHazardRow: Int { 1 + (Int(seed % 5) + turn - 1) % 5 }
    public var canPulse: Bool {
        phase == .active && actions >= 2 && sentryHealth > 0 &&
        distance(position, sentryPosition) <= 4 && hasLineOfSight(from: position, to: sentryPosition)
    }
    public var canSecureRelay: Bool { phase == .active && actions >= 1 && position == Self.relay && !relaySecured }
    public var canExtract: Bool { phase == .active && actions >= 1 && position == Self.start && relaySecured }
    public var sentryCanHit: Bool {
        sentryHealth > 0 && distance(position, upcomingSentryPosition) <= 4 &&
        hasLineOfSight(from: upcomingSentryPosition, to: position)
    }
    /// A score exists only after successful extraction, never for an abandoned or lost run.
    public var score: Int? {
        guard phase == .victory else { return nil }
        return 1_000 + health * 50 + (turnLimit - turn) * 25 + actions * 10 + (sentryHealth == 0 ? 80 : 0)
    }
    public var outcomeMessage: String {
        switch phase {
        case .victory: return "Relay recovered. Operator extracted."
        case .defeat: return health == 0 ? "Operator signal lost. Replay and change your route." : "Siege window closed. Replay and reach extraction sooner."
        case .active:
            return relaySecured ? "Return to the shielded extraction pad and extract for 1 AP." : "Secure the relay at R, then return to extraction at E."
        }
    }

    public func contains(_ cell: SiegeCell) -> Bool {
        (0..<Self.width).contains(cell.x) && (0..<Self.height).contains(cell.y)
    }
    public func terrain(at cell: SiegeCell) -> SiegeTerrain {
        if walls.contains(cell) { return .wall }
        if cell == Self.start { return .extraction }
        if cell == Self.relay { return .relay }
        return cover.contains(cell) ? .cover : .floor
    }
    private func distance(_ a: SiegeCell, _ b: SiegeCell) -> Int { abs(a.x - b.x) + abs(a.y - b.y) }
    private func walkable(_ cell: SiegeCell) -> Bool {
        contains(cell) && !walls.contains(cell) && (sentryHealth == 0 || cell != sentryPosition)
    }
    private func neighbors(_ cell: SiegeCell) -> [SiegeCell] {
        [SiegeCell(cell.x, cell.y - 1), SiegeCell(cell.x + 1, cell.y),
         SiegeCell(cell.x, cell.y + 1), SiegeCell(cell.x - 1, cell.y)].filter(walkable)
    }
    /// Shortest orthogonal path, excluding the origin. A dead sentry leaves its tile traversable.
    public func path(to destination: SiegeCell) -> [SiegeCell]? {
        guard walkable(destination) else { return nil }
        if destination == position { return [] }
        var queue = [position], cursor = 0
        var previous: [SiegeCell: SiegeCell] = [:]
        var visited: Set<SiegeCell> = [position]
        while cursor < queue.count {
            let cell = queue[cursor]; cursor += 1
            for next in neighbors(cell) where visited.insert(next).inserted {
                previous[next] = cell
                if next == destination {
                    var route = [next], step = next
                    while let parent = previous[step], parent != position { route.append(parent); step = parent }
                    return Array(route.reversed())
                }
                queue.append(next)
            }
        }
        return nil
    }
    public var reachableCells: Set<SiegeCell> {
        guard phase == .active else { return [] }
        return Set((0..<Self.height).flatMap { y in (0..<Self.width).map { SiegeCell($0, y) } }.filter {
            guard let route = path(to: $0) else { return false }
            return !route.isEmpty && route.count <= actions
        })
    }

    /// Conservative supercover: touching a wall corner blocks sight. Segment / tile
    /// intersection is symmetric, so neither combatant gets a corner-peeking advantage.
    public func hasLineOfSight(from origin: SiegeCell, to destination: SiegeCell) -> Bool {
        guard contains(origin), contains(destination), !walls.contains(origin), !walls.contains(destination) else { return false }
        return !walls.contains { wall in
            var lower = 0.0, upper = 1.0
            for (start, end, center) in [(origin.x, destination.x, wall.x), (origin.y, destination.y, wall.y)] {
                let delta = Double(end - start), minimum = Double(center) - 0.5, maximum = Double(center) + 0.5
                if delta == 0 {
                    if Double(start) < minimum || Double(start) > maximum { return false }
                } else {
                    let first = (minimum - Double(start)) / delta, second = (maximum - Double(start)) / delta
                    lower = max(lower, min(first, second)); upper = min(upper, max(first, second))
                    if lower > upper { return false }
                }
            }
            return lower <= upper
        }
    }

    public func replay() -> SignalSiege { SignalSiege(seed: seed, difficulty: difficulty) }

    /// Invalid commands are atomic: validation finishes before any state changes.
    public mutating func apply(_ command: SiegeCommand) throws {
        guard phase == .active else { throw SiegeError.terminal }
        guard commandHistory.count < Self.maximumCommands else { throw SiegeError.exhausted }
        switch command {
        case let .move(destination):
            guard contains(destination) else { throw SiegeError.outOfBounds }
            guard let route = path(to: destination), !route.isEmpty else { throw SiegeError.blocked }
            guard route.count <= actions else { throw SiegeError.insufficientActions }
            actions -= route.count; position = destination
        case .pulse:
            guard actions >= 2 else { throw SiegeError.insufficientActions }
            guard sentryHealth > 0 else { throw SiegeError.prerequisite }
            guard distance(position, sentryPosition) <= 4 else { throw SiegeError.outOfRange }
            guard hasLineOfSight(from: position, to: sentryPosition) else { throw SiegeError.noLineOfSight }
            actions -= 2; sentryHealth = max(0, sentryHealth - 2)
        case .brace:
            guard actions >= 1 else { throw SiegeError.insufficientActions }
            guard !isBraced else { throw SiegeError.alreadyBraced }
            actions -= 1; isBraced = true
        case .secureRelay:
            guard actions >= 1 else { throw SiegeError.insufficientActions }
            guard position == Self.relay, !relaySecured else { throw SiegeError.prerequisite }
            actions -= 1; relaySecured = true
        case .extract:
            guard actions >= 1 else { throw SiegeError.insufficientActions }
            guard position == Self.start, relaySecured else { throw SiegeError.prerequisite }
            actions -= 1; phase = .victory
        case .endTurn:
            // The forecasted patrol position is authoritative. A patrol never moves
            // onto the operator: it stays put and attacks from its previous tile.
            let next = upcomingSentryPosition
            if sentryHealth > 0, next != sentryPosition { patrolStep += 1 }
            var damage = 0
            if sentryHealth > 0, distance(position, sentryPosition) <= 4,
               hasLineOfSight(from: sentryPosition, to: position) {
                damage += max(0, difficulty.sentryDamage - (cover.contains(position) ? 1 : 0) - (isBraced ? 1 : 0))
            }
            if position.y == upcomingHazardRow, position != Self.start { damage += isBraced ? 1 : 2 }
            health = max(0, health - damage)
            isBraced = false
            if health == 0 || turn == turnLimit { phase = .defeat; actions = 0 }
            else { turn += 1; actions = Self.actionsPerTurn }
        }
        commandHistory.append(command)
    }

    public var isValid: Bool {
        guard sessionID.uuidString != "00000000-0000-0000-0000-000000000000", commandHistory.count <= Self.maximumCommands else { return false }
        var reconstructed = SignalSiege(seed: seed, difficulty: difficulty, sessionID: sessionID)
        do { for command in commandHistory { try reconstructed.apply(command) } }
        catch { return false }
        return reconstructed == self
    }

    private enum CodingKeys: String, CodingKey { case version, seed, difficulty, sessionID, commands }
    public func encode(to encoder: Encoder) throws {
        guard isValid else { throw SiegeError.invalidReceipt }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.rulesVersion, forKey: .version)
        try container.encode(seed, forKey: .seed); try container.encode(difficulty, forKey: .difficulty)
        try container.encode(sessionID, forKey: .sessionID); try container.encode(commandHistory, forKey: .commands)
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .version) == Self.rulesVersion else { throw SiegeError.unsupportedVersion }
        let seed = try container.decode(UInt64.self, forKey: .seed)
        let difficulty = try container.decode(SiegeDifficulty.self, forKey: .difficulty)
        let sessionID = try container.decode(UUID.self, forKey: .sessionID)
        guard sessionID.uuidString != "00000000-0000-0000-0000-000000000000" else { throw SiegeError.invalidReceipt }
        self.init(seed: seed, difficulty: difficulty, sessionID: sessionID)
        var commands = try container.nestedUnkeyedContainer(forKey: .commands)
        while !commands.isAtEnd {
            guard commandHistory.count < Self.maximumCommands else { throw SiegeError.exhausted }
            try apply(commands.decode(SiegeCommand.self))
        }
    }
}
