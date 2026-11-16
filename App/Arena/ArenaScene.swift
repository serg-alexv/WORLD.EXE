import SwiftUI
import SceneKit
import ARKit
import WorldCore

/// Procedural synthetic board; physical mesh is local-only depth occlusion, never a network payload.
final class ArenaGraph {
    let scene=SCNScene()
    let board=SCNNode()
    private var actorNodes:[String:SCNNode]=[:]
    init(camera:Bool) {
        scene.rootNode.addChildNode(board)
        let floor=SCNNode(geometry:SCNBox(width:10,height:0.06,length:10,chamferRadius:0.08))
        floor.position.y = -0.05;floor.geometry?.firstMaterial?.diffuse.contents=UIColor(red:0.04,green:0.09,blue:0.13,alpha:1);board.addChildNode(floor)
        let cover=SCNNode(geometry:SCNBox(width:1,height:1.2,length:3,chamferRadius:0.05))
        cover.position.y=0.6;cover.geometry?.firstMaterial?.diffuse.contents=UIColor.systemGray;board.addChildNode(cover)
        for i in -5...5 {
            for axis in 0...1 {
                let line=SCNNode(geometry:SCNBox(width:axis==0 ? 0.015:10,height:0.01,length:axis==0 ? 10:0.015,chamferRadius:0))
                line.position=SCNVector3(axis==0 ? Float(i):0,0.005,axis==1 ? Float(i):0)
                line.geometry?.firstMaterial?.diffuse.contents=UIColor.systemTeal.withAlphaComponent(0.25);board.addChildNode(line)
            }
        }
        let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=550;scene.rootNode.addChildNode(ambient)
        let lamp=SCNNode();lamp.light=SCNLight();lamp.light?.type = .omni;lamp.light?.intensity=1000;lamp.position=SCNVector3(-3,9,4);scene.rootNode.addChildNode(lamp)
        if camera { let c=SCNNode();c.camera=SCNCamera();c.camera?.usesOrthographicProjection=true;c.camera?.orthographicScale=7.4;c.position=SCNVector3(8,12,11);c.look(at:SCNVector3(0,0,0));scene.rootNode.addChildNode(c) }
    }
    func update(_ state:ArenaMission,selected:String) {
        guard state.valid else { return }
        for actor in state.actors {
            let node:SCNNode
            if let existing=actorNodes[actor.id] { node=existing }
            else {
                node=SCNNode(geometry:SCNCapsule(capRadius:0.24,height:0.9));node.name=actor.id
                actorNodes[actor.id]=node;board.addChildNode(node)
                let ring=SCNNode(geometry:SCNTorus(ringRadius:0.38,pipeRadius:0.025));ring.name="selection";ring.position.y = -0.4
                ring.geometry?.firstMaterial?.diffuse.contents=UIColor.white;node.addChildNode(ring)
            }
            node.position=SCNVector3(Float(actor.x),0.45,Float(actor.z));node.isHidden=actor.health<=0
            node.geometry?.firstMaterial?.diffuse.contents=actor.bot ? UIColor.systemOrange : (actor.id=="host" ? UIColor.systemTeal : UIColor.systemBlue)
            node.childNode(withName:"selection",recursively:false)?.isHidden=actor.id != selected
        }
        for id in Array(actorNodes.keys) where !state.actors.contains(where:{$0.id==id}) { actorNodes[id]?.removeFromParentNode();actorNodes.removeValue(forKey:id) }
    }
}
struct ArenaBoardView:UIViewRepresentable {
    let state:ArenaMission;let selected:String
    func makeCoordinator()->ArenaGraph { ArenaGraph(camera:true) }
    func makeUIView(context:Context)->SCNView {
        let view=SCNView();view.scene=context.coordinator.scene;view.backgroundColor = .black
        view.preferredFramesPerSecond=30;view.antialiasingMode = .multisampling2X;view.isPlaying=false;return view
    }
    func updateUIView(_ view:SCNView,context:Context){context.coordinator.update(state,selected:selected)}
}
struct ArenaARView:UIViewRepresentable {
    let state:ArenaMission;let selected:String;let onReady:(Bool)->Void
    func makeCoordinator()->Coordinator { Coordinator(onReady:onReady) }
    func makeUIView(context:Context)->ARSCNView {
        let view=ARSCNView();let c=context.coordinator;c.view=view;view.scene=c.graph.scene;view.delegate=c;view.session.delegate=c
        view.preferredFramesPerSecond=30;view.automaticallyUpdatesLighting=true
        c.graph.board.scale=SCNVector3(0.05,0.05,0.05);c.graph.board.isHidden=true
        view.addGestureRecognizer(UITapGestureRecognizer(target:c,action:#selector(Coordinator.place)))
        let cfg=ARWorldTrackingConfiguration();cfg.planeDetection=[.horizontal]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {cfg.sceneReconstruction = .mesh}
        view.session.run(cfg,options:[.resetTracking,.removeExistingAnchors]);return view
    }
    func updateUIView(_ view:ARSCNView,context:Context){context.coordinator.graph.update(state,selected:selected)}
    static func dismantleUIView(_ view:ARSCNView,coordinator:Coordinator){view.session.pause();view.session.delegate=nil;view.delegate=nil}
    final class Coordinator:NSObject,ARSCNViewDelegate,ARSessionDelegate {
        let graph=ArenaGraph(camera:false);let onReady:(Bool)->Void;weak var view:ARSCNView?
        var placed=false;var normal=false;var meshIDs=Set<UUID>();let meshLock=NSLock()
        init(onReady:@escaping(Bool)->Void){self.onReady=onReady}
        @objc func place(_ tap:UITapGestureRecognizer) {
            guard normal,let view,let q=view.raycastQuery(from:tap.location(in:view),allowing:.existingPlaneGeometry,alignment:.horizontal),let hit=view.session.raycast(q).first else{return}
            graph.board.simdTransform=hit.worldTransform;graph.board.scale=SCNVector3(0.05,0.05,0.05);graph.board.isHidden=false;placed=true;onReady(true)
        }
        func session(_ session:ARSession,cameraDidChangeTrackingState camera:ARCamera){
            let good:Bool;if case .normal=camera.trackingState{good=true}else{good=false}
            DispatchQueue.main.async{self.normal=good;self.graph.board.isHidden = !good || !self.placed;self.onReady(good && self.placed)}
        }
        func sessionWasInterrupted(_ session:ARSession){DispatchQueue.main.async{self.normal=false;self.onReady(false)}}
        func session(_ session:ARSession,didFailWithError error:Error){DispatchQueue.main.async{self.normal=false;self.onReady(false)}}
        private func mesh(_ anchor:ARMeshAnchor)->SCNGeometry? {
            let g=anchor.geometry,v=g.vertices,f=g.faces
            guard v.count>0,v.count<=80_000,v.offset>=0,v.stride>=12, v.offset+(v.count-1)*v.stride+12<=v.buffer.length,f.count<=160_000,f.indexCountPerPrimitive==3,[2,4].contains(f.bytesPerIndex) else{return nil}
            let bytes=f.count*3*f.bytesPerIndex;guard bytes<=f.buffer.length else{return nil}
            let src=SCNGeometrySource(buffer:v.buffer,vertexFormat:.float3,semantic:.vertex,vertexCount:v.count,dataOffset:v.offset,dataStride:v.stride)
            let data=Data(bytes:f.buffer.contents(),count:bytes)
            let el=SCNGeometryElement(data:data,primitiveType:.triangles,primitiveCount:f.count,bytesPerIndex:f.bytesPerIndex)
            let geometry=SCNGeometry(sources:[src],elements:[el]);let m=SCNMaterial();m.colorBufferWriteMask=[];m.writesToDepthBuffer=true;m.isDoubleSided=true;geometry.materials=[m];return geometry
        }
        func renderer(_ renderer:SCNSceneRenderer,nodeFor anchor:ARAnchor)->SCNNode?{
            guard let a=anchor as? ARMeshAnchor,let g=mesh(a) else{return nil}
            meshLock.lock();defer{meshLock.unlock()};guard meshIDs.count<48 else{return nil}
            meshIDs.insert(a.identifier);let node=SCNNode(geometry:g);node.renderingOrder = -1;return node
        }
        func renderer(_ renderer:SCNSceneRenderer,didUpdate node:SCNNode,for anchor:ARAnchor){if let a=anchor as? ARMeshAnchor {meshLock.lock();let known=meshIDs.contains(a.identifier);meshLock.unlock();if known {node.geometry=mesh(a)}}}
        func renderer(_ renderer:SCNSceneRenderer,didRemove node:SCNNode,for anchor:ARAnchor){meshLock.lock();meshIDs.remove(anchor.identifier);meshLock.unlock()}
    }
}
