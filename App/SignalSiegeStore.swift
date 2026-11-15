import Foundation
import Combine
import WorldCore

/// Local training state. The core engine alone accepts commands and computes scores.
@MainActor
final class SignalSiegeStore: ObservableObject {
    @Published private(set) var mission = SignalSiege()
    @Published private(set) var leaderboard = SiegeLeaderboard()
    @Published private(set) var message = "Reach the relay, secure its signal, then return to extraction."
    @Published private(set) var rankingStatus = "Victories only · top 10 on this device"
    private var rankingsNeedReset = false
    private var clearedSession: UUID?
    private let defaults: UserDefaults?
    private let evidence: EvidenceStore?
    private let missionKey = "worldexe.signal-siege.mission.v1"
    private let scoresKey = "worldexe.signal-siege.scores.v1"
    private let clearedSessionKey = "worldexe.signal-siege.cleared-session.v1"

    init(persist: Bool = true, evidence: EvidenceStore? = nil, storage: UserDefaults? = nil) {
        self.defaults = persist ? (storage ?? .standard) : nil
        self.evidence = evidence
        if let marker = defaults?.object(forKey: clearedSessionKey) {
            if let text = marker as? String, let id = UUID(uuidString: text),
               id.uuidString != "00000000-0000-0000-0000-000000000000" {
                clearedSession = id
            } else {
                rankingsNeedReset = true
                rankingStatus = "Saved ranking reset marker rejected. Clear local rankings to start a new archive."
            }
        }
        if let data = defaults?.data(forKey: scoresKey) {
            do { leaderboard = try SiegeLeaderboard(data: data) }
            catch {
                rankingsNeedReset = true
                rankingStatus = "Saved rankings rejected. Clear local rankings to start a new archive."
            }
        }
        if let data = defaults?.data(forKey: missionKey) {
            do {
                guard data.count <= 128_000 else { throw CocoaError(.coderReadCorrupt) }
                let restored = try JSONDecoder().decode(SignalSiege.self, from: data)
                guard restored.isValid else { throw CocoaError(.coderReadCorrupt) }
                mission = restored
                message = "Local Signal Siege session restored."
                recordVictory()
            } catch { message = "Saved challenge rejected. A fresh, deterministic board is ready." }
        }
    }

    func perform(_ command: SiegeCommand) {
        do {
            try mission.apply(command)
            message = mission.outcomeMessage
            evidence?.recordGame(mission: mission.sessionID, kind: .trainingCommand, action: actionName(command))
            saveMission()
            recordVictory()
        } catch {
            message = error.localizedDescription
            evidence?.recordGame(mission: mission.sessionID, kind: .rejectedCommand, action: actionName(command))
        }
    }

    func replay(seed: UInt64, difficulty: SiegeDifficulty) {
        mission = SignalSiege(seed: seed, difficulty: difficulty)
        message = "Fresh session. Same seed and difficulty give the same tactical rules."
        evidence?.recordGame(mission: mission.sessionID, kind: .replay, action: "signal-siege.replay")
        saveMission()
    }

    func clearRankings() {
        do {
            var next = leaderboard
            next.clear()
            let data = try next.encoded()
            // Preserve a completed session's cleared status across app relaunches.
            clearedSession = mission.phase == .victory ? mission.sessionID : nil
            defaults?.set(clearedSession?.uuidString, forKey: clearedSessionKey)
            defaults?.set(data, forKey: scoresKey)
            leaderboard = next
            rankingsNeedReset = false
            rankingStatus = "Local rankings cleared. Replay to earn a new entry."
            evidence?.recordGame(mission: mission.sessionID, kind: .reset, action: "signal-siege.rankings-clear")
        } catch { rankingStatus = "Could not encode local rankings." }
    }

    private func saveMission() {
        do { defaults?.set(try JSONEncoder().encode(mission), forKey: missionKey) }
        catch { message = "Challenge is playable; this session could not be saved." }
    }

    private func recordVictory() {
        guard mission.phase == .victory, mission.sessionID != clearedSession, !rankingsNeedReset else { return }
        do {
            var next = leaderboard
            guard try next.record(mission) else { return }
            let data = try next.encoded()
            leaderboard = next
            defaults?.set(data, forKey: scoresKey)
            rankingStatus = "Victory recorded on this device · seed and difficulty kept separate"
        } catch { rankingStatus = "Victory complete; rankings unavailable. Clear local rankings to reset the archive." }
    }

    private func actionName(_ command: SiegeCommand) -> String {
        switch command {
        case .move: return "signal-siege.move"
        case .pulse: return "signal-siege.pulse"
        case .brace: return "signal-siege.brace"
        case .secureRelay: return "signal-siege.secure-relay"
        case .extract: return "signal-siege.extract"
        case .endTurn: return "signal-siege.end-turn"
        }
    }
}
