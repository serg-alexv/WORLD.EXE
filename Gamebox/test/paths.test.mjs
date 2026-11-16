import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {ensurePrivateDirectory} from '../src/paths.mjs';
test('runtime state cannot be written into source or descendants',()=>{const dir=mkdtempSync(join(tmpdir(),'worldpaths-'));try{const root=join(dir,'repo');mkdirSync(root);assert.throws(()=>ensurePrivateDirectory(root,root),/inside_source/);assert.throws(()=>ensurePrivateDirectory(join(root,'state'),root),/inside_source/);assert.equal(ensurePrivateDirectory(join(dir,'ops'),root),join(dir,'ops'));}finally{rmSync(dir,{recursive:true,force:true});}});
