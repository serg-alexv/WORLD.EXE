import { existsSync, readFileSync, writeFileSync, renameSync, mkdirSync, openSync, closeSync, unlinkSync } from 'node:fs';
import { dirname } from 'node:path';
import { fields, identifier, integer, requireThat } from './contracts.mjs';

/** One writer. Durable controls, not durable matches. A stale lock needs operator review. */
export class ControlStore {
  #state = { schemaVersion:1, revision:0, mode:'paused', commands:[] };
  #file; #lock;
  constructor(file=null) {
    this.#file=file;
    if(!file)return; // In-memory use is only for tests and the explicitly labeled demo.
    mkdirSync(dirname(file),{recursive:true,mode:0o700});
    this.#lock=file+'.lock';
    const fd=openSync(this.#lock,'wx',0o600);closeSync(fd);
    try {
      if(existsSync(file)) {
        const s=JSON.parse(readFileSync(file,'utf8'));
        fields(s,['schemaVersion','revision','mode','commands']);
        requireThat(s.schemaVersion===1 && integer(s.revision,0,Number.MAX_SAFE_INTEGER) && ['paused','running','draining'].includes(s.mode) && Array.isArray(s.commands) && s.commands.length<=128,'corrupt_control_state');
        for(const r of s.commands){fields(r,['commandID','mode','revision']);requireThat(identifier(r.commandID) && ['paused','running','draining'].includes(r.mode) && integer(r.revision,1,s.revision),'corrupt_control_state');}
        this.#state=s;
      }else this.#persist(this.#state);
    }catch(e){this.close();throw e;}
  }
  #persist(state) {
    if(!this.#file)return;
    // Atomic same-directory replacement. No provider records, access tokens or locations.
    const tmp=this.#file+'.next';
    writeFileSync(tmp,JSON.stringify(state,null,2)+'\n',{mode:0o600,flush:true});
    renameSync(tmp,this.#file);
  }
  snapshot(){return {schemaVersion:1,revision:this.#state.revision,mode:this.#state.mode};}
  transition(input) {
    fields(input,['expectedRevision','commandID','mode']);
    requireThat(identifier(input.commandID) && integer(input.expectedRevision,0,Number.MAX_SAFE_INTEGER) && ['paused','running','draining'].includes(input.mode),'invalid_control');
    const prior=this.#state.commands.find(c=>c.commandID===input.commandID);
    if(prior){requireThat(prior.mode===input.mode && input.expectedRevision===prior.revision-1,'idempotency_conflict',409);return {...this.snapshot(),replayed:true};}
    requireThat(input.expectedRevision===this.#state.revision,'control_revision_conflict',409);
    requireThat(this.#state.revision < Number.MAX_SAFE_INTEGER,'control_revision_exhausted',409);
    const revision=this.#state.revision+1;
    const next={schemaVersion:1,revision,mode:input.mode,commands:[...this.#state.commands,{commandID:input.commandID,mode:input.mode,revision}].slice(-128)};
    this.#persist(next);this.#state=next;return {...this.snapshot(),replayed:false};
  }
  close(){if(this.#lock){unlinkSync(this.#lock);this.#lock=null;}}
}
