import Foundation

/// Validated, deterministic tactical decisions. Language models may explain a
/// proposal but cannot override the authoritative Mission state machine.
public struct TacticalSuggestion: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case begin, move, recover, extract, endTurn, completed
    }
    public let action: Action
    public let destination: GridPoint?
    public let cost: Int
    public let reason: String
    public init(action: Action, destination: GridPoint?, cost: Int, reason: String) {
        self.action = action; self.destination = destination
        self.cost = cost; self.reason = reason
    }
}

public struct TacticalSnapshot: Codable, Sendable {
    public let phase: MissionPhase
    public let position: GridPoint
    public let actions: Int
    public let turn: Int
    public let remainingRelics: [GridPoint]
    public let extraction: GridPoint
    public let recommended: TacticalSuggestion

    public init(mission: Mission, sector: Sector = .training) {
        phase = mission.phase; position = mission.position
        actions = mission.actions; turn = mission.turn
        remainingRelics = sector.relics.filter { !mission.recovered.contains($0) }
        extraction = sector.extraction
        recommended = TacticalAdvisor.recommend(mission: mission, sector: sector)
    }
}

public enum TacticalAdvisor {
    /// Chooses a legal next action, with stable tie-breaking and no model dependency.
    public static func recommend(mission: Mission, sector: Sector = .training) -> TacticalSuggestion {
        func suggest(_ action: TacticalSuggestion.Action, _ destination: GridPoint? = nil,
                     _ cost: Int = 0, _ reason: String) -> TacticalSuggestion {
            TacticalSuggestion(action: action, destination: destination, cost: cost, reason: reason)
        }
        switch mission.phase {
        case .briefing:
            return suggest(.begin, nil, 0, "Begin the expedition.")
        case .success:
            return suggest(.completed, nil, 0, "All objectives recovered.")
        case .active:
            break
        }
        let remaining = sector.relics.filter { !mission.recovered.contains($0) }
        if remaining.contains(mission.position) {
            return mission.actions > 0
                ? suggest(.recover, nil, 1, "Recover the relic at the squad's position.")
                : suggest(.endTurn, nil, 0, "Refresh action points before recovery.")
        }
        if remaining.isEmpty && mission.position == sector.extraction {
            return mission.actions > 0
                ? suggest(.extract, nil, 1, "All relics secured; extract.")
                : suggest(.endTurn, nil, 0, "Refresh action points before extraction.")
        }
        let targets = remaining.isEmpty ? [sector.extraction] : remaining
        let routes = targets.compactMap { target -> (GridPoint, [GridPoint])? in
            guard let path = sector.path(from: mission.position, to: target) else { return nil }
            return (target, path)
        }
        guard let best = routes.min(by: {
            if $0.1.count != $1.1.count { return $0.1.count < $1.1.count }
            if $0.0.y != $1.0.y { return $0.0.y < $1.0.y }
            return $0.0.x < $1.0.x
        }) else {
            return suggest(.endTurn, nil, 0, "No reachable objective; inspect sector.")
        }
        guard mission.actions > 0 else {
            return suggest(.endTurn, nil, 0, "Refresh action points.")
        }
        let steps = min(mission.actions, best.1.count - 1)
        guard steps > 0 else {
            return suggest(.endTurn, nil, 0, "Wait for next turn.")
        }
        return suggest(.move, best.1[steps], steps,
                       "Advance along a verified walkable route toward the nearest objective.")
    }

    /// Validate a model-proposed action against the authoritative recommendation
    /// and current game rules. Unsupported or illegal proposals fall back safely.
    public static func validate(_ proposed: TacticalSuggestion, mission: Mission,
                                sector: Sector = .training) -> TacticalSuggestion {
        let fallback = recommend(mission: mission, sector: sector)
        guard mission.phase == .active else { return fallback }
        switch proposed.action {
        case .move:
            guard let destination = proposed.destination,
                  let route = sector.path(from: mission.position, to: destination),
                  route.count > 1, route.count - 1 <= mission.actions,
                  proposed.cost == route.count - 1 else { return fallback }
            return proposed
        case .recover:
            guard sector.relics.contains(mission.position),
                  !mission.recovered.contains(mission.position),
                  mission.actions > 0, proposed.cost == 1 else { return fallback }
            return proposed
        case .extract:
            guard mission.position == sector.extraction,
                  mission.recovered.count == sector.relics.count,
                  mission.actions > 0, proposed.cost == 1 else { return fallback }
            return proposed
        case .endTurn:
            return proposed.cost == 0 ? proposed : fallback
        case .begin, .completed:
            return fallback
        }
    }
}
