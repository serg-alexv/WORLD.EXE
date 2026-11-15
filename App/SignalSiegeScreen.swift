import SwiftUI
import WorldCore

/// Local-only leaderboard; no server, no global ranking claims.
@MainActor final class SiegeStore: ObservableObject {
    @Published private(set) var game = SiegeGame()
    @Published private(set) var ranks = SiegeLeaderboard()
    @Published var message = "Approach the hostile probe. Cover reduces incoming damage."
    private let storage: UserDefaults?
    private let key = "worldexe.siege.ranks.v1"
    init(persist: Bool = true) {
        storage = persist ? .standard : nil
        if let data = storage?.data(forKey: key),
           let value = try? JSONDecoder().decode(SiegeLeaderboard.self, from: data),
           value.entries.count <= 10, value.entries.allSatisfy({ $0.score > 0 && $0.turns > 0 }) {
            ranks = value
        }
    }
    func act(_ action: SiegeAction) {
        do {
            try game.act(action)
            message = game.won ? "VICTORY. Mission recorded in local rankings." :
                game.finished ? "Squad lost. Replay to retry." :
                "Turn \(game.turn) · HP \(game.playerHP) · Probe \(game.enemyHP) · AP \(game.ap)"
            if game.won { ranks.submit(game); save() }
        } catch { message = "Action unavailable: \(error)" }
    }
    func replay() { game = SiegeGame(); message = "New encounter. Advance using adjacent tiles." }
    func clear() { ranks.clear(); save() }
    private func save() { if let data = try? JSONEncoder().encode(ranks) { storage?.set(data, forKey: key) } }
}

struct SignalSiegeScreen: View {
    @ObservedObject var brain: OnDeviceBrain
    @StateObject private var store = SiegeStore(persist: !ProcessInfo.processInfo.arguments.contains("-ui-testing"))
    @State private var showRanks = false
    @State private var npcText = "KIRA / Salvage officer: Secure the sector. I'll cover the exit."
    @State private var requesting = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("SIGNAL SIEGE / TACTICAL OPS").font(.headline.monospaced()).foregroundStyle(Palette.teal)
                Text("SIMULATION • turn-based action points • cover • hostile probe")
                    .font(.caption).foregroundStyle(Palette.amber)
                HStack {
                    Text("HP \(store.game.playerHP)/5")
                    Spacer()
                    Text("AP \(store.game.ap)/2")
                    Spacer()
                    Text("TURN \(store.game.turn)")
                }.font(.caption.monospaced())
                VStack(spacing: 3) {
                    ForEach(0..<SiegeGame.height, id: \.self) { y in
                        HStack(spacing: 3) {
                            ForEach(0..<SiegeGame.width, id: \.self) { x in
                                let p = SiegePoint(x,y)
                                Button {
                                    if p == store.game.enemy { store.act(.fire) }
                                    else { store.act(.move(p)) }
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(SiegeGame.cover.contains(p) ? Color.gray.opacity(0.7) : Palette.panel)
                                        if p == store.game.player { Image(systemName: "person.fill").foregroundStyle(Palette.teal) }
                                        else if p == store.game.enemy { Image(systemName: "scope").foregroundStyle(.red) }
                                        else if SiegeGame.cover.contains(p) { Image(systemName: "shield.fill").foregroundStyle(.white) }
                                    }.frame(height: 38)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("siege.tile.\(x).\(y)")
                                .accessibilityLabel("Tile \(x), \(y)")
                            }
                        }
                    }
                }
                Text(store.message).font(.caption).accessibilityIdentifier("siege.status")
                HStack {
                    Button("Fire") { store.act(.fire) }.accessibilityIdentifier("siege.fire")
                    Button("Brace") { store.act(.brace) }.accessibilityIdentifier("siege.brace")
                    Button("End Turn") { store.act(.endTurn) }.accessibilityIdentifier("siege.endTurn")
                }.buttonStyle(.borderedProminent).disabled(store.game.finished)
                HStack {
                    Button("Replay") { store.replay() }.accessibilityIdentifier("siege.replay")
                    Button("Local leaderboard") { showRanks = true }.accessibilityIdentifier("siege.leaderboard")
                }.buttonStyle(.bordered)
                Divider()
                Text("QWEN NPC / KIRA").font(.caption.bold()).foregroundStyle(Palette.teal)
                Text(npcText).font(.callout).accessibilityIdentifier("siege.npc.response")
                Button(brain.isLoaded ? "Ask Kira (on-device GGUF)" : "Kira: scripted dialogue") {
                    guard brain.isLoaded else {
                        npcText = store.game.playerInCover ?
                            "KIRA: You're behind cover. Hold position and watch the probe." :
                            "KIRA: Move behind a barrier before ending the turn."
                        return
                    }
                    requesting = true
                    Task {
                        await brain.respond(to: """
                        You are Kira, a fictional orbital salvage squad NPC. Speak in one short sentence.
                        This is a game, not a real-world sensor measurement. No commands.
                        Public state: turn \(store.game.turn), squad HP \(store.game.playerHP),
                        probe HP \(store.game.enemyHP), action points \(store.game.ap).
                        Suggest a tactical choice without inventing hidden information.
                        """)
                        npcText = "QWEN / FICTIONAL NPC: " + brain.response
                        requesting = false
                    }
                }.disabled(requesting || brain.isBusy).accessibilityIdentifier("siege.npc.ask")
                Text("Model dialogue is fictional interpretation. It cannot change game state or observations.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding()
        }
        .background(Palette.background).foregroundStyle(.white)
        .sheet(isPresented: $showRanks) {
            NavigationStack {
                List {
                    Text("LOCAL DEVICE ONLY — not global rankings").font(.caption)
                    ForEach(Array(store.ranks.entries.enumerated()), id: \.element.id) { index, entry in
                        HStack { Text("#\(index+1)"); Spacer(); Text("\(entry.score) pts · \(entry.turns) turns") }
                    }
                    Button("Clear local rankings", role: .destructive) { store.clear() }
                }
                .navigationTitle("Signal Siege · Top 10")
                .toolbar { Button("Close") { showRanks = false } }
            }
        }
    }
}
