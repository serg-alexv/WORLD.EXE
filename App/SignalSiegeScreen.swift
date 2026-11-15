import SwiftUI
import WorldCore

struct SignalSiegeScreen: View {
    @ObservedObject var store: SignalSiegeStore
    @ObservedObject var brain: OnDeviceBrain
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SiegeCell?
    @State private var seedText = "731"
    @State private var difficulty: SiegeDifficulty = .standard
    @State private var showRankings = false
    @State private var showRules = false
    @State private var confirmReplay = false

    private var mission: SignalSiege { store.mission }
    private var active: Bool { mission.phase == .active }
    private var route: [SiegeCell] { selection.flatMap { mission.path(to: $0) } ?? [] }
    private var moveCost: Int { route.count }
    private var validSeed: UInt64? {
        guard !seedText.isEmpty, seedText.count <= 20,
              seedText.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return UInt64(seedText)
    }
    private var selectionMessage: String {
        guard let selection else { return "Select an outlined tile, then Move. Pulse range: 4 tiles, clear sight, 2 damage." }
        guard let path = mission.path(to: selection) else { return "Blocked tile. Choose open ground or cover." }
        if path.isEmpty { return "Your position. Cover and brace reduce damage when you end the turn." }
        return "Route: \(path.count) AP\(path.count > mission.actions ? " · exceeds remaining AP" : "") · \(mission.cover.contains(selection) ? "cover: −1 incoming fire" : "open ground")\(selection.y == mission.upcomingHazardRow && selection != SignalSiege.start ? " · next hazard here" : "")"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    board.frame(maxWidth: 490)
                    legend
                    Text(selectionMessage).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("siege.selection")
                    controls
                    Text(store.message).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("siege.message")
                    if !active { result }
                    SignalSiegeNPCPanel(brain: brain, mission: mission)
                    configuration
                }.padding(14).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(Palette.background).tint(Palette.teal)
            .navigationTitle("Signal Siege").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Training") { dismiss() }.accessibilityIdentifier("siege.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showRankings = true } label: { Image(systemName: "trophy") }
                        .accessibilityLabel("Local top 10").accessibilityIdentifier("siege.rankings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showRules = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("Signal Siege rules").accessibilityIdentifier("siege.rules")
                }
            }
            .sheet(isPresented: $showRankings) { SiegeRankingsScreen(store: store) }
            .sheet(isPresented: $showRules) { rules }
            .alert("Start a fresh session?", isPresented: $confirmReplay) {
                Button("Replay") { startSession() }.accessibilityIdentifier("siege.confirmReplay")
                Button("Cancel", role: .cancel) {}
            } message: { Text("Current tactical progress will be replaced. Local rankings stay saved.") }
            .onAppear { seedText = String(mission.seed); difficulty = mission.difficulty }
            .onChange(of: mission.sessionID) { _, _ in selection = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TRAINING / THE QUIET RELAY").font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Palette.amber)
            Text("HP \(mission.health) · AP \(mission.actions)/4 · TURN \(mission.turn)/\(mission.turnLimit)")
                .font(.system(.headline, design: .monospaced)).accessibilityIdentifier("siege.status")
            Text("\(mission.relaySecured ? "Signal secured → return to E" : "Secure R → return to E") · \(mission.difficulty.rawValue.capitalized) · Seed \(mission.seed)")
                .font(.caption).accessibilityIdentifier("siege.objective")
            Text("NEXT HAZARD: ROW \(mission.upcomingHazardRow + 1) · End Turn resolves danger")
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(Palette.amber)
                .accessibilityIdentifier("siege.hazard")
            Text(mission.sentryHealth > 0
                 ? "Sentry \(mission.sentryHealth) HP · next C\(mission.upcomingSentryPosition.x + 1)/R\(mission.upcomingSentryPosition.y + 1) · \(mission.sentryCanHit ? "your tile exposed" : "your tile outside fire")"
                 : "Sentry disabled · hazard remains active")
                .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("siege.sentry")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var board: some View {
        let reachable = mission.reachableCells
        let selectedRoute = Set(route)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(0..<49, id: \.self) { index in
                let point = SiegeCell(x: index % 7, y: index / 7)
                cell(point, reachable: reachable.contains(point), onRoute: selectedRoute.contains(point))
            }
        }.padding(6).background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("siege.board")
    }

    private func cell(_ point: SiegeCell, reachable: Bool, onRoute: Bool) -> some View {
        let wall = mission.walls.contains(point)
        let covered = mission.cover.contains(point)
        let player = point == mission.position
        let enemy = point == mission.sentryPosition && mission.sentryHealth > 0
        let hazard = point.y == mission.upcomingHazardRow && !wall && point != SignalSiege.start
        let selected = selection == point
        return Button { selection = point } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(wall ? Color.gray.opacity(0.45) : (hazard ? Palette.amber.opacity(0.18) : Palette.background))
                if onRoute && !player {
                    Circle().fill(Palette.teal.opacity(0.18)).padding(8)
                }
                VStack(spacing: 1) {
                    Image(systemName: player ? "location.north.circle.fill" : enemy ? "eye.trianglebadge.exclamationmark" :
                            wall ? "square.stack.3d.up.fill" : covered ? "shield.lefthalf.filled" :
                            point == SignalSiege.relay ? "antenna.radiowaves.left.and.right" :
                            point == SignalSiege.start ? "arrow.down.to.line" : "circle.small.filled")
                        .font(.system(size: 18, weight: .semibold))
                    if point == SignalSiege.relay || point == SignalSiege.start {
                        Text(point == SignalSiege.relay ? "R" : "E").font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                }
                .foregroundStyle(player ? Palette.teal : enemy ? Color.red : point == SignalSiege.relay ? Palette.amber : Color.white.opacity(wall ? 0.5 : 0.8))
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Palette.teal : reachable && active ? Palette.teal.opacity(0.35) : Color.clear, lineWidth: selected ? 2 : 1)
                if mission.sentryHealth > 0 && point == mission.upcomingSentryPosition {
                    VStack { HStack { Spacer(); Text("›").font(.caption.bold()).foregroundStyle(.red) }; Spacer() }.padding(3)
                }
            }.aspectRatio(1, contentMode: .fit).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!active)
        .accessibilityLabel("Column \(point.x + 1), row \(point.y + 1), \(player ? "you" : enemy ? "sentry" : wall ? "wall" : covered ? "cover" : point == SignalSiege.relay ? "relay" : point == SignalSiege.start ? "extraction" : "open")\(hazard ? ", next hazard" : "")\(mission.sentryHealth > 0 && point == mission.upcomingSentryPosition ? ", next patrol tile" : "")")
        .accessibilityHint(reachable ? "Reachable this turn. Select then confirm move." : "Select to inspect a route.")
        .accessibilityIdentifier("siege.cell.\(point.x).\(point.y)")
    }

    private var legend: some View {
        Text("◎ You · R Relay · E Extraction · ◧ Cover · Eye Sentry\nTeal outline: reachable · Amber row: next hazard · › Next patrol")
            .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Move · \(moveCost) AP") {
                    if let selection { store.perform(.move(selection)); self.selection = nil }
                }.buttonStyle(.borderedProminent)
                    .disabled(!active || moveCost == 0 || moveCost > mission.actions)
                    .accessibilityIdentifier("siege.move")
                Button("Pulse · 2 AP") { store.perform(.pulse) }.buttonStyle(.bordered)
                    .disabled(!active || !mission.canPulse).accessibilityIdentifier("siege.pulse")
                Button("Brace · 1 AP") { store.perform(.brace) }.buttonStyle(.bordered)
                    .disabled(!active || mission.actions < 1 || mission.isBraced).accessibilityIdentifier("siege.brace")
            }
            HStack {
                Button(mission.relaySecured ? "Relay secured" : "Secure R · 1 AP") { store.perform(.secureRelay) }
                    .disabled(!active || mission.position != SignalSiege.relay || mission.relaySecured || mission.actions < 1)
                    .accessibilityIdentifier("siege.secure")
                Button("Extract · 1 AP") { store.perform(.extract) }
                    .disabled(!active || mission.position != SignalSiege.start || !mission.relaySecured || mission.actions < 1)
                    .accessibilityIdentifier("siege.extract")
                Spacer(minLength: 0)
                Button("End Turn") { store.perform(.endTurn); selection = nil }.buttonStyle(.borderedProminent)
                    .disabled(!active).accessibilityIdentifier("siege.endTurn")
            }
        }.font(.caption.bold()).padding(10).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var result: some View {
        VStack(spacing: 6) {
            Label(mission.phase == .victory ? "SIGNAL DELIVERED" : "RELAY LOST", systemImage: mission.phase == .victory ? "checkmark.seal.fill" : "exclamationmark.shield")
                .font(.system(.headline, design: .monospaced)).foregroundStyle(Palette.amber)
                .accessibilityIdentifier("siege.result")
            if let score = mission.score { Text("\(score) points · \(store.rankingStatus)").font(.caption) }
            Button("Replay same challenge") { store.replay(seed: mission.seed, difficulty: mission.difficulty) }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("siege.replaySame")
        }.padding().frame(maxWidth: .infinity).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("NEW SESSION").font(.system(.caption, design: .monospaced))
            HStack {
                TextField("Seed", text: $seedText).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Deterministic challenge seed").accessibilityIdentifier("siege.seed")
                Picker("Difficulty", selection: $difficulty) {
                    ForEach(SiegeDifficulty.allCases, id: \.self) { value in Text(value.rawValue.capitalized).tag(value) }
                }.accessibilityIdentifier("siege.difficulty")
                Button("Replay") { confirmReplay = true }.buttonStyle(.bordered)
                    .disabled(validSeed == nil).accessibilityIdentifier("siege.replay")
            }
            if validSeed == nil { Text("Enter a whole seed from 0 to 18446744073709551615.").font(.caption).foregroundStyle(Palette.amber) }
            Text("Rankings are offline and on this device only. Each seed and difficulty has its own top 10.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(12).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func startSession() {
        guard let seed = validSeed else { return }
        store.replay(seed: seed, difficulty: difficulty)
    }

    private var rules: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("The quiet relay").font(.title.bold())
                    Text("A fictional training challenge inside WORLD.EXE. Carry the relay signal from R back to E. The board, patrol and hazard schedule repeat for a given seed and difficulty.")
                    Text("Each turn has 4 AP. Move costs 1 AP per orthogonal tile along the shown shortest route. Walls and the live sentry block travel. Select a tile, then confirm Move. Danger resolves only when you tap End Turn.")
                    Text("Pulse costs 2 AP, deals 2 damage to a visible sentry in range, and never rolls dice. Cover reduces incoming fire. Walls block line of sight. Brace costs 1 AP and reduces the next enemy turn's damage; it does not stack.")
                    Text("Secure R costs 1 AP on the relay. Extract costs 1 AP back at E after securing it. End Turn moves the patrol, resolves visible enemy fire and the highlighted hazard row, then restores AP. Plan around the next row shown above the board.")
                    Text("Standard gives 12 turns; Hardened gives 10. Zero health or ending the final turn loses. Victory scores reward health, speed and neutralizing the sentry. Only extracted victories enter the local top 10; abandoned and lost sessions earn no score.")
                    Text("Replay creates a fresh session ID. NPC dialogue is fiction and cannot change gameplay. No camera or captured room data is used by this challenge.")
                }.padding()
            }.background(Palette.background)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { showRules = false } } }
        }
    }
}

