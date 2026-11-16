import Foundation
import Combine
import UIKit
import Darwin
import WorldCore

@MainActor
final class ArenaSession: ObservableObject {
    enum Role { case solo, host, guest }
    @Published private(set) var state=ArenaMission()
    @Published private(set) var role: Role = .solo
    @Published private(set) var active=false
    @Published private(set) var paused=true
    @Published private(set) var status="Synthetic tabletop arena. No live social feed."
    @Published var selected="bot1"
    let peer=ContactPeer(serviceType:"world-arena")
    private var timer: Timer?
    private var admittedSession: UUID?
    private var sequence=0
    @Published private var trackingGate = ArenaTrackingGate()
    private var trackingReady: Bool { trackingGate.trackingReady }
    var needsTrackingResume: Bool { trackingGate.requiresResume }
    var playerID: String { role == .guest ? "guest" : "host" }
    var player: ArenaActor? { state.actors.first{$0.id==playerID} }
    var canAct: Bool { active && trackingGate.permitsActions(authorityPaused: paused) && !state.won && !state.lost && (player?.health ?? 0)>0 }
    init() {
        peer.onData = { [weak self] data in self?.receive(data) }
        peer.onConnection = { [weak self] connected in self?.connection(connected) }
    }
    func beginSolo() { reset(.solo); paused=false;status="Solo training · deterministic bots";startClock() }
    func host() { reset(.host);status="Waiting for an explicitly accepted teammate";peer.host();startClock() }
    func browse() { reset(.guest);status="Choose the host, enter its code, and wait for acceptance";peer.browse() }
    private func reset(_ next: Role) {
        stop(); role=next;state=ArenaMission();sequence=0;admittedSession=nil;active=true;trackingGate=ArenaTrackingGate();selected="bot1"
    }
    func stop() { timer?.invalidate();timer=nil;active=false;paused=true;peer.stop();admittedSession=nil }
    func setTracking(_ ready: Bool) {
        trackingGate.updateTracking(ready)
        if !ready && active { paused=true;status="Paused: restore tracking, then Resume";broadcast() }
    }
    func togglePause() {
        guard active,trackingReady else { return }
        if trackingGate.requiresResume {
            guard trackingGate.resume() else { return }
            if role != .guest { paused = false }
            status = paused ? "Host paused" : "Synthetic arena running"
            broadcast(); return
        }
        guard role != .guest else { return }
        paused.toggle();status=paused ? "Paused" : "Synthetic arena running";broadcast()
    }
    func input(_ kind: ArenaInput.Kind,x:Double=0,z:Double=0) {
        guard canAct else { return }; sequence+=1
        let input=ArenaInput(sequence:sequence,kind:kind,x:x,z:z,target:kind == .fire ? selected : nil)
        if role == .guest { send(ArenaPacket(session:state.session,input:input)) }
        else {
            if !state.apply(input,player:"host") { status="Action rejected: cover, boundary, ammo, or action rate" }
        }
    }
    func selectNext() {
        let ids=state.actors.filter{$0.bot && $0.health>0}.map(\.id)
        guard !ids.isEmpty else { return }
        selected=ids[(ids.firstIndex(of:selected).map{$0+1} ?? 0) % ids.count]
    }
    private func startClock() {
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in
            Task { @MainActor in
                guard let self,self.active,self.role != .guest,self.trackingGate.permitsActions(authorityPaused: self.paused) else { return }
                self.state.step();self.broadcast()
                if self.state.won { self.status="Arena clear. All three synthetic bots eliminated." }
                else if self.state.lost { self.status="Squad down. Restart to try another route." }
            }
        }
    }
    private func connection(_ connected:Bool) {
        guard active else { return }
        if role == .host {
            state.setGuest(connected);paused = !connected || trackingGate.requiresResume;status=connected ? "Two players · host-authoritative" : "Pair disconnected · paused"
            broadcast()
        } else if role == .guest {
            admittedSession=nil;paused=true;status=connected ? "Connected; waiting for authoritative state" : "Disconnected · no offline impersonation"
        }
    }
    private func receive(_ data:Data) {
        guard active,peer.connected,let packet=ArenaPacket.decode(data) else { return }
        if role == .guest,let next=packet.state {
            guard next.actors.contains(where:{$0.id=="guest"}), admittedSession == nil || admittedSession==next.session else { return }
            if admittedSession != nil && next.tick<state.tick { return }
            admittedSession=next.session;state=next;paused=packet.paused;status=trackingGate.requiresResume ? "Local tracking paused · Resume after recovery" : "Paired · authoritative synthetic state"
            sequence=max(sequence,player?.ack ?? 0)
        } else if role == .host, !paused,trackingReady,packet.session==state.session,let input=packet.input {
            // The peer cannot choose an actor identity. Every accepted input belongs to guest.
            _=state.apply(input,player:"guest")
        }
    }
    private func send(_ packet:ArenaPacket) { if let data=try? JSONEncoder().encode(packet),data.count<=16_384 { _=peer.send(data) } }
    private func broadcast() { if role == .host && peer.connected { send(ArenaPacket(state:state,paused:paused)) } }
    deinit { timer?.invalidate() }
}

enum ArenaHardware {
    static var machine: String {
        var info=utsname();uname(&info)
        let size=MemoryLayout.size(ofValue:info.machine)
        return withUnsafePointer(to:&info.machine) { ptr in
            ptr.withMemoryRebound(to:CChar.self,capacity:size) { String(cString:$0) }
        }
    }
    static var simulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    static var admitted: Bool { ArenaDevicePolicy.admits(machine:machine,osMajor:ProcessInfo.processInfo.operatingSystemVersion.majorVersion,simulator:simulator) }
}
