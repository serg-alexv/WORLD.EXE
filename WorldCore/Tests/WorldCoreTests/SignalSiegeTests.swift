import Foundation
import XCTest
@testable import WorldCore

final class SignalSiegeTests: XCTestCase {
    private func rejects(_ mission: inout SignalSiege, _ command: SiegeCommand, _ error: SiegeError) {
        let before = mission
        XCTAssertThrowsError(try mission.apply(command)) { XCTAssertEqual($0 as? SiegeError, error) }
        XCTAssertEqual(mission, before, "Rejected commands must leave the complete receipt unchanged")
    }

    /// A deliberate cover route, not a hidden win command. Every seed admits this
    /// route; players can improve its score by taking shorter, riskier routes.
    private func win(seed: UInt64 = 731, difficulty: SiegeDifficulty = .standard) throws -> SignalSiege {
        var mission = SignalSiege(seed: seed, difficulty: difficulty)
        try mission.apply(.move(SiegeCell(1, 1))); try mission.apply(.endTurn)
        try mission.apply(.move(SiegeCell(4, 1))); try mission.apply(.brace); try mission.apply(.endTurn)
        while mission.sentryHealth > 0 {
            if mission.actions < 2 { try mission.apply(.endTurn) }
            try mission.apply(.pulse)
        }
        if mission.actions < 2 { try mission.apply(.endTurn) }
        try mission.apply(.move(Self.relay)); try mission.apply(.secureRelay)
        if mission.actions < 4 { try mission.apply(.endTurn) }
        try mission.apply(.move(SiegeCell(1, 1))); try mission.apply(.endTurn)
        try mission.apply(.move(Self.start)); try mission.apply(.endTurn)
        try mission.apply(.extract)
        return mission
    }
    private static var start: SiegeCell { SignalSiege.start }
    private static var relay: SiegeCell { SignalSiege.relay }

    func testFreshMissionHasCompleteRulesAndNoScore() {
        let mission = SignalSiege()
        XCTAssertEqual(mission.phase, .active); XCTAssertEqual(mission.position, Self.start)
        XCTAssertEqual(mission.actions, 4); XCTAssertEqual(mission.turn, 1)
        XCTAssertEqual(mission.health, mission.maxHealth); XCTAssertNil(mission.score)
        XCTAssertFalse(mission.relaySecured); XCTAssertTrue(mission.isValid)
        XCTAssertEqual(mission.terrain(at: Self.relay), .relay)
        XCTAssertEqual(mission.terrain(at: Self.start), .extraction)
        XCTAssertEqual(SignalSiege(seed: 0, difficulty: .hardened).turnLimit, 10)
    }

    func testMovementChargesShortestOrthogonalPathAndNeverAutoEndsTurn() throws {
        var mission = SignalSiege(seed: 0)
        XCTAssertEqual(mission.path(to: SiegeCell(1, 1))?.count, 4)
        try mission.apply(.move(SiegeCell(1, 1)))
        XCTAssertEqual(mission.actions, 0); XCTAssertEqual(mission.turn, 1)
        XCTAssertEqual(mission.commandHistory.count, 1)
        rejects(&mission, .move(SiegeCell(2, 1)), .insufficientActions)
        try mission.apply(.endTurn)
        XCTAssertEqual(mission.actions, 4); XCTAssertEqual(mission.turn, 2)
    }

    func testWallDetourEnemyOccupancyAndInvalidMovesAreAtomic() {
        var mission = SignalSiege(seed: 0)
        rejects(&mission, .move(SiegeCell(-1, 5)), .outOfBounds)
        rejects(&mission, .move(SiegeCell(Int.max, Int.min)), .outOfBounds)
        rejects(&mission, .move(SiegeCell(3, 3)), .blocked)
        rejects(&mission, .move(mission.sentryPosition), .blocked)
        rejects(&mission, .move(mission.position), .blocked)
        rejects(&mission, .move(SiegeCell(4, 3)), .insufficientActions)
        XCTAssertEqual(mission.path(to: SiegeCell(4, 3))?.count, 5)
        XCTAssertFalse(mission.reachableCells.contains(SiegeCell(3, 3)))
        XCTAssertTrue(mission.reachableCells.contains(SiegeCell(1, 4)))
    }

    func testSightIsSymmetricAndWallsBlockCornerPeeking() {
        let mission = SignalSiege()
        let cells = (0..<7).flatMap { y in (0..<7).map { SiegeCell($0, y) } }
        for a in cells { for b in cells {
            XCTAssertEqual(mission.hasLineOfSight(from: a, to: b), mission.hasLineOfSight(from: b, to: a))
        } }
        XCTAssertFalse(mission.hasLineOfSight(from: SiegeCell(2, 3), to: SiegeCell(4, 3)))
        XCTAssertFalse(mission.hasLineOfSight(from: SiegeCell(2, 2), to: SiegeCell(4, 0)))
        XCTAssertTrue(mission.hasLineOfSight(from: SiegeCell(1, 1), to: SiegeCell(5, 1)))
        XCTAssertFalse(mission.hasLineOfSight(from: SiegeCell(-1, 1), to: SiegeCell(5, 1)))
    }

