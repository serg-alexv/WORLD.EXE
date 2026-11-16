import SwiftUI
import ARKit
import WorldCore

struct ArenaScreen:View {
    let onExit:()->Void
    @StateObject private var game=ArenaSession()
    @StateObject private var camera=CameraAccess()
    @Environment(\.scenePhase) private var phase
    @State private var ar=false
    @State private var consent=false
    @State private var code=""
    @State private var ready=false
    var body:some View {
        VStack(spacing:10){
            HStack{Button("WORLD.EXE",action:onExit).accessibilityIdentifier("arena.close");Spacer();Text("ARENA / 0.5.0").font(.system(.caption,design:.monospaced))}.padding(.horizontal)
            if !ArenaHardware.admitted {
                Spacer();Text("iPhone 18 Pro or Pro Max required").font(.title2.bold())
                Text("This new arena requires iOS 27 and a qualified Pro device. Existing Fusion modes remain separate.").multilineTextAlignment(.center)
                Spacer()
            } else {
                Text(ArenaHardware.simulator ? "SIMULATOR · NOT PHYSICAL-DEVICE QUALIFICATION" : "SYNTHETIC TACTICAL ARENA · LOCAL-ONLY").font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.amber)
                if game.active {
                    ZStack(alignment:.bottom){
                        if ar { ArenaARView(state:game.state,selected:game.selected,onReady:{ready=$0;game.setTracking($0)}) }
                        else { ArenaBoardView(state:game.state,selected:game.selected) }
                        if ar && !ready { Text("Scan a clear tabletop slowly, then tap a detected horizontal surface. Stay stationary.").font(.caption).padding(10).background(.black.opacity(0.8)) }
                    }.frame(minHeight:200,maxHeight:.infinity).clipShape(RoundedRectangle(cornerRadius:14))
                    HStack{Text("HP \(game.player?.health ?? 0)");Text("AMMO \(game.player?.ammo ?? 0)");Spacer();Text("TICK \(game.state.tick)")}.font(.system(.caption,design:.monospaced))
                    Text(game.status).font(.caption).accessibilityIdentifier("arena.status")
                    HStack{Button("Target: \(game.selected)"){game.selectNext()}.accessibilityIdentifier("arena.target");Spacer();Button(game.paused ? "Resume":"Pause"){game.togglePause()}.disabled(game.role == .guest || (ar && !ready)).accessibilityIdentifier("arena.pause")}
                    HStack(spacing:16){
                        VStack(spacing:6){Button("↑"){game.input(.move,z:-1)}.accessibilityIdentifier("arena.north");HStack{Button("←"){game.input(.move,x:-1)};Button("↓"){game.input(.move,z:1)};Button("→"){game.input(.move,x:1)}}
                        Spacer();Button("FIRE"){game.input(.fire)}.buttonStyle(.borderedProminent).accessibilityIdentifier("arena.fire")
                        Button("Reload"){game.input(.reload)}.accessibilityIdentifier("arena.reload")
                    }.disabled(!game.canAct).buttonStyle(.bordered)
                    HStack{Button("Restart solo"){ar=false;game.beginSolo()}.accessibilityIdentifier("arena.restart");Spacer();Button(ar ? "3D board":"Place in AR"){
                        if ar {ar=false;game.setTracking(true)} else if ARWorldTrackingConfiguration.isSupported {camera.request{allowed in if allowed {game.setTracking(false);ready=false;ar=true}}}
                    }.disabled(ArenaHardware.simulator)}
                } else { Spacer();Image(systemName:"scope").font(.system(size:55)).foregroundStyle(Palette.teal);Text("Clear three bots. Use cover. Pair nearby.").font(.headline);Spacer() }
                if !game.active || game.paused {
                    VStack(spacing:8){
                        if !game.active {Button("Start solo training"){game.beginSolo()}.buttonStyle(.borderedProminent).accessibilityIdentifier("arena.start")}
                        Toggle("Share synthetic game state with one chosen teammate",isOn:$consent).font(.caption)
                        HStack{Button("Host pair"){ar=false;game.host()}.disabled(!consent);Button("Join nearby"){ar=false;game.browse()}.disabled(!consent)}
                        ArenaPairControls(peer:game.peer,code:$code)
                    }.padding(10).background(Palette.panel,in:RoundedRectangle(cornerRadius:12))
                }
                Text("Bots and terrain are fictional. AR mesh stays on this device. Each phone places its own board; shared physical alignment is not claimed. Hornet is not connected.").font(.system(size:10)).foregroundStyle(.secondary)
            }
        }.padding(12).background(Palette.background).onDisappear{game.stop()}
            .onChange(of:phase){_,value in if value != .active {game.stop();ar=false}}
            .onChange(of:consent){_,value in if !value && game.role != .solo {game.stop();ar=false}}
    }
}
private struct ArenaPairControls:View {
    @ObservedObject var peer:ContactPeer
    @Binding var code:String
    var body:some View {
        VStack(spacing:6){
            Text(peer.status).font(.caption2)
            if !peer.code.isEmpty {Text("Pair code: \(peer.code)").font(.headline.monospaced())}
            if peer.pendingName != nil {HStack{Button("Accept teammate"){peer.answer(true)};Button("Reject"){peer.answer(false)}}}
            if !peer.hosts.isEmpty {
                TextField("Six-digit pair code",text:$code).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                ForEach(peer.hosts,id:\.self){host in Button("Join \(ContactPeer.name(host))"){peer.invite(host,code:code)}}
            }
        }
    }
}