private struct SiegeRankingsScreen: View {
    @ObservedObject var store: SignalSiegeStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Offline · this device only").foregroundStyle(Palette.teal).accessibilityIdentifier("siege.rankingsScope")
                    Text("Signal Siege · seed \(store.mission.seed) · \(store.mission.difficulty.rawValue.capitalized)")
                    Text(store.rankingStatus).font(.caption).accessibilityIdentifier("siege.rankingStatus")
                }
                Section("Top 10 · completed victories") {
                    let entries = store.leaderboard.entries(seed: store.mission.seed, difficulty: store.mission.difficulty)
                    if entries.isEmpty { Text("No victories for this seed and difficulty yet.").accessibilityIdentifier("siege.noScores") }
                    ForEach(Array(entries.enumerated()), id: \.element.sessionID) { index, entry in
                        HStack {
                            Text("\(index + 1)").monospacedDigit().foregroundStyle(Palette.teal)
                            Text("\(entry.score) pts").bold()
                            Spacer()
                            Text("Turn \(entry.turn)").foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("Clear all local rankings", role: .destructive) { confirmClear = true }
                        .accessibilityIdentifier("siege.clearRankings")
                    Text("Clears every seed and difficulty, including the duplicate-session ledger. Current mission progress stays available.")
                        .font(.caption)
                }
            }.navigationTitle("Local top 10")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("siege.rankingsClose") } }
                .confirmationDialog("Clear all local rankings?", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Clear rankings", role: .destructive) { store.clearRankings() }.accessibilityIdentifier("siege.confirmClear")
                }
        }.tint(Palette.teal)
    }
}