    func testCoverAndBraceEachReduceRealEnemyDamage() throws {
        var covered = SignalSiege(seed: 0, difficulty: .hardened)
        try covered.apply(.move(SiegeCell(1, 1))); try covered.apply(.endTurn)
        try covered.apply(.move(SiegeCell(4, 1)))
        var exposed = covered, braced = covered
        try exposed.apply(.move(SiegeCell(5, 1))); try braced.apply(.brace)
        let initialHealth = covered.health
        XCTAssertNotEqual(covered.upcomingHazardRow, 1)
        XCTAssertTrue(covered.sentryCanHit); XCTAssertTrue(exposed.sentryCanHit)
        try covered.apply(.endTurn); try exposed.apply(.endTurn); try braced.apply(.endTurn)
        XCTAssertEqual(initialHealth - exposed.health, 3)
        XCTAssertEqual(initialHealth - covered.health, 2)
        XCTAssertEqual(initialHealth - braced.health, 1)
        XCTAssertFalse(braced.isBraced)
    }

    func testBraceCannotStackAndResetsOnlyAtEnemyTurn() throws {
        var mission = SignalSiege(seed: 0)
        try mission.apply(.brace); XCTAssertEqual(mission.actions, 3)
        rejects(&mission, .brace, .alreadyBraced)
        try mission.apply(.move(SiegeCell(1, 4))); XCTAssertTrue(mission.isBraced)
        try mission.apply(.endTurn); XCTAssertFalse(mission.isBraced)
        try mission.apply(.brace); XCTAssertTrue(mission.isBraced)
    }

    func testHazardForecastMatchesDamageAndPadIsShielded() throws {
        var exposed = SignalSiege(seed: 3), braced = SignalSiege(seed: 3)
        XCTAssertEqual(exposed.upcomingHazardRow, 4)
        try exposed.apply(.move(SiegeCell(1, 4))); try braced.apply(.move(SiegeCell(1, 4)))
        try braced.apply(.brace)
        XCTAssertFalse(exposed.sentryCanHit)
        try exposed.apply(.endTurn); try braced.apply(.endTurn)
        XCTAssertEqual(exposed.health, 6); XCTAssertEqual(braced.health, 7)
        XCTAssertEqual(exposed.upcomingHazardRow, 5)
        var shielded = SignalSiege(seed: 4)
        XCTAssertEqual(shielded.upcomingHazardRow, Self.start.y)
        try shielded.apply(.endTurn); XCTAssertEqual(shielded.health, shielded.maxHealth)
    }

    func testPulseHasDeterministicDamageAndRequiresRangeAndSight() throws {
        var blocked = SignalSiege(seed: 15)
        try blocked.apply(.move(SiegeCell(2, 5))); try blocked.apply(.endTurn)
        rejects(&blocked, .pulse, .noLineOfSight)
        var mission = SignalSiege(seed: 0)
        rejects(&mission, .pulse, .outOfRange)
        try mission.apply(.move(SiegeCell(1, 1))); try mission.apply(.endTurn)
        try mission.apply(.move(SiegeCell(4, 1))); try mission.apply(.endTurn)
        XCTAssertTrue(mission.canPulse)
        try mission.apply(.pulse); XCTAssertEqual(mission.sentryHealth, 2); XCTAssertEqual(mission.actions, 2)
        try mission.apply(.pulse); XCTAssertEqual(mission.sentryHealth, 0)
        try mission.apply(.endTurn); rejects(&mission, .pulse, .prerequisite)
        XCTAssertFalse(mission.sentryCanHit)
    }

    func testPatrolForecastResolvesCollisionBeforeAdvertisingTheEnemyPosition() throws {
        var mission = SignalSiege(seed: 0)
        try mission.apply(.move(SiegeCell(4, 5))); try mission.apply(.endTurn)
        XCTAssertEqual(mission.sentryPosition, SiegeCell(5, 3))
        try mission.apply(.move(SiegeCell(5, 2)))
        XCTAssertEqual(mission.upcomingSentryPosition, mission.sentryPosition)
        let forecast = mission.upcomingSentryPosition
        XCTAssertTrue(mission.sentryCanHit)
        try mission.apply(.endTurn)
        XCTAssertEqual(mission.sentryPosition, forecast)
        XCTAssertNotEqual(mission.sentryPosition, mission.position)
    }

    func testRelayAndExtractionRequireTheirLocationsAndActions() throws {
        var mission = SignalSiege()
        rejects(&mission, .extract, .prerequisite); rejects(&mission, .secureRelay, .prerequisite)
        try mission.apply(.move(SiegeCell(1, 1))); try mission.apply(.endTurn)
        try mission.apply(.move(Self.relay))
        rejects(&mission, .secureRelay, .insufficientActions)
        try mission.apply(.endTurn); try mission.apply(.secureRelay)
        XCTAssertTrue(mission.relaySecured); XCTAssertNil(mission.score)
        rejects(&mission, .secureRelay, .prerequisite); rejects(&mission, .extract, .prerequisite)
    }

