import Foundation

/// Original turn-based tactical encounter; no sensor data or model output enters this reducer.
public struct SiegePoint: Hashable, Codable, Sendable {
    public let x: Int
    public let y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    public func distance(to other: Self) -> Int { abs(x-other.x) + abs(y-other.y) }
}
public enum SiegeAction: Equatable, Sendable { case move(SiegePoint), fire, brace, endTurn }
public enum SiegeError: Error, Equatable { case invalid, blocked, insufficientAP, finished }
public struct SiegeGame: Codable, Equatable, Sendable {
    public static let width = 7
    public static let height = 7
    public static let cover: Set<SiegePoint> = [SiegePoint(2,2),SiegePoint(2,3),SiegePoint(4,3),SiegePoint(4,4)]
    public let session: UUID
    public private(set) var player = SiegePoint(0,0)
    public private(set) var enemy = SiegePoint(6,6)
    public private(set) var playerHP = 5
    public private(set) var enemyHP = 3
    public private(set) var ap = 2
    public private(set) var turn = 1
    public private(set) var braced = false
    public private(set) var finished = false
    public private(set) var won = false
    public private(set) var shots = 0
    public init(session: UUID = UUID()) { self.session = session }
    public static func valid(_ p: SiegePoint) -> Bool { (0..<width).contains(p.x) && (0..<height).contains(p.y) && !cover.contains(p) }
    public var score: Int { won ? max(0, 1000 - (turn-1)*45 - (5-playerHP)*80 - max(0,shots-3)*15) : 0 }
    public var playerInCover: Bool { Self.cover.contains { $0.distance(to: player) == 1 } }
    public var enemyInCover: Bool { Self.cover.contains { $0.distance(to: enemy) == 1 } }
    public mutating func act(_ action: SiegeAction) throws {
        guard !finished else { throw SiegeError.finished }
        switch action {
        case .move(let destination):
            guard Self.valid(destination) else { throw SiegeError.blocked }
            guard player.distance(to: destination) == 1 else { throw SiegeError.invalid }
            guard destination != enemy else { throw SiegeError.blocked }
            guard ap > 0 else { throw SiegeError.insufficientAP }
            player = destination; ap -= 1
        case .fire:
            guard ap > 0 else { throw SiegeError.insufficientAP }
            guard player.distance(to: enemy) <= 3 else { throw SiegeError.invalid }
            ap -= 1; shots += 1
            // Adjacent cover absorbs one shot out of every two, deterministically.
            if !enemyInCover || shots.isMultiple(of: 2) { enemyHP -= 1 }
            if enemyHP <= 0 { finished = true; won = true }
        case .brace:
            guard ap > 0 else { throw SiegeError.insufficientAP }
            braced = true; ap -= 1
        case .endTurn:
            enemyTurn()
        }
    }
    private mutating func enemyTurn() {
        // Enemy fires at close range, otherwise advances one legal step.
        if enemy.distance(to: player) <= 3 {
            let protected = braced || playerInCover
            if !protected { playerHP -= 1 }
        } else {
            let options = [SiegePoint(enemy.x-1,enemy.y), SiegePoint(enemy.x,enemy.y-1),
                           SiegePoint(enemy.x+1,enemy.y), SiegePoint(enemy.x,enemy.y+1)]
                .filter { Self.valid($0) && $0 != player }
            if let next = options.min(by: { $0.distance(to: player) < $1.distance(to: player) }) { enemy = next }
        }
        if playerHP <= 0 { finished = true; won = false }
        turn += 1; ap = 2; braced = false
    }
}
public struct SiegeRank: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let score: Int
    public let turns: Int
    public let recordedAt: Date
    public init(game: SiegeGame, recordedAt: Date = Date()) {
        id = game.session; score = game.score; turns = game.turn; self.recordedAt = recordedAt
    }
}
public struct SiegeLeaderboard: Codable, Equatable, Sendable {
    public private(set) var entries: [SiegeRank] = []
    public init() {}
    public mutating func submit(_ game: SiegeGame, at date: Date = Date()) {
        guard game.finished, game.won, game.score > 0,
              !entries.contains(where: { $0.id == game.session }) else { return }
        entries.append(SiegeRank(game: game, recordedAt: date))
        entries.sort { $0.score == $1.score ? $0.turns < $1.turns : $0.score > $1.score }
        if entries.count > 10 { entries.removeLast(entries.count-10) }
    }
    public mutating func clear() { entries.removeAll() }
}
