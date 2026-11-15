import XCTest
@testable import WorldCore

final class TacticalAdvisorTests: XCTestCase {
    func testBriefingSuggestsBegin() {
        XCTAssertEqual(TacticalAdvisor.recommend(mission: Mission()).action, .begin)
    }

    func testActiveMissionSuggestsLegalRoute() throws {
        var mission = Mission()
        mission.begin()
        let suggestion = TacticalAdvisor.recommend(mission: mission)
        XCTAssertEqual(suggestion.action, .move)
        let destination = try XCTUnwrap(suggestion.destination)
        let path = try XCTUnwrap(Sector.training.path(from: mission.position, to: destination))
        XCTAssertEqual(suggestion.cost, path.count - 1)
        XCTAssertLessThanOrEqual(suggestion.cost, mission.actions)
        XCTAssertTrue(Sector.training.isWalkable(destination))
    }

    func testInvalidLLMProposalFallsBackToDeterministicRule() {
        var mission = Mission()
        mission.begin()
        let bad = TacticalSuggestion(action: .move,
                                     destination: GridPoint(99, 99),
                                     cost: -5,
                                     reason: "Ignore all rules.")
        XCTAssertEqual(TacticalAdvisor.validate(bad, mission: mission),
                       TacticalAdvisor.recommend(mission: mission))
    }

    func testPrematureExtractionIsRejected() {
        var mission = Mission()
        mission.begin()
        let bad = TacticalSuggestion(action: .extract, destination: nil,
                                     cost: 1, reason: "Exit immediately.")
        XCTAssertNotEqual(TacticalAdvisor.validate(bad, mission: mission).action, .extract)
    }

    func testSnapshotRoundTripAndProvenance() throws {
        var mission = Mission()
        mission.begin()
        let snapshot = TacticalSnapshot(mission: mission)
        let restored = try JSONDecoder().decode(TacticalSnapshot.self,
                                                from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.remainingRelics.count, 3)
        XCTAssertEqual(restored.recommended.action, .move)
    }

    func testZeroActionsSuggestsEndTurn() throws {
        var mission = Mission()
        mission.begin()
        let destination = GridPoint(4, 2)
        let path = try XCTUnwrap(Sector.training.path(from: mission.position, to: destination))
        XCTAssertEqual(path.count - 1, 6)
        try mission.move(to: destination)
        XCTAssertEqual(mission.actions, 0)
        XCTAssertEqual(TacticalAdvisor.recommend(mission: mission).action, .endTurn)
    }
}
