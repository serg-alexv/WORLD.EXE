import SwiftUI
import WorldCore

struct HomeView: View {
    @StateObject private var game = GameStore(persist: !ProcessInfo.processInfo.arguments.contains("-ui-testing"))
    @StateObject private var room = RoomCaptureModel()
    @State private var mode = 0
    @State private var help = false
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WORLD.EXE").font(.system(.title2, design: .monospaced, weight: .bold))
                    Text("THE HOLLOW ORBIT / EXPEDITION 01")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.teal)
                }
                Spacer()
                Button { help = true } label: { Image(systemName: "questionmark.circle").font(.title2) }
                    .accessibilityLabel("Instructions").accessibilityIdentifier("instructions")
            }
            Picker("Expedition mode", selection: $mode) {
                Text("Training").tag(0)
                Text("LiDAR").tag(1)
                Text("Room scan").tag(2)
            }
            .pickerStyle(.segmented).accessibilityIdentifier("modePicker")
            if mode == 0 { TrainingScreen(game: game) }
            else if mode == 1 { LiDARView() }
            else { RoomCaptureScreen(model: room) }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
        .frame(maxWidth: 1000).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background).tint(Palette.teal)
        .sheet(isPresented: $help) { InstructionsScreen() }
    }
}

struct TrainingScreen: View {
    @ObservedObject var game: GameStore
    @State private var zoom = 1.0
    @StateObject private var tactical = TacticalNarrator()
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Label("SIMULATED TRAINING SECTOR", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.amber).accessibilityIdentifier("trainingLabel")
                Spacer()
                Text("SEED 731").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack {
                Label("\(game.mission.recovered.count)/3 relics", systemImage: "diamond.fill")
                Spacer()
                Text("TURN \(game.mission.turn)  ·  \(game.mission.actions)/6 AP")
            }.font(.system(.caption, design: .monospaced)).accessibilityIdentifier("missionStatus")
            ZStack {
                TrainingScene(game: game, zoom: zoom)
                    .accessibilityIdentifier("sectorScene")
                    .accessibilityLabel("Isometric training grid. Tap an open tile to preview a route.")
                if game.mission.phase != .active { missionCard }
            }
            .frame(minHeight: 180, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.teal.opacity(0.3)))
            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass")
                Slider(value: $zoom, in: 0.7...1.6).accessibilityLabel("Camera zoom")
                Image(systemName: "plus.magnifyingglass")
                Button("Reset camera") { zoom = 1 }.font(.caption).accessibilityIdentifier("resetCamera")
            }.font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Tactical Advisor") {
                        Task { await tactical.advise(mission: game.mission) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(tactical.isThinking || game.moving)
                    .accessibilityIdentifier("tacticalAdvisor")
                    Spacer()
                    Text(tactical.source)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.amber)
                }
                if !tactical.briefing.isEmpty {
                    Text(tactical.briefing)
                        .font(.caption)
                        .accessibilityIdentifier("tacticalBriefing")
                }
                Text(game.message).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 32).accessibilityIdentifier("missionMessage")
                HStack {
                    Button("Plot") { game.plotObjective() }
                        .buttonStyle(.bordered)
                        .disabled(game.mission.phase != .active || game.moving || game.mission.actions == 0)
                        .accessibilityLabel("Plot route to next objective")
                        .accessibilityIdentifier("plotObjective")
                    Button("Confirm Move · \(game.moveCost) AP") { game.confirmMove() }
                        .buttonStyle(.borderedProminent).disabled(!game.canMove)
                        .accessibilityIdentifier("confirmMove")
                    Spacer(minLength: 4)
                    Button("End Turn") { game.endTurn() }
                        .buttonStyle(.bordered).disabled(game.mission.phase != .active || game.moving)
                        .accessibilityIdentifier("endTurn")
                }.font(.caption.bold())
                HStack {
                    Button("Recover · 1 AP") { game.recover() }
                        .disabled(!game.onRelic || game.mission.actions == 0 || game.moving || game.mission.phase != .active)
                        .accessibilityIdentifier("recoverRelic")
                    Spacer()
                    Button("Extract · 1 AP") { game.extract() }
                        .disabled(game.mission.position != Sector.training.extraction || game.mission.recovered.count != 3
                                  || game.mission.actions == 0 || game.moving || game.mission.phase != .active)
                        .accessibilityIdentifier("extract")
                    Spacer()
                    Button("Reset") { game.reset() }.disabled(game.moving).accessibilityIdentifier("resetMission")
                }.font(.caption)
            }
            .padding(12).background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        }
    }
    private var missionCard: some View {
        VStack(spacing: 12) {
            Image(systemName: game.mission.phase == .success ? "checkmark.seal" : "diamond.circle")
                .font(.largeTitle).foregroundStyle(Palette.amber)
            Text(game.mission.phase == .success ? "SIGNALS RETURNED" : "THE SILENT ARRAY")
                .font(.system(.headline, design: .monospaced))
            Text(game.mission.phase == .success
                 ? "Three orbital relics secured. Expedition complete."
                 : "Recover three amber relics from the derelict array. Return to the teal landing pad and extract.")
                .font(.subheadline).multilineTextAlignment(.center)
            Text("Move: 1 AP / tile · Recover: 1 AP · Extract: 1 AP\nEnd Turn restores 6 AP. No turn limit.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(game.mission.phase == .success ? "Replay expedition" : "Begin expedition") {
                if game.mission.phase == .success { game.reset() }
                game.begin()
            }
            .buttonStyle(.borderedProminent).accessibilityIdentifier("beginMission")
        }
        .padding(20).frame(maxWidth: 330)
        .background(Palette.panel.opacity(0.97), in: RoundedRectangle(cornerRadius: 18))
        .padding(12)
    }
}

struct InstructionsScreen: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Expedition field guide").font(.title.bold())
                    Text("Training is a deterministic simulation. No camera, LiDAR, room measurements or internet connection are required.")
                    Text("1. Begin the expedition. The teal ring is your squad; amber crystals are recoverable relics. Tall pillars block movement.")
                    Text("2. Tap an open tile, or use Plot to select the next affordable waypoint toward a relic or extraction. Teal dots preview a route you can afford; amber dots mark a route that exceeds this turn's AP. Confirm Move travels along the route.")
                    Text("3. Each tile costs 1 AP. Recover costs 1 AP on a relic tile. End Turn restores 6 AP, so you can always continue. There are no enemies or turn deadlines in this slice.")
                    Text("4. Recover all three relics, return to the landing pad at the near edge, then Extract for 1 AP. Replay or Reset starts a fresh expedition.")
                    Text("Progress saves after every completed command. If you leave during movement, the destination is already saved. Reset affects training only.")
                    Text("Sensor modes").font(.headline).foregroundStyle(Palette.teal)
                    Text("LiDAR shows a live estimated mesh on supported hardware. Room scan uses RoomPlan to process an estimated room and offers JSON / USDZ sharing. They are separate from training and never generate mission terrain.")
                    Text("Start grants camera access only when requested. Stop or switch modes to pause sensors. Completed room geometry remains available in an orthographic view, with its original meter dimensions and transforms. Reset scan deletes that saved capture.")
                    Text("All records stay in this app's local storage unless you explicitly share an export. Unsupported or denied sensor access leaves training available.")
                }.padding()
            }
            .background(Palette.background)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Close") { dismiss() }.accessibilityIdentifier("closeInstructions")
            } }
        }
    }
}
