import Foundation
import XCTest
import WorldCore
import EvidenceCore
@testable import WorldEXE

@MainActor
final class SignalSiegeIntegrationTests: XCTestCase {
    private let missionKey = "worldexe.signal-siege.mission.v1"
    private let scoresKey = "worldexe.signal-siege.scores.v1"

    // Every command uses the same public gameplay path as the on-screen controls.
    private var winningCommands: [SiegeCommand] {
        [.move(SiegeCell(1, 1)), .endTurn,
         .move(SiegeCell(4, 1)), .brace, .endTurn,
         .pulse, .pulse, .endTurn,
         .move(SiegeCell(5, 1)), .secureRelay, .move(SiegeCell(4, 1)), .endTurn,
         .move(SiegeCell(1, 1)), .endTurn,
         .move(SiegeCell(1, 5)), .endTurn, .extract]
    }

    private func finish(_ store: SignalSiegeStore, startingAt index: Int = 0,
                        file: StaticString = #filePath, line: UInt = #line) {
        for command in winningCommands.dropFirst(index) {
            let count = store.mission.commandHistory.count
            store.perform(command)
            XCTAssertEqual(store.mission.commandHistory.count, count + 1,
                           "A legal mission command was rejected: \(command)", file: file, line: line)
        }
        XCTAssertEqual(store.mission.phase, .victory, file: file, line: line)
    }

    private func withStorage(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "org.worldexe.tests.signal-siege.\(UUID().uuidString)"
        let storage = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        try body(storage)
    }

    func testTacticalActionsAndClearOnlyJournalGameplay() {
        let log = EvidenceStore(persist: false)
        let store = SignalSiegeStore(persist: false, evidence: log)
        store.replay(seed: 31, difficulty: .standard)
        store.perform(.move(SiegeCell(1, 4)))
        store.perform(.brace)
        store.perform(.endTurn)
        store.clearRankings()

        XCTAssertEqual(log.snapshot.gameplay.count, 5)
        XCTAssertTrue(log.snapshot.gameplay.allSatisfy { $0.action.hasPrefix("signal-siege.") })
        XCTAssertTrue(log.snapshot.gameplay.allSatisfy { $0.missionID == store.mission.sessionID })
        XCTAssertEqual(log.snapshot.gameplay.last?.kind, .reset)
        XCTAssertTrue(log.snapshot.observations.isEmpty)
        XCTAssertTrue(log.snapshot.telemetry.isEmpty)
        XCTAssertTrue(log.snapshot.isValid)
    }

    func testRejectedCommandsKeepMissionAndRankingsAtomic() {
        let log = EvidenceStore(persist: false)
        let store = SignalSiegeStore(persist: false, evidence: log)
        let initial = store.mission
        for command in [SiegeCommand.extract, .move(SiegeCell(Int.max, Int.min)), .move(SiegeCell(3, 3))] {
            store.perform(command)
            XCTAssertEqual(store.mission, initial)
            XCTAssertTrue(store.leaderboard.isEmpty)
        }
        XCTAssertEqual(log.snapshot.gameplay.count, 3)
        XCTAssertTrue(log.snapshot.gameplay.allSatisfy { $0.kind == .rejectedCommand })
        XCTAssertTrue(log.snapshot.observations.isEmpty)
        XCTAssertTrue(log.snapshot.telemetry.isEmpty)
    }

    func testOnlyExtractionRecordsVictoryAndTerminalCommandsCannotDuplicateIt() {
        let store = SignalSiegeStore(persist: false)
        store.replay(seed: 31, difficulty: .standard)
        for command in winningCommands.dropLast() { store.perform(command) }
        XCTAssertEqual(store.mission.phase, .active)
        XCTAssertTrue(store.mission.relaySecured)
        XCTAssertTrue(store.leaderboard.isEmpty)
        XCTAssertNil(store.mission.score)

        store.perform(.extract)
        let completed = store.mission
        let entries = store.leaderboard.entries(seed: 31, difficulty: .standard)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.score, completed.score)
        XCTAssertEqual(entries.first?.sessionID, completed.sessionID)
        XCTAssertEqual(store.leaderboard.recordedSessionCount, 1)

