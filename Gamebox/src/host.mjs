import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { Arena } from './arena.mjs';
import { ControlStore } from './control.mjs';
import { SignalPipe } from './signals.mjs';
import { fields, requireThat, validateConfig } from './contracts.mjs';
const hash=s=>createHash('sha256').update(s).digest('hex');
const secret=()=>randomBytes(32).toString('base64url');

/** Single-process local shard. External identity and production routing are NOT implemented. */
export class GameboxHost {
  constructor(config,{control=new ControlStore(),now=()=>Date.now()}={}) {
    this.config=validateConfig(config);this.control=control;this.now=now;
    this.rooms=new Map();this.sessions=new Map();this.invitations=new Map();this.signals=new SignalPipe(this.config);
    this.counts={acceptedInputs:0,rejectedInputs:0,acceptedSignals:0,expiredRooms:0};
  }
  #admit(){requireThat(this.control.snapshot().mode==='running','admissions_paused',503);}
  room(id){const r=this.rooms.get(id);requireThat(r && r.until>this.now(),'room_not_found',404);return r;}
  createRoom() {
    this.#admit();this.sweep();
    requireThat(this.rooms.size<this.config.simulation.maxRooms,'room_capacity',429);
    const id=randomUUID(),arena=new Arena(this.config);
    for(let i=0;i<this.config.simulation.botsPerRoom;i++)arena.addPlayer('bot-'+i,true);
    this.rooms.set(id,{id,arena,until:this.now()+this.config.simulation.roomTTLSeconds*1000});
    return {roomID:id,expiresAt:this.rooms.get(id).until,protocol:1};
  }
  invite(roomID) {
    this.#admit();this.sweep();const r=this.room(roomID);
    const reserved=[...this.invitations.values()].filter(v=>v.roomID===roomID).length;
    requireThat(r.arena.playerCount+reserved<this.config.simulation.maxPlayers,'room_full',409);
    const invitation=secret(),expiresAt=Math.min(r.until,this.now()+60000);
    this.invitations.set(hash(invitation),{roomID,expiresAt});return {invitation,expiresAt};
  }
  join(roomID,input) {
    this.#admit();fields(input,['invitation','consent']);
    fields(input.consent,['multiplayer','spatialSharing']);
    requireThat(input.consent.multiplayer===true && input.consent.spatialSharing===false,'explicit_multiplayer_consent_required',403);
    requireThat(typeof input.invitation==='string' && input.invitation.length<=128,'invalid_invitation',403);
    const key=hash(input.invitation),inv=this.invitations.get(key);
    requireThat(inv && inv.roomID===roomID && inv.expiresAt>this.now(),'invalid_invitation',403);
    const r=this.room(roomID),playerID=randomUUID();
    r.arena.addPlayer(playerID);this.invitations.delete(key);
    const playerToken=secret(),expiresAt=Math.min(r.until,this.now()+this.config.simulation.sessionTTLSeconds*1000);
    this.sessions.set(hash(playerToken),{roomID,playerID,expiresAt});
    return {playerID,playerToken,expiresAt,protocol:1};
  }
  session(token,roomID=null) {
    requireThat(typeof token==='string' && token.length<=128,'invalid_session',401);
    const s=this.sessions.get(hash(token));
    requireThat(s && s.expiresAt>this.now() && (!roomID || s.roomID===roomID),'invalid_session',401);
    this.room(s.roomID);return s;
  }
  input(roomID,token,input) {
    const s=this.session(token,roomID);
    requireThat(this.control.snapshot().mode!=='paused','simulation_paused',503);
    try{const result=this.room(roomID).arena.apply(s.playerID,input);this.counts.acceptedInputs++;return result;}
    catch(e){this.counts.rejectedInputs++;throw e;}
  }
  signal(roomID,input) {
    requireThat(this.control.snapshot().mode!=='paused','simulation_paused',503);
    const r=this.room(roomID),signal=this.signals.ingest(input,this.now());
    r.arena.applySignal(signal,this.now());this.counts.acceptedSignals++;return {accepted:true};
  }
  snapshot(roomID,token) { this.session(token,roomID);return this.room(roomID).arena.snapshot(); }
  revoke(token) {
    const s=this.session(token);this.rooms.get(s.roomID)?.arena.removePlayer(s.playerID);this.sessions.delete(hash(token));
    return {revoked:true};
  }
  closeRoom(id){requireThat(this.rooms.has(id),'room_not_found',404);this.rooms.delete(id);for(const [k,s] of this.sessions)if(s.roomID===id)this.sessions.delete(k);for(const [k,s] of this.invitations)if(s.roomID===id)this.invitations.delete(k);}
  sweep(){
    for(const [k,s] of this.sessions)if(s.expiresAt<=this.now()){this.rooms.get(s.roomID)?.arena.removePlayer(s.playerID);this.sessions.delete(k);}
    for(const [k,s] of this.invitations)if(s.expiresAt<=this.now())this.invitations.delete(k);
    for(const [id,r] of this.rooms)if(r.until<=this.now()){this.closeRoom(id);this.counts.expiredRooms++;}
  }
  tick(){this.sweep();if(this.control.snapshot().mode!=='paused')for(const r of this.rooms.values())r.arena.step(this.now());}
  status(){this.sweep();return {service:'WORLD.EXE Gamebox',qualification:'local-reference-only',control:this.control.snapshot(),rooms:this.rooms.size,players:this.sessions.size,pendingAdmissions:this.invitations.size,limits:this.config.simulation,metrics:{...this.counts},liveDatingProvidersConnected:false,cloudInferenceCalls:0};}
}
