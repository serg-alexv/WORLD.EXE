import { mkdirSync,realpathSync } from 'node:fs';
import { resolve,relative,isAbsolute } from 'node:path';
import { requireThat } from './contracts.mjs';
const inside=(root,path)=>{const rel=relative(root,path);return rel==='' || (!rel.startsWith('..') && !isAbsolute(rel));};
export function ensurePrivateDirectory(directory,sourceRoot){
  const dir=resolve(directory),root=resolve(sourceRoot);
  requireThat(!inside(root,dir),'private_state_inside_source');
  mkdirSync(dir,{recursive:true,mode:0o700});
  requireThat(!inside(realpathSync(root),realpathSync(dir)),'private_state_inside_source');
  return dir;
}
