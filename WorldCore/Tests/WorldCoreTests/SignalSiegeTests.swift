import XCTest
@testable import WorldCore

final class SignalSiegeTests: XCTestCase {
    func testInitialState() {
        let game = SiegeGame()
        XCTAssertEqual(game.ap, 2)
        XCTAssertEqual(game.playerHP, 5)
        XCTAssertFalse(game.finished)
    }
    func testMoveConsumesAP() throws {
        var game = SiegeGame()
        try game.act(.move(SiegePoint(1,0)))
        XCTAssertEqual(game.player, SiegePoint(1,0))
        XCTAssertEqual(game.ap, 1)
    }
    func testCannotTeleport() {
        var game = SiegeGame()
        XCTAssertThrowsError(try game.act(.move(SiegePoint(5,5))))
        XCTAssertEqual(game.ap, 2)
    }
    func testCannotMoveIntoCover() {
        var game = SiegeGame()
        try? game.act(.move(SiegePoint(1,0)))
        try? game.act(.endTurn)
        try? game.act(.move(SiegePoint(1,1)))
        XCTAssertThrowsError(try game.act(.move(SiegePoint(2,2))))
    }
    func testNoShootingAtLongRange() {
        var game = SiegeGame()
        XCTAssertThrowsError(try game.act(.fire))
        XCTAssertEqual(game.enemyHP, 3)
    }
    func testBraceConsumesAP() throws {
        var game = SiegeGame()
        try game.act(.brace)
        XCTAssertTrue(game.braced)
        XCTAssertEqual(game.ap, 1)
    }
    func testTurnResetsAP() throws {
        var game = SiegeGame()
        try game.act(.brace)
        try game.act(.endTurn)
        XCTAssertEqual(game.ap, 2)
        XCTAssertEqual(game.turn, 2)
        XCTAssertFalse(game.braced)
    }
    func testCannotSpendNegativeAP() throws {
        var game = SiegeGame()
        try game.act(.brace)
        try game.act(.brace)
        XCTAssertThrowsError(try game.act(.brace))
        XCTAssertEqual(game.ap, 0)
    }
    func testUnfinishedGameNotRanked() {
        var ranks = SiegeLeaderboard()
        ranks.submit(SiegeGame())
        XCTAssertTrue(ranks.entries.isEmpty)
    }
    func testLeaderboardRejectsUnfinishedRepeatedSessions() {
        var ranks = SiegeLeaderboard()
        let game = SiegeGame()
        ranks.submit(game)
        ranks.submit(game)
        XCTAssertEqual(ranks.entries.count, 0)
    }    func testCodableRoundTrip() throws {
        let game = SiegeGame()
        XCTAssertEqual(try JSONDecoder().decode(SiegeGame.self, from: JSONEncoder().encode(game)), game)
    }
    func testNoSensorDependencies() {
        XCTAssertTrue(SiegeGame.cover.allSatisfy { !SiegeGame.valid($0) })
    }
}
