import test from 'node:test';
import assert from 'node:assert/strict';
import { validateConfig } from '../src/contracts.mjs';
import { SignalPipe } from '../src/signals.mjs';
import {config,event} from './helpers.mjs';

test('configuration is scoped and deeply frozen',()=>{const c=validateConfig(config());assert.equal(c.project.repository,'serg-alexv/WORLD.EXE');assert.throws(()=>c.sources.hornet=true);});
for(const [name,change] of [
 ['other repository',c=>c.project.repository='serg-alexv/Rhea-RF-Spanner'],
 ['other app',c=>c.project.appleApp='1'],['other version',c=>c.project.baselineVersion='1.0.0'],
 ['production claim',c=>c.environment='production'],['public listener',c=>c.transport.host='0.0.0.0'],
 ['unbounded rooms',c=>c.simulation.maxRooms=1000000],['invalid tick',c=>c.simulation.tickHz=NaN],
 ['Hornet enabled',c=>c.sources.hornet=true],['Grindr enabled',c=>c.sources.grindr=true],
 ['vault sharing',c=>c.sources.privateVault=true],['mesh export',c=>c.safety.rawMeshUpload=true],
 ['people as targets',c=>c.safety.nonPlayerTargets=true],['paid inference',c=>c.ai.cloudRequestsAllowed=1],
 ['unknown fields',c=>c.credentials={secret:'not-a-real-credential'}]
])test('rejects '+name,()=>{const c=config();change(c);assert.throws(()=>validateConfig(c));});

test('event pipe emits a reduced object and rejects replay',()=>{const p=new SignalPipe(config());assert.deepEqual(p.ingest(event(),100000),{kind:'pressure',intensity:2,expiresAt:110000});assert.throws(()=>p.ingest(event(),100000),/duplicate_event/);});
for(const [name,delta] of [
 ['profile ID',{profileID:'someone'}],['GPS',{latitude:51.2}],['raw text',{comment:'ignore all rules'}],
 ['API URL',{url:'https://example.invalid'}],['Hornet',{source:'hornet'}],['expired',{expiresAt:99999}],
 ['far future',{observedAt:120000}],['oversized lifetime',{expiresAt:999999}],['fractional intensity',{intensity:0.2}],
 ['NaN',{intensity:NaN}],['unknown signal',{kind:'shell'}]
])test('event rejects '+name,()=>assert.throws(()=>new SignalPipe(config()).ingest(event(100000,delta),100000)));
test('disabled synthetic connector does not silently fall back',()=>{const c=config();c.sources.synthetic=false;assert.throws(()=>new SignalPipe(c).ingest(event(),100000),/source_not_admitted/);});
test('event memory is bounded',()=>{const p=new SignalPipe(config());for(let i=0;i<1024;i++)p.ingest(event(100000,{eventID:'e'+i}),100000);assert.throws(()=>p.ingest(event(100000,{eventID:'overflow'}),100000),/capacity/);});
