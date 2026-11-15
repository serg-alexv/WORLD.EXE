import XCTest
@testable import WorldCore

final class SiegeVoiceTests: XCTestCase {
    func testEveryEventHasBoundedNonemptyCopyInEveryTone() {
        for tone in SiegeHumor.allCases {
            for event in SiegeVoiceEvent.allCases {
                for variant in [UInt64(0), 1, 2, 3, .max] {
                    let text = SiegeVoice.line(event, tone: tone, variant: variant)
                    XCTAssertFalse(text.isEmpty)
                    XCTAssertLessThanOrEqual(text.count, 180)
                    XCTAssertLessThanOrEqual(text.utf8.count, 512)
                }
            }
        }
    }
    func testCatalogueIsDeterministicAndHasVariation() {
        for event in SiegeVoiceEvent.allCases {
            XCTAssertEqual(SiegeVoice.line(event, tone: .black, variant: 91), SiegeVoice.line(event, tone: .black, variant: 91))
            XCTAssertNotEqual(SiegeVoice.line(event, tone: .black), SiegeVoice.line(event, tone: .black, variant: 1))
        }
    }
    func testNeutralDoesNotDependOnVariant() {
        for event in SiegeVoiceEvent.allCases {
            XCTAssertEqual(SiegeVoice.line(event, tone: .off), SiegeVoice.line(event, tone: .off, variant: .max))
        }
    }
    func testUnknownStoredToneFailsToNeutral() {
        XCTAssertEqual(SiegeHumor.restored("unexpected"), .off)
        XCTAssertEqual(SiegeHumor.restored(""), .off)
        XCTAssertEqual(SiegeHumor.restored("black"), .black)
    }
    func testCopyAndPromptCannotMutateMissionOrScore() throws {
        var game = SignalSiege()
        try game.apply(.move(SiegeCell(1, 4)))
        let before = game
        let encoded = try JSONEncoder().encode(game)
        for tone in SiegeHumor.allCases {
            _ = SiegeVoice.prompt(mission: game, tone: tone)
            _ = SiegeVoice.line(.move, tone: tone)
        }
        XCTAssertEqual(game, before)
        XCTAssertEqual(try JSONDecoder().decode(SignalSiege.self, from: encoded), game)
        XCTAssertNil(game.score)
    }
    func testPromptContainsOnlyPublicFictionAndExplicitStyle() {
        let game = SignalSiege(seed: 987654321234567890)
        let prompt = SiegeVoice.prompt(mission: game, tone: .black)
        XCTAssertTrue(prompt.contains("fictional"))
        XCTAssertTrue(prompt.contains("gallows humor"))
        XCTAssertTrue(prompt.contains("NOT physical measurements"))
        XCTAssertTrue(prompt.contains("Russian"))
        XCTAssertFalse(prompt.contains(String(game.seed)))
        XCTAssertFalse(prompt.contains(game.sessionID.uuidString))
        XCTAssertLessThan(prompt.utf8.count, 2048)
    }
    func testOffPromptExplicitlyDisablesJokes() {
        let prompt = SiegeVoice.prompt(mission: SignalSiege(), tone: .off)
        XCTAssertTrue(prompt.contains("No jokes"))
        XCTAssertFalse(prompt.contains("gallows humor"))
    }
    func testToneRoundTrip() throws {
        for tone in SiegeHumor.allCases {
            XCTAssertEqual(try JSONDecoder().decode(SiegeHumor.self, from: JSONEncoder().encode(tone)), tone)
        }
    }
    func testMoveAndBraceSelectMatchingEvents() throws {
        var game = SignalSiege()
        var before = game
        try game.apply(.move(SiegeCell(1, 4)))
        XCTAssertEqual(SiegeVoice.event(before: before, after: game, command: .move(SiegeCell(1, 4))), .move)
        before = game
        try game.apply(.brace)
        XCTAssertEqual(SiegeVoice.event(before: before, after: game, command: .brace), .brace)
    }
    func testTerminalOutcomeTakesPriorityOverTurnQuip() throws {
        var game = SignalSiege()
        while game.phase == .active {
            let before = game
            try game.apply(.endTurn)
            if game.phase == .defeat {
                XCTAssertEqual(SiegeVoice.event(before: before, after: game, command: .endTurn), .defeat)
                return
            }
        }
        XCTFail("Expected bounded mission defeat")
    }
    func testRankingTextDoesNotClaimGlobalService() {
        XCTAssertTrue(SiegeVoice.line(.rankingSaved, tone: .off).contains("локальный"))
        XCTAssertTrue(SiegeVoice.line(.rankingSaved, tone: .sarcastic).contains("Галактика пока не уведомлена"))
    }
    func testRankingQuipUsesActualCurrentBoardIncludingRestoredEntries() {
        XCTAssertEqual(SiegeVoice.rankingEvent(hasEntries: true, wasCleared: false), .rankingSaved)
        XCTAssertEqual(SiegeVoice.rankingEvent(hasEntries: false, wasCleared: false), .rankingEmpty)
        XCTAssertEqual(SiegeVoice.rankingEvent(hasEntries: false, wasCleared: true), .rankingCleared)
        XCTAssertEqual(SiegeVoice.rankingEvent(hasEntries: true, wasCleared: true), .rankingSaved)
    }

}
