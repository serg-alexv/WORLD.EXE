"""Freeze approved source locally; publish ONLY immutable WORLD.EXE checkpoint refs."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, re, shutil, stat, subprocess, sys, tempfile, zipfile
from pathlib import Path, PurePosixPath
from common import GateError, ORIGINS, atomic, bounded_run, canonical, digest, file_hash, file_lock, load_config, read_json, utc

MAX_BYTES=24*1024*1024
PRIVATE_PARTS={'private','privatedata','imports','exports','recordings','credentials','runtime','state','queue','jobs','candidates','receipts'}

def policy(cfg):
    path=Path(cfg['release'])/'checkpoint_policy.py'
    spec=importlib.util.spec_from_file_location('approved_checkpoint_policy',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

def safe_git(root, args, data=None, env=None):
    environment=os.environ.copy();environment.update(env or {})
    environment.update(GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='Never',SSH_ASKPASS_REQUIRE='never')
    p=subprocess.Popen(['git','-C',str(root),*args],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                       env=environment,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    try: out,err=p.communicate(input=data,timeout=45)
    except subprocess.TimeoutExpired:
        from common import kill_owned_process
        kill_owned_process(p);raise GateError('git_timeout')
    if len(out)+len(err)>2*1024*1024:raise GateError('git_output_limit')
    if p.returncode:
        raw=err.lower()
        if any(x in raw for x in [b'authentication failed',b'permission denied',b'403',b'could not read username']):
            raise GateError('authentication_blocked')
        if args[0]=='push' and (b'non-fast-forward' in raw or b'fetch first' in raw):raise GateError('remote_race')
        raise GateError('git_'+args[0]+'_failed')
    return out

def scope(cfg, label):
    found=[s for s in cfg['sources'] if s['label']==label]
    if len(found)!=1:raise GateError('unknown_workspace')
    root=Path(found[0]['path']).resolve();canonical=Path(cfg['canonical']).resolve()
    if not root.is_dir():raise GateError('workspace_offline')
    if safe_git(root,['remote','get-url','origin']).decode().strip() not in ORIGINS:raise GateError('wrong_origin')
    common=(root/safe_git(root,['rev-parse','--git-common-dir']).decode().strip()).resolve()
    if common!=canonical/'.git':raise GateError('wrong_git_common_dir')
    return root

def source_allowed(cp,name,tracked):
    parts=PurePosixPath(name).parts
    if any(x.lower() in PRIVATE_PARTS for x in parts):return False
    return cp.allowed(name,tracked)

def collect(cfg,label):
    root=scope(cfg,label);cp=policy(cfg)
    head=safe_git(root,['rev-parse','HEAD']).decode().strip()
    branch=safe_git(root,['rev-parse','--abbrev-ref','HEAD']).decode().strip()
    tracked={}
    for row in safe_git(root,['ls-files','--stage','-z']).split(b'\0'):
        if not row:continue
        meta,raw=row.split(b'\t',1);mode,_,stage=meta.decode().split()
        if stage!='0':raise GateError('index_conflict')
        if mode in {'100644','100755'}:tracked[raw.decode('utf-8')]=mode
    other={n.decode('utf-8') for n in safe_git(root,['ls-files','--others','--exclude-standard','-z']).split(b'\0') if n}
    rows=[];total=0
    for name in sorted(set(tracked)|other):
        if not source_allowed(cp,name,name in tracked):continue
        p=root/name
        if not p.exists():continue
        if p.is_symlink() or root not in p.resolve().parents:raise GateError('unsafe_source_link')
        before=p.stat()
        if not stat.S_ISREG(before.st_mode) or before.st_size>2*1024*1024:raise GateError('source_file_limit')
        data=p.read_bytes();after=p.stat()
        if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns):raise GateError('source_changed_during_capture')
        try:cp.safe_content(name,data,name in tracked)
        except Exception as e:raise GateError('source_content_gate') from e
        total+=len(data)
        if total>MAX_BYTES:raise GateError('snapshot_size_limit')
        rows.append((name,tracked.get(name,'100755' if name.endswith('.sh') else '100644'),data))
    if len(rows)>4000:raise GateError('source_count_limit')
    if safe_git(root,['rev-parse','HEAD']).decode().strip()!=head:raise GateError('source_changed_during_capture')
    manifest={'format':1,'source_head':head,'source_branch':branch,'workspace':label,
              'status':'source recovery snapshot, not a validated build',
              'excludes':['credentials','model weights','binaries','build output','private ops files']}
    rows.append(('CHECKPOINT.json','100644',json.dumps(manifest,sort_keys=True,indent=2).encode()+b'\n'))
    return rows,manifest

def fingerprint(rows):
    h=hashlib.sha256()
    for name,mode,data in rows:h.update(name.encode()+b'\0'+mode.encode()+b'\0'+hashlib.sha256(data).digest())
    return h.hexdigest()

def capture(cfg,label):
    rows,manifest=collect(cfg,label);fp=fingerprint(rows)
    result={'workspace':label,'source_head':manifest['source_head'],'fingerprint':fp,'files':len(rows),
            'source_bytes':sum(len(d) for _,_,d in rows),'observed_utc':utc()}
    old=read_json(Path(cfg['checkpoints'])/(label+'.json'),{})
    if old.get('fingerprint')==fp:
        return dict(result,status='unchanged',commit=old.get('commit'),last_verified_utc=old.get('verified_utc'))
    directory=Path(cfg['state'])/'snapshots'/label;directory.mkdir(parents=True,exist_ok=True)
    path=directory/(fp+'.zip')
    if not path.exists():
        used=sum(x.stat().st_size for x in (Path(cfg['state'])/'snapshots').rglob('*.zip'))
        if used+result['source_bytes']>512*1024*1024:raise GateError('local_outbox_quota')
        if shutil.disk_usage(directory).free<1024**3+result['source_bytes']:raise GateError('low_disk_reserve')
        temp=path.with_suffix('.zip.partial')
        try:
            with zipfile.ZipFile(temp,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
                for name,mode,data in rows:
                    info=zipfile.ZipInfo(name,(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
                    info.external_attr=(int(mode,8)<<16);z.writestr(info,data)
            with temp.open('r+b') as f:os.fsync(f.fileno())
            os.replace(temp,path)
        finally:temp.unlink(missing_ok=True)
    return dict(result,status='captured',archive=str(path),archive_sha256=file_hash(path))

def read_archive(cfg,label,fp,expected_hash):
    if not re.fullmatch('[a-f0-9]{64}',fp) or not re.fullmatch('[a-f0-9]{64}',expected_hash):raise GateError('invalid_archive_identity')
    path=Path(cfg['state'])/'snapshots'/label/(fp+'.zip')
    if not path.is_file() or path.is_symlink() or file_hash(path)!=expected_hash:raise GateError('archive_integrity')
    cp=policy(cfg);rows=[]
    with zipfile.ZipFile(path) as z:
        infos=z.infolist()
        if len(infos)>4001 or sum(x.file_size for x in infos)>MAX_BYTES+4096:raise GateError('archive_budget')
        if len({x.filename for x in infos})!=len(infos):raise GateError('duplicate_archive_entry')
        for x in infos:
            name=x.filename;p=PurePosixPath(name)
            if p.is_absolute() or '..' in p.parts or '\\' in name or ':' in name or x.is_dir():raise GateError('unsafe_archive_path')
            mode=format((x.external_attr>>16)&0xffff,'o')
            if mode not in {'100644','100755'}:raise GateError('unsafe_archive_mode')
            data=z.read(x)
            if name!='CHECKPOINT.json':
                if not source_allowed(cp,name,True):raise GateError('archive_source_gate')
                try:cp.safe_content(name,data,True)
                except Exception as e:raise GateError('archive_content_gate') from e
            rows.append((name,mode,data))
    if fingerprint(rows)!=fp:raise GateError('archive_fingerprint')
    manifests=[d for n,_,d in rows if n=='CHECKPOINT.json']
    if len(manifests)!=1:raise GateError('archive_manifest')
    manifest=json.loads(manifests[0])
    if manifest.get('workspace')!=label or not re.fullmatch('[a-f0-9]{40}',manifest.get('source_head','')):raise GateError('archive_scope')
    return rows,manifest

def publish(cfg,label,fp,archive_hash):
    root=scope(cfg,label);rows,manifest=read_archive(cfg,label,fp,archive_hash)
    state=Path(cfg['checkpoints']);state.mkdir(exist_ok=True)
    with file_lock(state/'runner.lock'):
        ref='refs/heads/checkpoints/wd/'+label
        remote=safe_git(root,['ls-remote','--heads','origin',ref]).decode().strip()
        parent=remote.split()[0] if remote else None
        old=read_json(state/(label+'.json'),{})
        if old.get('fingerprint')==fp and old.get('commit')==parent:
            return {**old,'status':'unchanged','verified_utc':utc()}
        if parent:safe_git(root,['fetch','--no-tags','--no-write-fetch-head','origin',ref])
        with tempfile.TemporaryDirectory(prefix='localops-index-',dir=state) as tmp:
            env={'GIT_INDEX_FILE':str(Path(tmp)/'index'),'GIT_AUTHOR_NAME':'WORLD.EXE Checkpoint','GIT_COMMITTER_NAME':'WORLD.EXE Checkpoint',
                 'GIT_AUTHOR_EMAIL':'worldexe-checkpoint@users.noreply.github.com','GIT_COMMITTER_EMAIL':'worldexe-checkpoint@users.noreply.github.com'}
            safe_git(root,['read-tree','--empty'],env=env)
            entries=[]
            for name,mode,data in rows:
                oid=safe_git(root,['hash-object','-w','--stdin'],data=data).decode().strip()
                entries.append(f'{mode} {oid}\t{name}'.encode()+b'\0')
            safe_git(root,['update-index','-z','--index-info'],data=b''.join(entries),env=env)
            tree=safe_git(root,['write-tree'],env=env).decode().strip()
            # A crash after push but before receipt must not create a duplicate snapshot commit.
            existing_tree=safe_git(root,['rev-parse',parent+'^{tree}']).decode().strip() if parent else None
            if existing_tree==tree:commit=parent;status='reconciled_existing'
            else:
                args=['commit-tree',tree]+(['-p',parent] if parent else [])
                commit=safe_git(root,args,data=f'checkpoint({label}): {manifest["source_head"][:12]} [skip ci]\n'.encode(),env=env).decode().strip()
                safe_git(root,['push','origin',commit+':'+ref]);status='pushed'
        verified=safe_git(root,['ls-remote','--heads','origin',ref]).decode().split()[0]
        if verified!=commit:raise GateError('remote_verification_failed')
        result={'workspace':label,'source_head':manifest['source_head'],'files':len(rows),'source_bytes':sum(len(d) for _,_,d in rows),
                'fingerprint':fp,'status':status,'commit':commit,'branch':ref,'verified_utc':utc(),'local_archive_sha256':archive_hash}
        atomic(state/(label+'.json'),result)
        return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);parser.add_argument('--config-hash',required=True)
    parser.add_argument('action',choices=['capture','publish']);parser.add_argument('--label',required=True)
    parser.add_argument('--fingerprint');parser.add_argument('--archive-hash');args=parser.parse_args()
    try:
        cfg=load_config(args.config,args.config_hash,check_binding=False)
        result=capture(cfg,args.label) if args.action=='capture' else publish(cfg,args.label,args.fingerprint,args.archive_hash)
        print(json.dumps({'ok':True,'result':result}));return 0
    except Exception as e:
        code=str(e) if isinstance(e,GateError) else type(e).__name__
        permanent=code in {'authentication_blocked','wrong_origin','wrong_git_common_dir','source_content_gate','archive_content_gate',
            'archive_integrity','configuration_integrity_failed','pinned_runtime_integrity_failed','index_conflict','local_outbox_quota','low_disk_reserve'}
        print(json.dumps({'ok':False,'error':code[:120],'permanent':permanent}));return 2
if __name__=='__main__':raise SystemExit(main())
