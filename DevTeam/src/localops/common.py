"""Private, machine-bound WORLD.EXE local operations primitives."""
from __future__ import annotations
import contextlib, hashlib, json, os, re, subprocess, sys, time, uuid
from pathlib import Path

REPO = 'serg-alexv/WORLD.EXE'
ORIGINS = {f'https://github.com/{REPO}', f'https://github.com/{REPO}.git', f'git@github.com:{REPO}.git'}
class GateError(RuntimeError):
    pass

def utc():
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat()

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode('utf-8')

def digest(data):
    return hashlib.sha256(data).hexdigest()

def file_hash(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda: f.read(1024*1024), b''): h.update(chunk)
    return h.hexdigest()

def read_json(path, default=None):
    path = Path(path)
    if not path.exists(): return default
    if path.stat().st_size > 1024*1024: raise GateError('json_size_limit')
    try: return json.loads(path.read_text(encoding='utf-8-sig'))
    except (ValueError, UnicodeError) as e: raise GateError('corrupt_json_requires_review') from e

def atomic(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        with tmp.open('wb') as f:
            f.write(json.dumps(value, indent=2, ensure_ascii=False).encode('utf-8')); f.flush(); os.fsync(f.fileno())
        for attempt in range(5):
            try: os.replace(tmp, path); return
            except PermissionError:
                if attempt == 4: raise
                time.sleep(.05*(attempt+1))
    finally: tmp.unlink(missing_ok=True)

def log_event(state, kind, **details):
    path = Path(state)/'events.jsonl'
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.stat().st_size > 1024*1024:
        (path.parent/'events.3.jsonl').unlink(missing_ok=True)
        for n in (2, 1):
            p = path.parent/f'events.{n}.jsonl'
            if p.exists(): os.replace(p, path.parent/f'events.{n+1}.jsonl')
        os.replace(path, path.parent/'events.1.jsonl')
    with path.open('a', encoding='utf-8') as f:
        f.write(json.dumps({'utc':utc(), 'event':kind, **details}, ensure_ascii=False)+'\n')

def runtime_identity():
    if os.name != 'nt': raise GateError('native_windows_required')
    script = r'''$ErrorActionPreference='Stop'; $g=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid; $u=(Get-CimInstance Win32_ComputerSystemProduct).UUID; $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value; @{machineGuid=$g;hardwareUUID=$u;sid=$sid;host=$env:COMPUTERNAME} | ConvertTo-Json -Compress'''
    p = subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',script],
        capture_output=True, timeout=20, creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    if p.returncode: raise GateError('identity_probe_failed')
    obj = json.loads(p.stdout.decode('utf-8-sig'))
    if not obj.get('machineGuid') or not obj.get('sid') or not obj.get('hardwareUUID'):
        raise GateError('identity_incomplete')
    return obj

def binding(identity, salt):
    return digest(salt.encode()+b'\0'+canonical(identity))

def verify_files(cfg):
    release = Path(cfg['release']).resolve()
    for name, expected in cfg['pins'].items():
        p = (release/name).resolve()
        if p.parent != release or not p.is_file() or p.is_symlink() or file_hash(p)!=expected:
            raise GateError('pinned_runtime_integrity_failed')

def load_config(path, expected_hash, check_binding=True):
    path = Path(path).resolve()
    if not re.fullmatch('[a-f0-9]{64}', expected_hash) or file_hash(path)!=expected_hash:
        raise GateError('configuration_integrity_failed')
    cfg = read_json(path)
    if cfg.get('repository')!=REPO or cfg.get('schema')!=1: raise GateError('wrong_repository')
    if cfg.get('host')!='127.0.0.1' or not 1024<=cfg.get('port',0)<=65535: raise GateError('loopback_only')
    ops = Path(cfg['ops']).resolve(); root = Path(cfg['canonical']).resolve()
    if ops.name!='WORLD.EXE-ops' or root.name!='WORLD.EXE' or ops.parent!=root.parent:
        raise GateError('invalid_private_boundary')
    if Path(cfg['state']).resolve()!=ops/'local-supervisor'/'state': raise GateError('invalid_state_path')
    if Path(cfg['checkpoints']).resolve()!=ops/'checkpoints': raise GateError('invalid_checkpoint_path')
    if Path(cfg['release']).resolve().parent!=ops/'local-supervisor'/'releases': raise GateError('invalid_release_path')
    if cfg.get('network_authority')!='checkpoint_refs_only': raise GateError('invalid_authority')
    sources = cfg.get('sources',[])
    if not 1<=len(sources)<=20: raise GateError('invalid_sources')
    labels=set();paths=set()
    for s in sources:
        p=Path(s['path']).resolve();label=s['label']
        if not re.fullmatch('[a-z0-9][a-z0-9-]{0,48}',label) or label in labels or str(p) in paths:
            raise GateError('duplicate_or_invalid_source')
        if p!=root and p.parent!=root.parent/'WORLD.EXE-worktrees': raise GateError('source_outside_scope')
        labels.add(label);paths.add(str(p))
    verify_files(cfg)
    if check_binding and binding(runtime_identity(),cfg['binding_salt'])!=cfg['binding_hash']:
        raise GateError('machine_or_user_binding_mismatch')
    return cfg

@contextlib.contextmanager
def file_lock(path):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    f=path.open('a+b');f.seek(0);f.write(b'0');f.flush();f.seek(0)
    try:
        if os.name=='nt':
            import msvcrt
            try: msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,1)
            except OSError as e: raise GateError('already_running') from e
        else:
            import fcntl
            try: fcntl.flock(f.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
            except OSError as e: raise GateError('already_running') from e
        yield
    finally: f.close()

def kill_owned_process(p):
    if p.poll() is not None: return
    if os.name=='nt':
        subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],capture_output=True,timeout=10,
                       creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    else:
        import signal
        os.killpg(p.pid,signal.SIGKILL)
    p.wait(timeout=10)

