import Foundation
import XCTest
@testable import WorldCore

final class SiegeLeaderboardTests: XCTestCase {
    private func victory(seed: UInt64 = 31, difficulty: SiegeDifficulty = .standard,
                         id: UUID = UUID(), braceBeforeExtraction: Bool = false) throws -> SignalSiege {
        var mission = SignalSiege(seed: seed, difficulty: difficulty, sessionID: id)
        let opening: [SiegeCommand] = [
            .move(SiegeCell(x: 1, y: 1)), .endTurn,
            .move(SiegeCell(x: 4, y: 1)), .brace, .endTurn,
            .pulse, .pulse, .endTurn
        ]
        for action in opening { try mission.apply(action) }
        if difficulty == .hardened {
            for action in [SiegeCommand.pulse, .move(SiegeCell(x: 5, y: 1)), .secureRelay, .endTurn] {
                try mission.apply(action)
            }
        } else {
            for action in [SiegeCommand.move(SiegeCell(x: 5, y: 1)), .secureRelay,
                           .move(SiegeCell(x: 4, y: 1)), .endTurn] {
                try mission.apply(action)
            }
        }
        for action in [SiegeCommand.move(SiegeCell(x: 1, y: 1)), .endTurn,
                       .move(SiegeCell(x: 1, y: 5)), .endTurn] {
            try mission.apply(action)
        }
        if braceBeforeExtraction { try mission.apply(.brace) }
        try mission.apply(.extract)
        XCTAssertEqual(mission.phase, .victory)
        XCTAssertTrue(mission.isValid)
        return mission
    }

