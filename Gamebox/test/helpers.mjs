import { readFileSync } from 'node:fs';
import { GameboxHost } from '../src/host.mjs';
export const config = () => JSON.parse(readFileSync(new URL('../config/demo.json',import.meta.url),'utf8'));
export const event = (now=100000,changes={}) => ({schemaVersion:1,eventID:'event-001',source:'synthetic',observedAt:now,expiresAt:now+10000,kind:'pressure',intensity:2,...changes});
export function running(c=config(),options={}) { const h=new GameboxHost(c,options);h.control.transition({expectedRevision:0,commandID:'start',mode:'running'});return h; }
export function join(h,id) {return h.join(id,{invitation:h.invite(id).invitation,consent:{multiplayer:true,spatialSharing:false}});}
export const aim=(from,to)=>{const v=to.map((x,i)=>x-from[i]),d=Math.hypot(...v);return v.map(x=>x/d);};