    func testCompletedMissionScoresOnlyOnceAndRejectsFurtherGameplay() throws {
        var mission = try win()
        XCTAssertEqual(mission.phase, .victory); XCTAssertNotNil(mission.score)
        XCTAssertTrue(mission.canExtract == false); XCTAssertTrue(mission.isValid)
        let score = mission.score
        for command in [SiegeCommand.extract, .endTurn, .pulse, .move(Self.relay)] { rejects(&mission, command, .terminal) }
        XCTAssertEqual(mission.score, score)
    }

    func testBothDifficultiesHaveAWinningCoverRouteForEveryPatrolHazardCombination() throws {
        // The 30 seeds cover the complete 5-row x 6-patrol offset state space.
        for difficulty in SiegeDifficulty.allCases {
            for seed in UInt64(0)..<UInt64(30) {
                let mission = try win(seed: seed, difficulty: difficulty)
                XCTAssertEqual(mission.phase, .victory, "seed \(seed), \(difficulty)")
                XCTAssertGreaterThan(mission.health, 0); XCTAssertLessThanOrEqual(mission.turn, mission.turnLimit)
            }
        }
        XCTAssertEqual(try win(seed: UInt64.max, difficulty: .hardened).phase, .victory)
    }

    func testDeadlineDefeatHasNoScoreAndCannotResume() throws {
        for difficulty in SiegeDifficulty.allCases {
            var mission = SignalSiege(seed: 0, difficulty: difficulty)
            for _ in 0..<difficulty.turnLimit { try mission.apply(.endTurn) }
            XCTAssertEqual(mission.phase, .defeat); XCTAssertEqual(mission.turn, mission.turnLimit)
            XCTAssertEqual(mission.health, mission.maxHealth); XCTAssertNil(mission.score)
            XCTAssertTrue(mission.outcomeMessage.contains("window"))
            rejects(&mission, .extract, .terminal)
        }
    }

    func testHealthDefeatStopsTheMission() throws {
        var mission = SignalSiege(seed: 0, difficulty: .hardened)
        try mission.apply(.move(SiegeCell(1, 1))); try mission.apply(.endTurn)
        try mission.apply(.move(Self.relay))
        while mission.phase == .active { try mission.apply(.endTurn) }
        XCTAssertEqual(mission.phase, .defeat); XCTAssertEqual(mission.health, 0)
        XCTAssertNil(mission.score); XCTAssertTrue(mission.outcomeMessage.contains("signal lost"))
    }

    func testSeedReplayReproducesGameplayAndCreatesANewSession() throws {
        let completed = try win(seed: UInt64.max, difficulty: .hardened)
        var replay = completed.replay()
        XCTAssertNotEqual(replay.sessionID, completed.sessionID)
        XCTAssertEqual(replay.seed, completed.seed); XCTAssertEqual(replay.difficulty, completed.difficulty)
        XCTAssertEqual(replay.phase, .active); XCTAssertNil(replay.score)
        for command in completed.commandHistory { try replay.apply(command) }
        XCTAssertEqual(replay.position, completed.position); XCTAssertEqual(replay.health, completed.health)
        XCTAssertEqual(replay.score, completed.score); XCTAssertEqual(replay.commandHistory, completed.commandHistory)
    }

    func testCodableReceiptReconstructsVictoryInsteadOfTrustingScoreFields() throws {
        let completed = try win(seed: 731, difficulty: .hardened)
        let encoded = try JSONEncoder().encode(completed)
        XCTAssertEqual(try JSONDecoder().decode(SignalSiege.self, from: encoded), completed)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["score"]); XCTAssertNil(object["health"]); XCTAssertNil(object["phase"])
        object["score"] = 9_999_999; object["phase"] = "victory"; object["commands"] = []
        let restored = try JSONDecoder().decode(SignalSiege.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.score); XCTAssertEqual(restored.phase, .active)
    }

    func testCodableRejectsFutureVersionsZeroSessionsAndImpossibleReceipts() throws {
        let data = try JSONEncoder().encode(SignalSiege(seed: 1))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in [("version", 2 as Any), ("seed", -1 as Any), ("difficulty", "impossible" as Any),
                             ("sessionID", "00000000-0000-0000-0000-000000000000" as Any)] {
            var bad = original; bad[key] = value
            XCTAssertThrowsError(try JSONDecoder().decode(SignalSiege.self, from: JSONSerialization.data(withJSONObject: bad)))
        }
        var premature = original
        premature["commands"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([SiegeCommand.extract]))
        XCTAssertThrowsError(try JSONDecoder().decode(SignalSiege.self, from: JSONSerialization.data(withJSONObject: premature)))
        var flooded = original
        flooded["commands"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Array(repeating: SiegeCommand.endTurn, count: 257)))
        XCTAssertThrowsError(try JSONDecoder().decode(SignalSiege.self, from: JSONSerialization.data(withJSONObject: flooded)))
    }
}