def bounded_run(cmd, timeout=90, cwd=None, env=None):
    p=subprocess.Popen(cmd,cwd=cwd,env=env,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
        start_new_session=(os.name!='nt'),creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    try: out,err=p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        kill_owned_process(p); raise GateError('operation_timeout')
    if len(out)+len(err)>1024*1024: raise GateError('operation_output_budget')
    return p.returncode,out,err

class RestartBudget:
    def __init__(self, times=None, limit=3, window=600): self.times=list(times or []);self.limit=limit;self.window=window
    def record(self, now):
        self.times=[x for x in self.times if 0<=now-x<self.window]
        if len(self.times)>=self.limit: return None
        self.times.append(now)
        return [2,5,15][min(len(self.times)-1,2)]

class WorkItem:
    def __init__(self, saved=None):
        self.data={'generation':0,'dirty':False,'due':0,'fingerprint':None,'archive':None,'archive_sha256':None,
            'remote_fingerprint':None,'remote_commit':None,'last_capture':None,'last_verified_utc':None,
            'attempts':0,'next_retry':0,'circuit':False,'error':None, **(saved or {})}
    def mark(self, now, debounce=3):
        d=self.data;d['generation']+=1;d['dirty']=True
        # Debounce writes but impose a 30-second upper bound during sustained editing.
        d.setdefault('first_dirty',now)
        d['due']=min(now+debounce,d['first_dirty']+30)
    def captured(self, result, generation):
        d=self.data;old=d['fingerprint'];d.update({k:result[k] for k in ('fingerprint','source_head','files','source_bytes')})
        d['last_capture']=utc()
        sticky=d.get('operator_retry_required',False)
        if not sticky:d['error']=None
        if 'archive' in result: d['archive']=result['archive'];d['archive_sha256']=result['archive_sha256']
        if old!=d['fingerprint'] and not sticky: d['attempts']=0;d['next_retry']=0;d['circuit']=False
        if generation==d['generation']: d['dirty']=False;d.pop('first_dirty',None)
    def pending(self):
        d=self.data;return bool(d['archive'] and d['fingerprint']!=d['remote_fingerprint'])
    def fail(self, now, code, permanent=False):
        d=self.data;d['attempts']+=1;d['error']=code
        d['circuit']=permanent or d['attempts']>=5
        if code in {'authentication_blocked','wrong_origin','wrong_git_common_dir','configuration_integrity_failed','pinned_runtime_integrity_failed','archive_integrity'}:d['operator_retry_required']=True
        d['next_retry']=now+[15,60,300,900,1800][min(d['attempts']-1,4)]
    def published(self, result, fingerprint):
        d=self.data;d['remote_fingerprint']=fingerprint;d['remote_commit']=result['commit']
        d['last_verified_utc']=result['verified_utc'];d['attempts']=0;d['error']=None;d['circuit']=False
    def reset_retry(self):
        self.data.update(attempts=0,next_retry=0,circuit=False,error=None,operator_retry_required=False)
