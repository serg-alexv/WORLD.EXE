import { createHash } from 'node:crypto';
import { fields, finite, identifier, integer, requireThat, vector } from './contracts.mjs';
const length = v => Math.hypot(...v);
const sub = (a,b) => a.map((v,i) => v-b[i]);
const dot = (a,b) => a.reduce((s,v,i) => s+v*b[i],0);
const norm = v => v.map(x => x/length(v));
const BOXES = [ { min:[-0.6,0,-2], max:[0.6,2,2] } ];

export function rayBox(origin, direction, box) {
  let near = 0, far = Infinity;
  for (let i=0;i<3;i++) {
    if (Math.abs(direction[i]) < 1e-12) { if (origin[i] < box.min[i] || origin[i] > box.max[i]) return Infinity; }
    else { const a=(box.min[i]-origin[i])/direction[i], b=(box.max[i]-origin[i])/direction[i]; near=Math.max(near,Math.min(a,b)); far=Math.min(far,Math.max(a,b)); }
    if (near > far) return Infinity;
  }
  return near;
}
function raySphere(origin, direction, center, radius=0.45) {
  const oc=sub(origin,center), b=dot(oc,direction), c=dot(oc,oc)-radius*radius, d=b*b-c;
  if (d < 0) return Infinity;
  const t=-b-Math.sqrt(d); return t >= 0 ? t : Infinity;
}

/** Server-owned deterministic, flat-floor 3D arena. No GPS, profiles, avatars or room scans. */
export class Arena {
  #actors = new Map();
  #tick = 0;
  #pressure = 0;
  #pressureUntil = 0;
  #spawnSerial = 0;
  constructor(config) { this.config=config.simulation; this.obstacles=structuredClone(BOXES); }
  get tick() { return this.#tick; }
  get playerCount() { return [...this.#actors.values()].filter(a => !a.bot).length; }
  addPlayer(id, bot=false) {
    requireThat(identifier(id) && !this.#actors.has(id), 'invalid_actor');
    requireThat(bot ? [...this.#actors.values()].filter(a=>a.bot).length < this.config.botsPerRoom : this.playerCount < this.config.maxPlayers, 'room_full', 409);
    // Unique local spawn slots, never positions supplied by clients.
    const n=this.#spawnSerial++;
    this.#actors.set(id,{ id,bot,position:[bot?5:-5,1,-6+(n%7)*2],health:100,ammo:12,seq:0,lastInput:-1,lastShot:-1000 });
    return this.snapshot();
  }
  removePlayer(id) { this.#actors.delete(id); }
  apply(id, input) {
    const a=this.#actors.get(id); requireThat(a && !a.bot, 'not_a_player',403);
    return this.#command(a,input);
  }
  #command(a,input) {
    fields(input,['seq','kind'],['vector']);
    requireThat(integer(input.seq,1,Number.MAX_SAFE_INTEGER) && input.seq > a.seq, 'replayed_input',409);
    requireThat(a.health > 0,'player_eliminated',409);
    requireThat(a.lastInput !== this.#tick,'input_rate',429);
    requireThat(['move','fire','reload'].includes(input.kind),'unknown_command');
    requireThat(input.kind === 'reload' ? !Object.hasOwn(input,'vector') : vector(input.vector) && length(input.vector) > 0 && length(input.vector) <= 1.000001,'invalid_vector');
    let position, hit=null;
    if (input.kind === 'move') {
      requireThat(input.vector[1]===0,'ground_movement_only');
      position=a.position.map((p,i)=>p+input.vector[i]*3/this.config.tickHz);
      requireThat(Math.abs(position[0])<=9 && Math.abs(position[2])<=9,'outside_arena');
      const blocked=this.obstacles.some(b=>[0,2].every(i=>position[i]>=b.min[i]-0.3 && position[i]<=b.max[i]+0.3));
      requireThat(!blocked,'collision',409);
    }
    if (input.kind === 'fire') {
      requireThat(a.ammo>0,'empty_magazine',409);
      requireThat(this.#tick-a.lastShot>=Math.ceil(this.config.tickHz*0.3),'weapon_cooldown',429);
      const direction=norm(input.vector);
      let nearest=Math.min(25,...this.obstacles.map(b=>rayBox(a.position,direction,b)));
      for (const other of this.#actors.values()) {
        // Cooperative prototype: human players cannot damage other human players.
        if (other.id===a.id || other.health<=0 || other.bot===a.bot) continue;
        const d=raySphere(a.position,direction,other.position);
        if (d < nearest) { nearest=d; hit=other; }
      }
    }
    // Commit only after all validation: rejected commands cannot partially change state.
    a.seq=input.seq; a.lastInput=this.#tick;
    if (position) a.position=position;
    if (input.kind==='fire') { a.ammo--; a.lastShot=this.#tick; if(hit) hit.health=Math.max(0,hit.health-25); }
    if (input.kind==='reload') a.ammo=12;
    return { accepted:true,tick:this.#tick,seq:a.seq,hit:hit?.id??null };
  }
  applySignal(signal, now=Date.now()) {
    requireThat(signal.expiresAt>now && integer(signal.intensity,0,3),'invalid_signal');
    if (signal.kind==='pressure') { this.#pressure=signal.intensity; this.#pressureUntil=signal.expiresAt; }
    else if(signal.kind==='supply') { for(const a of this.#actors.values()) if(!a.bot && a.health>0) a.ammo=Math.min(12,a.ammo+signal.intensity); }
    else throw new Error('invalid_signal');
  }
  step(now=Date.now()) {
    this.#tick++;
    if(now>=this.#pressureUntil)this.#pressure=0;
    if(this.#tick % Math.max(2,6-this.#pressure)!==0) return;
    for(const bot of this.#actors.values()) {
      if(!bot.bot || bot.health<=0)continue;
      const targets=[...this.#actors.values()].filter(p=>!p.bot && p.health>0).sort((a,b)=>length(sub(a.position,bot.position))-length(sub(b.position,bot.position)) || a.id.localeCompare(b.id));
      if(!targets.length)continue;
      const delta=sub(targets[0].position,bot.position); if(length(delta)<1e-9)continue;
      const direction=norm(delta), blocked=this.obstacles.some(b=>rayBox(bot.position,direction,b)<length(delta));
      let command;
      if(bot.ammo===0)command={seq:bot.seq+1,kind:'reload'};
      else if(!blocked && this.#tick-bot.lastShot>=Math.ceil(this.config.tickHz*0.3))command={seq:bot.seq+1,kind:'fire',vector:direction};
      else command={seq:bot.seq+1,kind:'move',vector:blocked?[0,0,bot.position[2]<0?-1:1]:[direction[0],0,direction[2]]};
      try {this.#command(bot,command);} catch(e) { if(!e.code)throw e; }
    }
  }
  snapshot() {
    return { protocol:1,tick:this.#tick,units:'local-metres',pressure:this.#pressure,obstacles:structuredClone(this.obstacles),
      actors:[...this.#actors.values()].sort((a,b)=>a.id.localeCompare(b.id)).map(a=>({id:a.id,bot:a.bot,position:[...a.position],health:a.health,ammo:a.ammo,ack:a.seq})) };
  }
  digest(){return createHash('sha256').update(JSON.stringify(this.snapshot())).digest('hex');}
}
