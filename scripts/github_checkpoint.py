"""Five-minute, source-only GitHub snapshots. Never alters a working index or branch.
Run one iteration: python github_checkpoint.py --config checkpoint-config.json
Windows Task Scheduler owns recurrence; this program is not an AI worker.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile

ROOT_FILES = {'.gitignore', '.gitattributes', 'AGENTS.md', 'BACKLOG.md', 'GENESIS.md', 'README.md', 'project.yml', 'LICENSE'}
ROOT_DIRS = {'App', 'WorldCore', 'LocalLlama', 'Dependencies', 'Benchmarks', 'UITests', 'AppUnitTests', 'docs', 'scripts', '.github'}
TEXT_EXT = {'.swift','.c','.cc','.cpp','.h','.hpp','.m','.mm','.metal','.md','.txt','.py','.ps1','.sh','.yml','.yaml','.json','.plist','.xcprivacy','.modulemap','.xcconfig'}
EXCLUDED_PARTS = {'.git','.build','.swiftpm','build','DerivedData','Frameworks','__pycache__','node_modules','xcuserdata'}
SECRET_PATTERNS = [re.compile(p) for p in (
    rb'-----BEGIN (?:EC |RSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',
    rb'gh[pousr]_[A-Za-z0-9]{25,}',
    rb'github_pat_[A-Za-z0-9_]{35,}',
    rb'(?:sk-proj-|hf_)[A-Za-z0-9_-]{32,}',
    rb'(?i)(?:api[_-]?key|password|access[_-]?token)\s*[:=]\s*[\"\'][A-Za-z0-9_+/=-]{28,}[\"\']',
)]


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def git(root: Path, args: list[str], data: bytes | None = None, env: dict | None = None) -> bytes:
    result = subprocess.run(['git', '-C', str(root), *args], input=data, capture_output=True,
                            env=env, timeout=90)
    if result.returncode:
        raise RuntimeError(f'git {args[0]} failed (exit {result.returncode}); raw output suppressed')
    return result.stdout


def allowed(name: str, tracked: bool) -> bool:
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or any(p in EXCLUDED_PARTS for p in path.parts):
        return False
    if any(p.lower().startswith('.env') for p in path.parts):
        return False
    # Personal-client backups are code-only, never arbitrary exports or account data.
    if path.parts and path.parts[0] == 'PersonalClient':
        if any(p.lower() in {'imports','exports','privatedata','generated','fixtures','recordings'} for p in path.parts):
            return False
        if name in {'PersonalClient/.gitignore','PersonalClient/project.yml','PersonalClient/Core/Package.swift',
                    'PersonalClient/App/PrivacyInfo.xcprivacy'}:
            return True
        source_roots = ('PersonalClient/App/', 'PersonalClient/AppTests/', 'PersonalClient/UITests/',
                        'PersonalClient/Core/Sources/', 'PersonalClient/Core/Tests/')
        return path.suffix == '.swift' and name.startswith(source_roots)
    if name in ROOT_FILES:
        return True
    if not path.parts or path.parts[0] not in ROOT_DIRS:
        return False
    if path.suffix.lower() in TEXT_EXT:
        return True
    return tracked and name.startswith('App/Assets.xcassets/') and path.suffix.lower() == '.png'


def safe_content(name: str, data: bytes, tracked: bool) -> None:
    if len(data) > 2 * 1024 * 1024:
        raise ValueError(f'Source size limit exceeded: {name}')
    if PurePosixPath(name).suffix.lower() == '.png':
        if not tracked or not data.startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError('Unapproved binary asset')
    else:
        data.decode('utf-8-sig')
        if any(pattern.search(data) for pattern in SECRET_PATTERNS):
            raise ValueError(f'Possible credential in {name}; snapshot refused')


def snapshot(root: Path, label: str, canonical: Path, state_dir: Path, dry: bool) -> dict:
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,48}', label):
        raise ValueError('Invalid snapshot label')
    root = root.resolve()
    if root != canonical and root.parent != canonical.parent / 'WORLD.EXE-worktrees':
        raise ValueError('Source is outside approved WORLD.EXE workspaces')
    if git(root, ['remote','get-url','origin']).decode().strip() not in {
        'https://github.com/serg-alexv/WORLD.EXE.git','https://github.com/serg-alexv/WORLD.EXE',
        'git@github.com:serg-alexv/WORLD.EXE.git'}:
        raise ValueError('Unexpected remote; no upload')
    common = (root / git(root,['rev-parse','--git-common-dir']).decode().strip()).resolve()
    if common != (canonical / '.git').resolve():
        raise ValueError('Workspace is not in the approved repository')
    head = git(root, ['rev-parse','HEAD']).decode().strip()
    branch = git(root, ['rev-parse','--abbrev-ref','HEAD']).decode().strip()
    tracked = {}
    for row in git(root, ['ls-files','--stage','-z']).split(b'\0'):
        if not row:
            continue
        metadata, rawname = row.split(b'\t', 1)
        mode, _, stage = metadata.decode().split()
        if stage != '0':
            raise ValueError('Unresolved index conflict; snapshot stopped')
        if mode not in {'100644','100755'}:
            continue
        tracked[rawname.decode('utf-8')] = mode
    other = {x.decode('utf-8') for x in git(root,['ls-files','--others','--exclude-standard','-z']).split(b'\0') if x}
    rows = []
    for name in sorted(set(tracked) | other):
        if not allowed(name, name in tracked):
            continue
        path = root / name
        if not path.exists():
            continue
        if path.is_symlink() or root not in path.resolve().parents:
            raise ValueError('Symlink or outside-source reference refused')
        before = path.stat()
        data = path.read_bytes()
        after = path.stat()
        if (before.st_size,before.st_mtime_ns) != (after.st_size,after.st_mtime_ns):
            raise ValueError('File changed while reading; retry next interval')
        safe_content(name, data, name in tracked)
        rows.append((name, tracked.get(name, '100755' if name.endswith('.sh') else '100644'), data))
    if sum(len(data) for _,_,data in rows) > 24 * 1024 * 1024:
        raise ValueError('Snapshot exceeds approved source budget')
    manifest = {'format':1, 'source_head':head, 'source_branch':branch, 'workspace':label,
                'status':'source recovery snapshot, not a validated build',
                'excludes':['credentials','model weights','binaries','build output','private ops files']}
    rows.append(('CHECKPOINT.json','100644',json.dumps(manifest,sort_keys=True,indent=2).encode()+b'\n'))
    fingerprint = hashlib.sha256()
    for name,mode,data in rows:
        fingerprint.update(name.encode()+b'\0'+mode.encode()+b'\0'+hashlib.sha256(data).digest())
    stamp=fingerprint.hexdigest()
    receipt={'workspace':label,'source_head':head,'files':len(rows),'source_bytes':sum(len(d) for _,_,d in rows),'fingerprint':stamp}
    if dry:
        return dict(receipt,status='validated_dry_run')
    remote_ref = 'refs/heads/checkpoints/wd/'+label
    tip = git(root, ['ls-remote','--heads','origin',remote_ref]).decode().strip()
    parent = tip.split()[0] if tip else None
    previous_path = state_dir / (label+'.json')
    previous = json.loads(previous_path.read_text()) if previous_path.exists() else {}
    if previous.get('fingerprint') == stamp and parent == previous.get('commit'):
        return dict(receipt,status='unchanged',commit=parent,branch=remote_ref)
    if parent:
        git(root,['fetch','--no-tags','--no-write-fetch-head','origin',remote_ref])
    with tempfile.TemporaryDirectory(prefix='index-', dir=state_dir) as temporary:
        env = os.environ.copy()
        env['GIT_INDEX_FILE'] = str(Path(temporary)/'index')
        env.update({'GIT_AUTHOR_NAME':'WORLD.EXE Checkpoint','GIT_COMMITTER_NAME':'WORLD.EXE Checkpoint',
                    'GIT_AUTHOR_EMAIL':'worldexe-checkpoint@users.noreply.github.com',
                    'GIT_COMMITTER_EMAIL':'worldexe-checkpoint@users.noreply.github.com'})
        git(root,['read-tree','--empty'],env=env)
        entries=[]
        for name,mode,data in rows:
            oid=git(root,['hash-object','-w','--stdin'],data=data).decode().strip()
            entries.append(f'{mode} {oid}\t{name}'.encode()+b'\0')
        git(root,['update-index','-z','--index-info'],data=b''.join(entries),env=env)
        tree=git(root,['write-tree'],env=env).decode().strip()
        args=['commit-tree',tree]
        if parent:
            args += ['-p',parent]
        commit=git(root,args,data=f'checkpoint({label}): {head[:12]} [skip ci]\n'.encode(),env=env).decode().strip()
    git(root,['push','origin',commit+':'+remote_ref])
    verified=git(root,['ls-remote','--heads','origin',remote_ref]).decode().split()[0]
    if verified != commit:
        raise RuntimeError('Remote verification did not match uploaded checkpoint')
    receipt.update(status='pushed',commit=commit,branch=remote_ref,verified_utc=now())
    previous_path.write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    return receipt


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,required=True)
    parser.add_argument('--dry-run',action='store_true')
    args=parser.parse_args()
    config=json.loads(args.config.read_text(encoding='utf-8-sig'))
    canonical=Path(config['canonical']).resolve()
    state_dir=Path(config['state']).resolve()
    state_dir.mkdir(parents=True,exist_ok=True)
    # OS lock is released if the process exits; no stale lock blocks recovery.
    import msvcrt
    with (state_dir/'runner.lock').open('a+b') as lock:
        lock.seek(0); lock.write(b'0'); lock.flush(); lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
        except OSError:
            print(json.dumps({'status':'another_checkpoint_running'})); return 0
        report={'observed_utc':now(),'snapshots':[]}
        for source in config['sources']:
            try:
                result=snapshot(Path(source['path']),source['label'],canonical,state_dir,args.dry_run)
            except Exception as error:
                result={'workspace':source['label'],'status':'error','error_type':type(error).__name__,'detail':str(error)}
            report['snapshots'].append(result)
        report['finished_utc']=now()
        state_dir.joinpath('latest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        with state_dir.joinpath('history.jsonl').open('a',encoding='utf-8') as log:
            log.write(json.dumps(report)+'\n')
        print(json.dumps(report))
        return int(any(x['status']=='error' for x in report['snapshots']))


if __name__ == '__main__':
    sys.exit(main())
