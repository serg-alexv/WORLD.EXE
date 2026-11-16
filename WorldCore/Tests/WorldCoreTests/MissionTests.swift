import XCTest
@testable import WorldCore

final class MissionTests: XCTestCase {
    let sector = Sector.training
    func testShortestPathAndEndpoints() throws {
        let route = try XCTUnwrap(sector.path(from: GridPoint(0, 0), to: GridPoint(2, 2)))
        XCTAssertEqual(route.count - 1, 4)
        XCTAssertEqual(route.first, GridPoint(0, 0))
        XCTAssertEqual(route.last, GridPoint(2, 2))
        for pair in zip(route, route.dropFirst()) {
            XCTAssertEqual(abs(pair.0.x - pair.1.x) + abs(pair.0.y - pair.1.y), 1)
            XCTAssertTrue(sector.isWalkable(pair.1))
        }
        XCTAssertEqual(sector.path(from: GridPoint(0, 0), to: GridPoint(0, 0)), [GridPoint(0, 0)])
    }
    func testBlockedOutOfBoundsAndUnreachable() {
        XCTAssertNil(sector.path(from: GridPoint(0, 0), to: GridPoint(3, 3)))
        XCTAssertNil(sector.path(from: GridPoint(-1, 0), to: GridPoint(0, 0)))
        XCTAssertNil(sector.path(from: GridPoint(0, 0), to: GridPoint(9, 0)))
        XCTAssertNil(sector.path(from: GridPoint(3, 3), to: GridPoint(0, 0)))
        XCTAssertNil(sector.path(from: GridPoint(0, 0), to: GridPoint(2, 0),
                                 avoiding: [GridPoint(1, 0), GridPoint(0, 1)]))
    }
    func testObstacleDetourIsShortest() throws {
        let route = try XCTUnwrap(sector.path(from: GridPoint(2, 3), to: GridPoint(4, 3)))
        XCTAssertEqual(route.count - 1, 6)
        XCTAssertFalse(route.contains(GridPoint(3, 3)))
    }
    func testActionCostsAndFailureAreAtomic() throws {
        var mission = Mission()
        XCTAssertThrowsError(try mission.move(to: GridPoint(4, 7)))
        mission.begin()
        let route = try mission.move(to: GridPoint(4, 5))
        XCTAssertEqual(route.count - 1, 3)
        XCTAssertEqual(mission.actions, 3)
        let before = mission
        XCTAssertThrowsError(try mission.move(to: GridPoint(0, 0)))
        XCTAssertEqual(mission, before)
        XCTAssertThrowsError(try mission.recover())
        XCTAssertEqual(mission, before)
        try mission.endTurn()
        XCTAssertEqual(mission.turn, 2)
        XCTAssertEqual(mission.actions, 6)
    }
    func testCompleteMissionAndObjectiveGating() throws {
        var mission = Mission()
        mission.begin()
        XCTAssertThrowsError(try mission.extract()) { XCTAssertEqual($0 as? MissionError, .missingRelics) }
        for relic in sector.relics {
            try travel(&mission, to: relic)
            if mission.actions == 0 { try mission.endTurn() }
            let before = mission.actions
            try mission.recover()
            XCTAssertEqual(mission.actions, before - 1)
            XCTAssertThrowsError(try mission.recover())
        }
        XCTAssertThrowsError(try mission.extract()) { XCTAssertEqual($0 as? MissionError, .wrongExtraction) }
        try travel(&mission, to: sector.extraction)
        if mission.actions == 0 { try mission.endTurn() }
        try mission.extract()
        XCTAssertEqual(mission.phase, .success)
        XCTAssertTrue(mission.isValid)
        XCTAssertThrowsError(try mission.endTurn())
        mission.reset()
        XCTAssertEqual(mission, Mission())
    }
    func testRecoveryRequiresActionPoint() throws {
        var mission = Mission()
        mission.begin()
        try mission.move(to: GridPoint(4, 7))
        try mission.endTurn()
        try mission.move(to: GridPoint(4, 8))
        try mission.move(to: GridPoint(7, 6))
        XCTAssertEqual(mission.actions, 0)
        XCTAssertTrue(sector.relics.contains(mission.position))
        let before = mission
        XCTAssertThrowsError(try mission.recover()) {
            XCTAssertEqual($0 as? MissionError, .insufficientActions)
        }
        XCTAssertEqual(mission, before)
    }
    func testCodableAndInvalidVersion() throws {
        var mission = Mission()
        mission.begin()
        try mission.move(to: GridPoint(4, 7))
        let data = try JSONEncoder().encode(mission)
        XCTAssertEqual(try JSONDecoder().decode(Mission.self, from: data), mission)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 999
        let invalid = try JSONDecoder().decode(Mission.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(invalid.isValid)
        object["version"] = Mission.schemaVersion
        object["actions"] = -1
        let badActions = try JSONDecoder().decode(Mission.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(badActions.isValid)
    }
    private func travel(_ mission: inout Mission, to destination: GridPoint) throws {
        let route = try XCTUnwrap(sector.path(from: mission.position, to: destination))
        for step in route.dropFirst() {
            if mission.actions == 0 { try mission.endTurn() }
            try mission.move(to: step)
        }
    }
}
