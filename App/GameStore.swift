import Foundation
import SwiftUI
import OSLog
import WorldCore

let expeditionLog = Logger(subsystem: "org.worldexe.prototype", category: "Expedition")

enum Palette {
    static let background = Color(red: 0.025, green: 0.045, blue: 0.075)
    static let panel = Color(red: 0.06, green: 0.10, blue: 0.14)
    static let teal = Color(red: 0.25, green: 0.90, blue: 0.81)
    static let amber = Color(red: 1.0, green: 0.73, blue: 0.32)
}

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var mission = Mission()
    @Published var selection: GridPoint?
    @Published var message = "Recover three signal relics, then return to the landing pad."
    @Published var moving = false
    private(set) var lastRoute: [GridPoint] = []
    private let defaults: UserDefaults?
    private let key = "worldexe.mission.v1"

    init(persist: Bool = true) {
        defaults = persist ? .standard : nil
        guard let data = defaults?.data(forKey: key) else { return }
        do {
            let saved = try JSONDecoder().decode(Mission.self, from: data)
            guard saved.isValid else { throw CocoaError(.coderReadCorrupt) }
            mission = saved
            message = "Local expedition restored."
        } catch {
            defaults?.removeObject(forKey: key)
            message = "Saved expedition could not be read. A fresh briefing is ready."
            expeditionLog.error("Mission restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    var preview: [GridPoint]? {
        guard let selection else { return nil }
        return Sector.training.path(from: mission.position, to: selection)
    }
    var moveCost: Int { max(0, (preview?.count ?? 1) - 1) }
    var canMove: Bool {
        mission.phase == .active && !moving && preview != nil && moveCost > 0 && moveCost <= mission.actions
    }
    var onRelic: Bool {
        Sector.training.relics.contains(mission.position) && !mission.recovered.contains(mission.position)
    }
    func select(_ point: GridPoint) {
        guard mission.phase == .active, !moving else { return }
        selection = point
        if let route = preview {
            let cost = route.count - 1
            message = cost == 0 ? "Squad position. Recovery and extraction each cost 1 AP."
                : "Route: \(cost) AP. \(cost <= mission.actions ? "Confirm to move." : "Choose closer or End Turn.")"
        } else { message = "Blocked tile. Select an open tile." }
    }
    func plotObjective() {
        guard mission.phase == .active, !moving, mission.actions > 0 else { return }
        let sector = Sector.training
        let goal = sector.relics.first { !mission.recovered.contains($0) } ?? sector.extraction
        guard let route = sector.path(from: mission.position, to: goal) else {
            message = "No route to the objective. Reset the training sector."
            return
        }
        select(route[min(mission.actions, route.count - 1)])
    }
    func begin() { mission.begin(); selection = nil; save() }
    func confirmMove() {
        guard canMove, let destination = selection else { return }
        do {
            var next = mission
            lastRoute = try next.move(to: destination)
            moving = true
            mission = next
            selection = nil
            message = "Squad advancing."
            save()
        } catch { report(error) }
    }
    func finishMovement() {
        guard moving else { return }
        moving = false
        message = onRelic ? "Signal relic reached. Recover for 1 AP." : "Destination reached. Select the next tile."
    }
    func recover() {
        guard !moving else { return }
        do {
            try mission.recover()
            message = "Relic secured: \(mission.recovered.count)/3. Return all signals to extraction."
            save()
        } catch { report(error) }
    }
    func extract() {
        guard !moving else { return }
        do { try mission.extract(); message = "All three signals evacuated."; save() }
        catch { report(error) }
    }
    func endTurn() {
        guard !moving else { return }
        do {
            try mission.endTurn()
            selection = nil
            message = "Turn \(mission.turn). Six AP replenished."
            save()
        } catch { report(error) }
    }
    func reset() {
        guard !moving else { return }
        mission.reset()
        selection = nil
        lastRoute = []
        message = "Training sector reset. Read the briefing to deploy."
        save()
    }
    private func save() {
        do { defaults?.set(try JSONEncoder().encode(mission), forKey: key) }
        catch { report(error) }
    }
    private func report(_ error: Error) {
        message = error.localizedDescription
        expeditionLog.error("Mission: \(error.localizedDescription, privacy: .public)")
    }
}
