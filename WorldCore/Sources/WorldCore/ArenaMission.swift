import Foundation

/// Synthetic tabletop combat only. No geographic coordinates, profiles, text or model commands.
public struct ArenaActor: Codable, Equatable, Sendable {
    public let id: String
    public let bot: Bool
    public var x: Double
    public var z: Double
    public var health: Int
    public var ammo: Int
    public var ack: Int
    public var lastTick: Int
    public init(id: String, bot: Bool, x: Double, z: Double) {
        self.id=id; self.bot=bot; self.x=x; self.z=z
        health=bot ? 50 : 100; ammo=12; ack=0; lastTick = -100
    }
}
public struct ArenaInput: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case move, fire, reload }
    public let sequence: Int
    public let kind: Kind
    public let x: Double
    public let z: Double
    public let target: String?
    public init(sequence: Int, kind: Kind, x: Double = 0, z: Double = 0, target: String? = nil) {
        self.sequence=sequence; self.kind=kind; self.x=x; self.z=z; self.target=target
    }
}
public struct ArenaMission: Codable, Equatable, Sendable {
    public private(set) var session: UUID
    public private(set) var tick: Int
    public private(set) var actors: [ArenaActor]
    public var won: Bool { actors.filter(\.bot).allSatisfy { $0.health == 0 } }
    public var lost: Bool { actors.filter { !$0.bot }.allSatisfy { $0.health == 0 } }
    public init(session: UUID = UUID()) {
        self.session=session; tick=0
        actors=[ArenaActor(id:"host",bot:false,x:-3,z:-3),
                ArenaActor(id:"bot1",bot:true,x:3,z:-3),
                ArenaActor(id:"bot2",bot:true,x:3,z:0),
                ArenaActor(id:"bot3",bot:true,x:3,z:3)]
    }
    public mutating func setGuest(_ joined: Bool) {
        actors.removeAll { $0.id == "guest" }
        if joined { actors.append(ArenaActor(id:"guest",bot:false,x:-3,z:3)) }
    }
    public var valid: Bool {
        guard session.uuidString != "00000000-0000-0000-0000-000000000000", tick >= 0, tick < 1_000_000, (4...5).contains(actors.count),
              Set(actors.map(\.id)).count == actors.count,
              Set(actors.map(\.id)).isSuperset(of:["host","bot1","bot2","bot3"]) else { return false }
        return actors.allSatisfy {
            ["host","guest","bot1","bot2","bot3"].contains($0.id) && $0.bot == $0.id.hasPrefix("bot") &&
            $0.x.isFinite && $0.z.isFinite && abs($0.x) <= 4.5 && abs($0.z) <= 4.5 &&
            (0...100).contains($0.health) && (0...12).contains($0.ammo) &&
            (0...1_000_000).contains($0.ack) && (-100...tick).contains($0.lastTick) &&
            !Self.blocked(x:$0.x,z:$0.z)
        }
    }
    public static func blocked(x: Double, z: Double) -> Bool { abs(x) < 0.7 && abs(z) < 1.7 }
    public static func clearLine(ax: Double, az: Double, bx: Double, bz: Double) -> Bool {
        // Segment vs conservative rectangular cover; no point-sampling gaps.
        var low=0.0, high=1.0
        for (o,d,mn,mx) in [(ax,bx-ax,-0.5,0.5),(az,bz-az,-1.5,1.5)] {
            if abs(d) < 1e-12 { if o < mn || o > mx { return true } }
            else { let t1=(mn-o)/d, t2=(mx-o)/d; low=max(low,min(t1,t2)); high=min(high,max(t1,t2)) }
            if low > high { return true }
        }
        return false
    }
    @discardableResult public mutating func apply(_ input: ArenaInput, player: String) -> Bool {
        guard valid, !won, !lost, ["host","guest"].contains(player),
              let index=actors.firstIndex(where:{$0.id==player}), actors[index].health>0,
              input.sequence>actors[index].ack, input.sequence<=1_000_000,
              actors[index].lastTick != tick, input.x.isFinite, input.z.isFinite else { return false }
        var actor=actors[index]
        switch input.kind {
        case .move:
            guard input.target == nil, input.x*input.x+input.z*input.z<=1.000001,
                  input.x*input.x+input.z*input.z>0 else { return false }
            let nx=actor.x+input.x*0.35, nz=actor.z+input.z*0.35
            guard abs(nx)<=4.5, abs(nz)<=4.5, !Self.blocked(x:nx,z:nz) else { return false }
            actor.x=nx; actor.z=nz
        case .fire:
            guard input.x==0, input.z==0, actor.ammo>0,
                  let target=input.target, let ti=actors.firstIndex(where:{$0.id==target && $0.bot && $0.health>0}) else { return false }
            actor.ammo-=1
            if Self.clearLine(ax:actor.x,az:actor.z,bx:actors[ti].x,bz:actors[ti].z) {
                actors[ti].health=max(0,actors[ti].health-25)
            }
        case .reload:
            guard input.target == nil, input.x==0, input.z==0 else { return false }
            actor.ammo=12
        }
        actor.ack=input.sequence; actor.lastTick=tick; actors[index]=actor
        return true
    }
    public mutating func step() {
        guard valid, !won, !lost, tick<999_999 else { return }; tick+=1
        guard tick % 12 == 0 else { return }
        for bi in actors.indices where actors[bi].bot && actors[bi].health>0 {
            let bot=actors[bi]
            guard let pi=actors.indices.filter({!actors[$0].bot && actors[$0].health>0}).min(by:{
                let a=actors[$0],b=actors[$1]
                return hypot(a.x-bot.x,a.z-bot.z)<hypot(b.x-bot.x,b.z-bot.z)
            }) else { continue }
            let target=actors[pi]
            if Self.clearLine(ax:bot.x,az:bot.z,bx:target.x,bz:target.z) {
                actors[pi].health=max(0,target.health-5)
            } else {
                let nz=max(-4.4,min(4.4,bot.z+(bot.z<=0 ? -0.3 : 0.3)))
                if !Self.blocked(x:bot.x,z:nz) { actors[bi].z=nz }
            }
        }
    }
}
public struct ArenaPacket: Codable, Sendable {
    public let version: Int
    public let session: UUID
    public let paused: Bool
    public let state: ArenaMission?
    public let input: ArenaInput?
    public init(state: ArenaMission, paused: Bool = false) { version=1;session=state.session;self.state=state;self.paused=paused;input=nil }
    public init(session: UUID,input: ArenaInput) { version=1;self.session=session;paused=false;state=nil;self.input=input }
    public static func decode(_ data: Data) -> ArenaPacket? {
        guard !data.isEmpty, data.count<=16_384, let p=try? JSONDecoder().decode(Self.self,from:data),p.version==1,
              (p.state == nil) != (p.input == nil) else { return nil }
        if let s=p.state { guard s.valid,s.session==p.session else { return nil } }
        return p
    }
}
/// Explicit known model admission. Future hardware needs qualification rather than numeric guessing.
public enum ArenaDevicePolicy {
    public static let supportedModelIdentifiers: Set<String> = ["iPhone19,2","iPhone19,3","iPhone19,7"]
    public static func admits(machine: String, osMajor: Int, simulator: Bool = false) -> Bool {
        simulator || (osMajor>=27 && supportedModelIdentifiers.contains(machine))
    }
}
