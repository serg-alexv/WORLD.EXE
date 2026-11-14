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
    /// Breadth-first search with stable neighbor ordering. Includes both endpoints.
    public func path(from start: GridPoint, to goal: GridPoint) -> [GridPoint]? {
        guard isWalkable(start), isWalkable(goal) else { return nil }
        var queue = [start]
        var head = 0
        var visited: Set<GridPoint> = [start]
        var previous: [GridPoint: GridPoint] = [:]
        while head < queue.count {
            let current = queue[head]
            head += 1
            if current == goal {
                var result = [goal]
                var cursor = goal
                while cursor != start {
                    guard let parent = previous[cursor] else { return nil }
                    result.append(parent)
                    cursor = parent
                }
                return result.reversed()
            }
            for next in current.neighbors where isWalkable(next) {
                if visited.insert(next).inserted {
                    previous[next] = current
                    queue.append(next)
                }
            }
        }
        return nil
    }
    /// Also useful for custom blocked-map checks without changing the mission map.
    public func path(from start: GridPoint, to goal: GridPoint,
                     avoiding extra: Set<GridPoint>) -> [GridPoint]? {
        guard !extra.contains(start), !extra.contains(goal),
              isWalkable(start), isWalkable(goal) else { return nil }
        var queue = [[start]]
        var visited: Set<GridPoint> = [start]
        var head = 0
        while head < queue.count {
            let route = queue[head]
            head += 1
            guard let current = route.last else { continue }
            if current == goal { return route }
            for next in current.neighbors
            where isWalkable(next) && !extra.contains(next) && !visited.contains(next) {
                visited.insert(next)
                queue.append(route + [next])
            }
        }
        return nil
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