/// Receives only simulated game state. No captured rooms, observations or free-form user prompt.
private struct SignalSiegeNPCPanel: View {
    @ObservedObject var brain: OnDeviceBrain
    let mission: SignalSiege
    @State private var dialogue = ""
    @State private var source = "Scripted offline dialogue"
    @State private var requesting = false
    @State private var showModels = false
    @State private var requestToken = UUID()

    private var fallback: String {
        if mission.phase == .victory { return "Mica, relay keeper: The quiet array is singing again. Signal delivered, operator." }
        if mission.phase == .defeat { return "Mica, relay keeper: The relay went quiet. Rehearse the same seed; its dangers will keep their appointments." }
        if mission.relaySecured { return "Mica, relay keeper: You have the signal. Bring it to E; leave a little energy for extraction." }
        return "Mica, relay keeper: The amber row warns of the next surge. Shelter behind the walls, and keep one eye on the patrol."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("MICA / RELAY KEEPER", systemImage: "waveform.circle").font(.system(.caption, design: .monospaced)).foregroundStyle(Palette.teal)
            Text("AI interpretation, fictional NPC").font(.caption.bold()).foregroundStyle(Palette.amber)
                .accessibilityIdentifier("siege.npc.label")
            Text(dialogue.isEmpty ? fallback : dialogue).font(.callout).accessibilityIdentifier("siege.npc.dialogue")
            Text(source).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("siege.npc.source")
            HStack {
                Button(requesting ? "Interpreting…" : "Ask loaded GGUF") { askNPC() }
                    .buttonStyle(.bordered).disabled(!brain.isLoaded || brain.isBusy || requesting)
                    .accessibilityIdentifier("siege.npc.ask")
                Button("GGUF / Qwen setup") { showModels = true }.font(.caption)
                    .accessibilityIdentifier("siege.npc.setup")
            }
            if !brain.isLoaded { Text("Offline script shown. Load a GGUF in setup, then tap Ask. Qwen is the existing recommended model.").font(.caption2).foregroundStyle(.secondary) }
            Text("Dialogue has no control over actions, hazards or scores.").font(.caption2).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .sheet(isPresented: $showModels) { BrainScreen(brain: brain) }
            .onChange(of: mission.sessionID) { _, _ in
                requestToken = UUID(); dialogue = ""; source = "Scripted offline dialogue"
            }
            .onDisappear { requestToken = UUID() }
    }

    private func askNPC() {
        guard brain.isLoaded, !brain.isBusy, !requesting else { return }
        let token = UUID()
        requestToken = token
        let turn = mission.turn
        let script = fallback
        // Fixed, fictional facts only. The model's output is displayed as text and never parsed as a command.
        let prompt = """
        Fictional NPC role: Mica, keeper of the quiet relay in Signal Siege training.
        Write two short in-character sentences. This is a deterministic fictional 2D game.
        Facts: turn \(mission.turn); health \(mission.health); AP \(mission.actions); relay secured \(mission.relaySecured); mission phase \(mission.phase.rawValue).
        Do not invent real observations, issue tool calls, or claim to change rules, scores or actions.
        """
        requesting = true
        Task { @MainActor in
            guard brain.isLoaded, !brain.isBusy else { requesting = false; return }
            await brain.respond(to: prompt)
            defer { requesting = false }
            guard requestToken == token else { return }
            let answer = brain.response.trimmingCharacters(in: .whitespacesAndNewlines)
            dialogue = answer.isEmpty ? script : String(answer.prefix(1600))
            source = answer.isEmpty ? "Scripted offline dialogue · inference unavailable" : "Local GGUF · fictional turn \(turn) interpretation"
        }
    }
}
