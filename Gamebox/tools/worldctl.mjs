#!/usr/bin/env node
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve,join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { ensurePrivateDirectory } from '../src/paths.mjs';
import { randomUUID,randomBytes } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { validateConfig } from '../src/contracts.mjs';
import { GameboxHost } from '../src/host.mjs';
import { ControlStore } from '../src/control.mjs';
import { startServer } from '../src/server.mjs';
const [command='validate',...args]=process.argv.slice(2);
const option=(name,fallback)=>{const i=args.indexOf(name);if(i<0)return fallback;if(i===args.length-1 || args[i+1].startsWith('--'))throw new Error('Missing value for '+name);return args[i+1];};
const output=value=>console.log(JSON.stringify(value,null,2));
const c=JSON.parse(readFileSync(option('--config',new URL('../config/demo.json',import.meta.url)),'utf8'));
validateConfig(c);
function running(config){const h=new GameboxHost(config);h.control.transition({expectedRevision:0,commandID:randomUUID(),mode:'running'});return h;}
function enroll(h,id){return h.join(id,{invitation:h.invite(id).invitation,consent:{multiplayer:true,spatialSharing:false}});}
try {
  if(command==='validate')output({status:'PASS',configuration:'valid',productionQualified:false,project:c.project});
  else if(command==='demo'){
    const h=running(c),id=h.createRoom().roomID,a=enroll(h,id),b=enroll(h,id),now=Date.now();
    h.signal(id,{schemaVersion:1,eventID:randomUUID(),source:'synthetic',observedAt:now,expiresAt:now+10000,kind:'pressure',intensity:2});
    h.input(id,a.playerToken,{seq:1,kind:'move',vector:[1,0,0]});
    for(let i=0;i<100;i++)h.tick();
    output({status:'PASS',evidence:'headless in-process synthetic demo, NOT an iPhone playtest',sameSnapshot:JSON.stringify(h.snapshot(id,a.playerToken))===JSON.stringify(h.snapshot(id,b.playerToken)),snapshot:h.snapshot(id,a.playerToken),metrics:h.status().metrics});
  }else if(command==='benchmark'){
    const rooms=Number(option('--rooms','32')),players=Number(option('--players','8')),ticks=Number(option('--ticks','200'));
    if(!Number.isInteger(ticks)||ticks<1||ticks>10000)throw new Error('ticks must be 1..10000');
    c.simulation.maxRooms=rooms;c.simulation.maxPlayers=players;validateConfig(c);
    const h=running(c);for(let r=0;r<rooms;r++){const id=h.createRoom().roomID;for(let p=0;p<players;p++)enroll(h,id);}
    const durations=[],start=performance.now();for(let i=0;i<ticks;i++){const t=performance.now();h.tick();durations.push(performance.now()-t);}
    durations.sort((a,b)=>a-b);output({evidence:'local in-process synthetic throughput only; excludes transport, AR, identity, storage and internet latency',node:process.version,rooms,playersPerRoom:players,simulatedPlayers:rooms*players,ticks,elapsedMs:performance.now()-start,tickP95Ms:durations[Math.min(durations.length-1,Math.floor(durations.length*0.95))],rssBytes:process.memoryUsage().rss,productionQualified:false});
  }else if(command==='capacity'){
    const mau=Number(option('--mau','1000000')),peakFraction=Number(option('--peak-fraction','0.02')),players=Number(option('--players','32')),headroom=Number(option('--headroom','0.3'));
    if(!Number.isFinite(mau)||mau<1||!Number.isFinite(peakFraction)||peakFraction<=0||peakFraction>1||!Number.isInteger(players)||players<2||players>32||!Number.isFinite(headroom)||headroom<0||headroom>2)throw new Error('Invalid sizing assumptions');
    const peakCCU=Math.ceil(mau*peakFraction),matches=Math.ceil(peakCCU/players);
    output({evidence:'scenario arithmetic, NOT measured capacity or a demand forecast',assumptions:{mau,peakFraction,playersPerMatch:players,headroom},peakCCU,concurrentMatches:matches,matchSlotsWithHeadroom:Math.ceil(matches*(1+headroom)),measuredProductionCapacity:null});
  }else if(command==='serve'){
    const dir=resolve(option('--state-dir',join(homedir(),'.worldexe-gamebox')));
    // This reference process must not persist operator state within the source checkout.
    const sourceRoot=fileURLToPath(new URL('../../',import.meta.url));
    ensurePrivateDirectory(dir,sourceRoot);let token=process.env.GAMEBOX_OPERATOR_TOKEN;
    if(!token){const file=join(dir,'operator.token');try{token=readFileSync(file,'utf8').trim();}catch(e){if(e.code!=='ENOENT')throw e;token=randomBytes(32).toString('base64url');writeFileSync(file,token+'\n',{mode:0o600,flag:'wx'});}}
    const control=new ControlStore(join(dir,'control.json'));
    try{const s=await startServer(c,{operatorToken:token,control});output({listening:s.url,mode:control.snapshot().mode,credential:'private state directory; not printed',productionQualified:false});let closing=false;const close=async()=>{if(closing)return;closing=true;await s.close();};process.once('SIGINT',close);process.once('SIGTERM',close);}catch(e){control.close();throw e;}
  }else if(['status','pause','resume','drain'].includes(command)){
    const dir=resolve(option('--state-dir',join(homedir(),'.worldexe-gamebox'))),token=process.env.GAMEBOX_OPERATOR_TOKEN||readFileSync(join(dir,'operator.token'),'utf8').trim();
    const base=`http://127.0.0.1:${c.transport.port}`;
    const get=await fetch(base+'/v1/status',{headers:{authorization:'Bearer '+token},signal:AbortSignal.timeout(5000)});if(!get.ok)throw new Error('Status request failed: '+get.status);const status=await get.json();
    if(command==='status')output(status);else{const mode={pause:'paused',resume:'running',drain:'draining'}[command];const r=await fetch(base+'/v1/control',{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify({expectedRevision:status.control.revision,commandID:randomUUID(),mode}),signal:AbortSignal.timeout(5000)});const result=await r.json();if(!r.ok)throw new Error(result.error);output(result);}
  }else throw new Error('Commands: validate | demo | benchmark | capacity | serve | status | pause | resume | drain');
}catch(e){console.error(JSON.stringify({status:'FAIL',error:e.code||e.message}));process.exitCode=1;}