        store.perform(.extract)
        store.perform(.endTurn)
        XCTAssertEqual(store.mission, completed)
        XCTAssertEqual(store.leaderboard.entries(seed: 31, difficulty: .standard), entries)
        XCTAssertEqual(store.leaderboard.recordedSessionCount, 1)
    }

    func testReplayCreatesNewSessionAndPreservesCompletedRankings() {
        let store = SignalSiegeStore(persist: false)
        store.replay(seed: 31, difficulty: .standard)
        finish(store)
        let completedID = store.mission.sessionID
        store.replay(seed: 31, difficulty: .hardened)

        XCTAssertNotEqual(store.mission.sessionID, completedID)
        XCTAssertEqual(store.mission.seed, 31)
        XCTAssertEqual(store.mission.difficulty, .hardened)
        XCTAssertEqual(store.mission.phase, .active)
        XCTAssertTrue(store.mission.commandHistory.isEmpty)
        XCTAssertNil(store.mission.score)
        XCTAssertEqual(store.leaderboard.entries(seed: 31, difficulty: .standard).count, 1)
        XCTAssertTrue(store.leaderboard.entries(seed: 31, difficulty: .hardened).isEmpty)
    }

    func testRestoringCompletedSessionNeverAddsAnotherRanking() throws {
        try withStorage { storage in
            let store = SignalSiegeStore(storage: storage)
            store.replay(seed: 31, difficulty: .standard)
            finish(store)
            let completed = store.mission
            let savedScores = try XCTUnwrap(storage.data(forKey: scoresKey))

            for _ in 0..<2 {
                let restored = SignalSiegeStore(storage: storage)
                XCTAssertEqual(restored.mission, completed)
                XCTAssertEqual(restored.leaderboard.recordedSessionCount, 1)
                XCTAssertEqual(restored.leaderboard.entries(seed: 31, difficulty: .standard).count, 1)
                XCTAssertEqual(storage.data(forKey: scoresKey), savedScores)
            }
        }
    }

    func testCorruptRankingsStayGatedUntilExplicitClearAndNewVictory() throws {
        try withStorage { storage in
            let corrupt = Data("{unsupported-archive".utf8)
            storage.set(corrupt, forKey: scoresKey)
            let store = SignalSiegeStore(storage: storage)
            store.replay(seed: 31, difficulty: .standard)
            finish(store)
            XCTAssertTrue(store.leaderboard.isEmpty)
            XCTAssertTrue(store.rankingStatus.contains("rejected"))
            XCTAssertEqual(storage.data(forKey: scoresKey), corrupt,
                           "A completed mission must not silently replace an invalid archive")

            let restored = SignalSiegeStore(storage: storage)
            XCTAssertEqual(restored.mission.phase, .victory)
            XCTAssertTrue(restored.leaderboard.isEmpty)
            XCTAssertEqual(storage.data(forKey: scoresKey), corrupt)
            restored.clearRankings()
            XCTAssertTrue(restored.leaderboard.isEmpty)
            XCTAssertNoThrow(try SiegeLeaderboard(data: XCTUnwrap(storage.data(forKey: scoresKey))))
            restored.replay(seed: 31, difficulty: .standard)
            finish(restored)
            XCTAssertEqual(restored.leaderboard.recordedSessionCount, 1)
        }
    }

    func testClearedCompletedVictoryStaysClearedAcrossRelaunches() throws {
        try withStorage { storage in
            let store = SignalSiegeStore(storage: storage)
            store.replay(seed: 31, difficulty: .standard)
            finish(store)
            let completed = store.mission
            store.clearRankings()
            XCTAssertEqual(store.mission, completed)

            for _ in 0..<2 {
                let restored = SignalSiegeStore(storage: storage)
                XCTAssertEqual(restored.mission, completed)
                XCTAssertTrue(restored.leaderboard.isEmpty)
                XCTAssertEqual(restored.leaderboard.recordedSessionCount, 0)
            }
        }
    }

    func testClearingDuringActiveMissionAllowsThatMissionToRankAfterRestore() throws {
        try withStorage { storage in
            let store = SignalSiegeStore(storage: storage)
            store.replay(seed: 31, difficulty: .standard)
            finish(store)
            store.replay(seed: 31, difficulty: .standard)
            store.perform(winningCommands[0])
            let active = store.mission
            store.clearRankings()
            XCTAssertEqual(store.mission, active)

            let restored = SignalSiegeStore(storage: storage)
            XCTAssertEqual(restored.mission, active)
            XCTAssertTrue(restored.leaderboard.isEmpty)
            finish(restored, startingAt: 1)
            XCTAssertEqual(restored.leaderboard.recordedSessionCount, 1)
            XCTAssertEqual(restored.leaderboard.entries(seed: 31, difficulty: .standard).first?.sessionID,
                           active.sessionID)
        }
    }

    func testInvalidMissionSaveDoesNotDiscardValidRankings() throws {
        try withStorage { storage in
            let store = SignalSiegeStore(storage: storage)
            store.replay(seed: 31, difficulty: .standard)
            finish(store)
            let savedScores = try XCTUnwrap(storage.data(forKey: scoresKey))
            storage.set(Data(repeating: 32, count: 128_001), forKey: missionKey)

            let restored = SignalSiegeStore(storage: storage)
            XCTAssertEqual(restored.mission.phase, .active)
            XCTAssertTrue(restored.mission.commandHistory.isEmpty)
            XCTAssertTrue(restored.message.contains("rejected"))
            XCTAssertEqual(restored.leaderboard.recordedSessionCount, 1)
            XCTAssertEqual(storage.data(forKey: scoresKey), savedScores)
        }
    }
    func testHumorTracksEventsButNeverBecomesEvidence() throws {
        let log = EvidenceStore(persist: false)
        let store = SignalSiegeStore(persist: false, evidence: log)
        XCTAssertEqual(store.voiceEvent, .deployment)
        store.perform(.move(SiegeCell(1, 4)))
        XCTAssertEqual(store.voiceEvent, .move)
        let before = store.mission
        for tone in SiegeHumor.allCases {
            _ = SiegeVoice.line(store.voiceEvent, tone: tone, variant: store.voiceVariant)
            _ = SiegeVoice.prompt(mission: store.mission, tone: tone)
        }
        XCTAssertEqual(store.mission, before)
        XCTAssertEqual(log.snapshot.gameplay.count, 1)
        XCTAssertTrue(log.snapshot.observations.isEmpty)
        XCTAssertTrue(log.snapshot.telemetry.isEmpty)
        let journal = String(decoding: try log.snapshot.encoded(), as: UTF8.self)
        XCTAssertFalse(journal.contains("КИРА"))
        XCTAssertFalse(journal.contains("Эвакуируем бюджет"))
    }

    func testRejectedCommandKeepsFactualErrorSeparateFromJoke() {
        let store = SignalSiegeStore(persist: false)
        let before = store.mission
        store.perform(.extract)
        XCTAssertEqual(store.mission, before)
        XCTAssertEqual(store.voiceEvent, .rejected)
        XCTAssertEqual(store.message, SiegeError.prerequisite.localizedDescription)
        XCTAssertNotEqual(store.message, SiegeVoice.line(.rejected, tone: .black))
    }

    func testRankingNarrativeDoesNotChangeScoreOrClearMission() {
        let store = SignalSiegeStore(persist: false)
        store.replay(seed: 31, difficulty: .standard)
        XCTAssertEqual(store.voiceEvent, .replay)
        finish(store)
        XCTAssertEqual(store.voiceEvent, .victory)
        XCTAssertEqual(store.rankingVoice, .rankingSaved)
        let before = store.mission
        let score = before.score
        _ = SiegeVoice.line(.rankingSaved, tone: .black)
        XCTAssertEqual(store.mission.score, score)
        store.clearRankings()
        XCTAssertEqual(store.mission, before)
        XCTAssertEqual(store.rankingVoice, .rankingCleared)
        XCTAssertTrue(store.leaderboard.isEmpty)
    }

}