    private func object(_ board: SiegeLeaderboard) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: board.encoded()) as? [String: Any])
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func testEmptyArchiveRoundTripsWithExplicitVersionAndMode() throws {
        let board = SiegeLeaderboard()
        let decoded = try SiegeLeaderboard(data: board.encoded())
        XCTAssertTrue(decoded.isEmpty)
        XCTAssertEqual(decoded.recordedSessionCount, 0)
        XCTAssertEqual(try object(board)["version"] as? Int, 1)
        XCTAssertEqual(try object(board)["mode"] as? String, "signalSiege")
        XCTAssertEqual(board, decoded)
    }

    func testOnlyCompletedVictoriesCanScore() throws {
        var board = SiegeLeaderboard()
        XCTAssertThrowsError(try board.record(SignalSiege(seed: 31))) {
            XCTAssertEqual($0 as? SiegeLeaderboardError, .incompleteMission)
        }
        XCTAssertTrue(board.isEmpty)
        XCTAssertEqual(board.recordedSessionCount, 0)
    }

    func testDefeatCannotScoreAndInvalidSessionCannotSubmit() throws {
        var board = SiegeLeaderboard()
        var defeated = SignalSiege(seed: 31)
        while defeated.phase == .active { try defeated.apply(.endTurn) }
        XCTAssertEqual(defeated.phase, .defeat)
        XCTAssertThrowsError(try board.record(defeated)) {
            XCTAssertEqual($0 as? SiegeLeaderboardError, .incompleteMission)
        }
        let completed = try victory()
        let nilID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        var invalid = SignalSiege(seed: completed.seed, difficulty: completed.difficulty, sessionID: nilID)
        for action in completed.commandHistory { try invalid.apply(action) }
        XCTAssertEqual(invalid.phase, .victory)
        XCTAssertFalse(invalid.isValid)
        XCTAssertThrowsError(try board.record(invalid)) {
            XCTAssertEqual($0 as? SiegeLeaderboardError, .invalidMission)
        }
        XCTAssertTrue(board.isEmpty)
    }

    func testVictoryFieldsAndCanonicalPersistence() throws {
        let mission = try victory()
        var board = SiegeLeaderboard()
        XCTAssertTrue(try board.record(mission))
        let row = try XCTUnwrap(board.entries(seed: mission.seed, difficulty: mission.difficulty).first)
        XCTAssertEqual(row.id, mission.sessionID)
        XCTAssertEqual(row.score, mission.score)
        XCTAssertEqual(row.turn, mission.turn)
        XCTAssertEqual(row.seed, mission.seed)
        XCTAssertEqual(row.difficulty, mission.difficulty)
        let restored = try SiegeLeaderboard(data: board.encoded())
        XCTAssertEqual(board, restored)
        XCTAssertEqual(try board.encoded(), try restored.encoded())
    }

    func testDuplicateSessionsRemainRejectedAfterPersistence() throws {
        let mission = try victory()
        var board = SiegeLeaderboard()
        XCTAssertTrue(try board.record(mission))
        let before = try board.encoded()
        XCTAssertFalse(try board.record(mission))
        XCTAssertEqual(before, try board.encoded())
        var restored = try SiegeLeaderboard(data: before)
        XCTAssertFalse(try restored.record(mission))
        XCTAssertEqual(restored.recordedSessionCount, 1)
    }

    func testTopTenTieBreakAndEvictedSessionLedger() throws {
        var board = SiegeLeaderboard()
        var first: SignalSiege?
        for number in (1...12).reversed() {
            let id = try XCTUnwrap(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)))
            let mission = try victory(id: id)
            if first == nil { first = mission }
            try board.record(mission)
        }
        let entries = board.entries(seed: 31, difficulty: .standard)
        XCTAssertEqual(entries.count, 10)
        XCTAssertEqual(entries.map(\.sessionID.uuidString), entries.map(\.sessionID.uuidString).sorted())
        XCTAssertEqual(entries.first?.sessionID.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(entries.last?.sessionID.uuidString, "00000000-0000-0000-0000-000000000010")
        XCTAssertEqual(board.recordedSessionCount, 12)
        var restored = try SiegeLeaderboard(data: board.encoded())
        XCTAssertFalse(try restored.record(try XCTUnwrap(first)))
        XCTAssertEqual(restored.recordedSessionCount, 12)
    }

    func testRanksActualPerformanceByDescendingScore() throws {
        let lowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let lower = try victory(id: lowID, braceBeforeExtraction: true)
        let higher = try victory(id: highID)
        XCTAssertLessThan(try XCTUnwrap(lower.score), try XCTUnwrap(higher.score))
        var board = SiegeLeaderboard()
        try board.record(lower)
        try board.record(higher)
        let ranked = board.entries(seed: 31, difficulty: .standard)
        XCTAssertEqual(ranked.map(\.sessionID), [highID, lowID])
        XCTAssertEqual(ranked[0].score - ranked[1].score, 10)
    }

    func testExactSeedAndDifficultyBoardsStaySeparate() throws {
        var board = SiegeLeaderboard()
        try board.record(victory(seed: 31))
        try board.record(victory(seed: 32))
        try board.record(victory(seed: 31, difficulty: .hardened))
        XCTAssertEqual(board.entries(seed: 31, difficulty: .standard).count, 1)
        XCTAssertEqual(board.entries(seed: 32, difficulty: .standard).count, 1)
        XCTAssertEqual(board.entries(seed: 31, difficulty: .hardened).count, 1)
        XCTAssertTrue(board.entries(seed: 32, difficulty: .hardened).isEmpty)
    }

    func testMaximumSeedIsPreservedWithoutFloatingPointConversion() throws {
        var board = SiegeLeaderboard()
        try board.record(victory(seed: UInt64.max))
        let restored = try SiegeLeaderboard(data: board.encoded())
        XCTAssertEqual(restored.entries(seed: UInt64.max, difficulty: .standard).first?.seed, UInt64.max)
        XCTAssertTrue(restored.entries(seed: UInt64.max - 1, difficulty: .standard).isEmpty)
    }

    func testClearExplicitlyResetsRankingsAndSessionLedger() throws {
        let mission = try victory()
        var board = SiegeLeaderboard()
        try board.record(mission)
        board.clear()
        XCTAssertTrue(board.isEmpty)
        XCTAssertEqual(board.recordedSessionCount, 0)
        XCTAssertTrue(try board.record(mission))
    }

    func testRejectsUnknownVersionModeAndMalformedJSON() throws {
        let valid = try object(SiegeLeaderboard())
        for (key, value) in [("version", 2 as Any), ("version", -1 as Any),
                             ("mode", "training" as Any), ("version", "1" as Any)] {
            var invalid = valid
            invalid[key] = value
            XCTAssertThrowsError(try SiegeLeaderboard(data: data(invalid)))
        }
        XCTAssertThrowsError(try SiegeLeaderboard(data: Data("{invalid".utf8)))
        XCTAssertThrowsError(try SiegeLeaderboard(data: Data("{}".utf8)))
    }

    func testRejectsScoreAndReceiptMetadataDisagreement() throws {
        var board = SiegeLeaderboard()
        try board.record(victory())
        let valid = try object(board)
        let rows = try XCTUnwrap(valid["results"] as? [[String: Any]])
        for (key, value) in [("score", -1 as Any), ("score", 999_999 as Any),
                             ("turn", 999 as Any), ("seed", 32 as Any),
                             ("difficulty", "hardened" as Any),
                             ("sessionID", UUID().uuidString as Any)] {
            var invalid = valid
            var altered = rows
            altered[0][key] = value
            invalid["results"] = altered
            XCTAssertThrowsError(try SiegeLeaderboard(data: data(invalid)), "Accepted corrupted \(key)")
        }
    }

    func testReceiptMustReplayToVictoryRatherThanTrustingCachedScore() throws {
        var board = SiegeLeaderboard()
        try board.record(victory())
        let valid = try object(board)
        let rows = try XCTUnwrap(valid["results"] as? [[String: Any]])
        let receipt = try XCTUnwrap(rows[0]["receipt"] as? [String: Any])
        let commands = try XCTUnwrap(receipt["commands"] as? [[String: Any]])
        let finalCommand = try XCTUnwrap(commands.last)
        for transcript in [[[String: Any]](), Array(commands.dropLast()), commands + [finalCommand]] {
            var alteredReceipt = receipt
            alteredReceipt["commands"] = transcript
            var alteredRows = rows
            alteredRows[0]["receipt"] = alteredReceipt
            var invalid = valid
            invalid["results"] = alteredRows
            XCTAssertThrowsError(try SiegeLeaderboard(data: data(invalid)))
        }
    }

    func testRejectsDuplicateIDsRowsAndOrphanReceipts() throws {
        var board = SiegeLeaderboard()
        try board.record(victory())
        let valid = try object(board)
        let ids = try XCTUnwrap(valid["recordedSessionIDs"] as? [String])
        let rows = try XCTUnwrap(valid["results"] as? [[String: Any]])
        var duplicateID = valid
        duplicateID["recordedSessionIDs"] = ids + ids
        XCTAssertThrowsError(try SiegeLeaderboard(data: data(duplicateID)))
        var duplicateRow = valid
        duplicateRow["results"] = rows + rows
        XCTAssertThrowsError(try SiegeLeaderboard(data: data(duplicateRow)))
        var orphan = valid
        orphan["recordedSessionIDs"] = [String]()
        XCTAssertThrowsError(try SiegeLeaderboard(data: data(orphan)))
        var emptyResults = valid
        emptyResults["results"] = [[String: Any]]()
        XCTAssertThrowsError(try SiegeLeaderboard(data: data(emptyResults)))
        var zeroLedgerID = valid
        zeroLedgerID["recordedSessionIDs"] = ids + ["00000000-0000-0000-0000-000000000000"]
        XCTAssertThrowsError(try SiegeLeaderboard(data: data(zeroLedgerID)))
    }

    func testRejectsOversizedLedgerAndData() throws {
        var board = SiegeLeaderboard()
        try board.record(victory())
        var invalid = try object(board)
        invalid["recordedSessionIDs"] = (0...SiegeLeaderboard.maximumRecordedSessions).map { _ in UUID().uuidString }
        XCTAssertThrowsError(try SiegeLeaderboard(data: data(invalid)))
        let oversized = Data(repeating: 32, count: SiegeLeaderboard.maximumArchiveBytes + 1)
        XCTAssertThrowsError(try SiegeLeaderboard(data: oversized)) {
            XCTAssertEqual($0 as? SiegeLeaderboardError, .capacityReached)
        }
    }

    func testRejectsOverfullBoardWithOtherwiseValidUniqueReceipts() throws {
        var rows: [[String: Any]] = []
        var ids: [String] = []
        for _ in 0...SiegeLeaderboard.entriesPerBoard {
            let mission = try victory()
            var single = SiegeLeaderboard()
            try single.record(mission)
            rows.append(contentsOf: try XCTUnwrap(try object(single)["results"] as? [[String: Any]]))
            ids.append(mission.sessionID.uuidString)
        }
        var invalid = try object(SiegeLeaderboard())
        invalid["results"] = rows
        invalid["recordedSessionIDs"] = ids
        XCTAssertThrowsError(try SiegeLeaderboard(data: data(invalid)))
    }

    func testFullLedgerFailsAtomicallyWithoutEvictingDuplicateProtection() throws {
        let mission = try victory()
        var board = SiegeLeaderboard()
        try board.record(mission)
        var full = try object(board)
        var ids = [mission.sessionID.uuidString]
        ids.append(contentsOf: (1..<SiegeLeaderboard.maximumRecordedSessions).map { _ in UUID().uuidString })
        full["recordedSessionIDs"] = ids
        var restored = try SiegeLeaderboard(data: data(full))
        let before = try restored.encoded()
        XCTAssertFalse(try restored.record(mission))
        XCTAssertThrowsError(try restored.record(victory())) {
            XCTAssertEqual($0 as? SiegeLeaderboardError, .capacityReached)
        }
        XCTAssertEqual(before, try restored.encoded())
        XCTAssertEqual(restored.recordedSessionCount, SiegeLeaderboard.maximumRecordedSessions)
    }
}
