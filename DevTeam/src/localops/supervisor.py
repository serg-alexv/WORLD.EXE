"""Event-driven, localhost-only WORLD.EXE source recovery. Not an autonomous coding agent."""
from __future__ import annotations
import argparse, concurrent.futures, hmac, json, os, queue, secrets, shutil, socket, subprocess, sys, threading, time, urllib.request, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from common import GateError, WorkItem, RestartBudget, atomic, bounded_run, file_lock, load_config, log_event, read_json, utc, verify_files, kill_owned_process
from snapshot import policy, source_allowed, PRIVATE_PARTS
from winwatch import DirectoryWatch, ChildJob

class LocalHTTP(ThreadingHTTPServer):
    daemon_threads=True
    allow_reuse_address=False
    def __init__(self,*args,**kwargs):self.slots=threading.BoundedSemaphore(8);super().__init__(*args,**kwargs)
    def process_request(self,request,address):
        request.settimeout(3)
        if not self.slots.acquire(blocking=False):self.shutdown_request(request);return
        try:super().process_request(request,address)
        except Exception:self.slots.release();raise
    def process_request_thread(self,*args):
        try:super().process_request_thread(*args)
        finally:self.slots.release()

def make_handler(controller):
    class Handler(BaseHTTPRequestHandler):
        server_version='WORLD.EXE-LocalOps';sys_version=''
        def log_message(self,*a):pass
        def send(self,code,obj):
            data=json.dumps(obj).encode();self.send_response(code)
            self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)))
            self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff');self.send_header('Connection','close')
            self.end_headers()
            try:self.wfile.write(data)
            except OSError:pass
        def permitted(self,auth=True):
            expected={'127.0.0.1:'+str(controller.cfg['port']),'localhost:'+str(controller.cfg['port'])}
            if self.client_address[0]!='127.0.0.1' or self.headers.get('Host') not in expected:
                self.send(403,{'error':'loopback_host_required'});return False
            if self.headers.get('Origin') or self.headers.get('Transfer-Encoding'):
                self.send(403,{'error':'browser_origins_and_chunked_requests_denied'});return False
            if '?' in self.path or '#' in self.path:
                self.send(400,{'error':'query_arguments_denied'});return False
            if auth and not hmac.compare_digest(self.headers.get('Authorization',''), 'Bearer '+controller.token):
                self.send(401,{'error':'authorization_required'});return False
            return True
        def do_GET(self):
            if not self.permitted(auth=self.path!='/healthz'):return
            state=read_json(controller.state/'heartbeat.json',{})
            if self.path=='/healthz':
                self.send(200 if state.get('ready') else 503,{'service':'WORLD.EXE-LocalOps','instance':controller.nonce,
                    'ready':bool(state.get('ready')),'phase':state.get('phase','starting'),'utc':state.get('utc')})
            elif self.path=='/v1/status':self.send(200,state)
            else:self.send(404,{'error':'not_found'})
        def do_POST(self):
            if not self.permitted():return
            if self.path!='/v1/control':self.send(404,{'error':'not_found'});return
            try:
                length=int(self.headers.get('Content-Length','0'))
                if not 1<=length<=1024 or self.headers.get('Content-Type')!='application/json':raise ValueError()
                obj=json.loads(self.rfile.read(length))
                if not isinstance(obj,dict) or set(obj)!={'command'} or obj['command'] not in {'pause','resume','reconcile','retry','stop'}:raise ValueError()
                response=concurrent.futures.Future()
                controller.events.put(('control',obj['command'],response),block=False)
                result=response.result(timeout=2)
                self.send(200,result)
            except (ValueError,UnicodeError):self.send(400,{'error':'invalid_control'})
            except (queue.Full,concurrent.futures.TimeoutError):self.send(503,{'error':'control_queue_unavailable'})
        def do_OPTIONS(self):self.send(405,{'error':'method_not_allowed'})
        def do_PUT(self):self.send(405,{'error':'method_not_allowed'})
        def do_DELETE(self):self.send(405,{'error':'method_not_allowed'})
    return Handler

class Controller:
    def __init__(self,cfg,config_path,config_hash,nonce):
        self.cfg=cfg;self.config_path=config_path;self.config_hash=config_hash;self.nonce=nonce;self.state=Path(cfg['state'])
        self.state.mkdir(parents=True,exist_ok=True);self.token=(self.state/'control.token').read_text().strip()
        if len(self.token)!=64:raise GateError('invalid_control_token')
        old=read_json(self.state/'state.json',{})
        if old and old.get('schema')!=1:raise GateError('unsupported_state_schema')
        self.mode=read_json(self.state/'control.json',{'mode':'paused'})['mode']
        if self.mode not in {'running','paused'}:raise GateError('invalid_control_mode')
        self.items={s['label']:WorkItem(old.get('workspaces',{}).get(s['label'])) for s in cfg['sources']}
        for label,item in self.items.items():
            saved=read_json(Path(cfg['checkpoints'])/(label+'.json'),{})
            if saved.get('fingerprint'):
                item.data['remote_fingerprint']=saved['fingerprint'];item.data['remote_commit']=saved.get('commit')
                item.data['last_verified_utc']=saved.get('verified_utc',item.data.get('last_verified_utc'))
            item.mark(time.time(),0)
        self.cp=policy(cfg);self.events=queue.Queue(maxsize=1024);self.overflow=threading.Event();self.running=True
        self.metrics={'source_events':0,'captures':0,'unchanged':0,'publishes':0,'failures':0,**old.get('metrics',{})}
        self.watchers={};self.watch_defs={};self.watch_failures={};self.sequence=old.get('sequence',0)
        self.pool=concurrent.futures.ThreadPoolExecutor(max_workers=1,thread_name_prefix='worldexe-bounded-operation')
        self.agent_status={};self.active=None;self.state_changed=True;self.ready=False;self.last_event='startup';self.last_audit=time.time();self.last_step=time.time()
    def emit(self,label,name,kind):
        try:self.events.put_nowait(('source',label,(name,kind)))
        except queue.Full:self.overflow.set()
    def relevant(self,name,common=False):
        if name is None:return True
        parts=name.split('/')
        if common:
            if name=='HEAD' or name=='config' or name=='index':return True
            return (name.startswith('refs/heads/') and not name.startswith('refs/heads/checkpoints/')) or (name.startswith('worktrees/') and parts[-1] in {'HEAD','index'})
        if name=='.git':return True
        if any(p in self.cp.EXCLUDED_PARTS or p.lower() in PRIVATE_PARTS for p in parts):return False
        if source_allowed(self.cp,name,True):return True
        return '.' not in parts[-1] and parts[0] in (self.cp.ROOT_DIRS|{'DevTeam','Gamebox','PersonalClient'})
    def start_watch(self,key,path,label,common=False):
        def callback(name,kind):
            if label=='@agents' or kind!='filesystem' or self.relevant(name,common):self.emit(label,name,kind)
        watch=DirectoryWatch(path,callback);watch.start();watch.ready.wait(5)
        self.watchers[key]=watch;self.watch_defs[key]=(path,label,common)
        if not watch.ready.is_set() or watch.failure:self.watch_failures.setdefault(key,{'count':0,'due':time.time()+2})
    def watch_all(self):
        for s in self.cfg['sources']:self.start_watch(s['label'],s['path'],s['label'])
        self.start_watch('_git',Path(self.cfg['canonical'])/'.git','*',True)
        for folder in ('queue','receipts'):
            path=Path(self.cfg['ops'])/'devteam'/folder
            if path.is_dir():self.start_watch('_agent_'+folder,path,'@agents')
        self.observe_agents()
    def observe_agents(self):
        base=Path(self.cfg['ops'])/'devteam'
        queued={p.stem for p in (base/'queue').glob('*.json')};processed={p.stem for p in (base/'receipts').glob('*.json')}
        self.agent_status={'observed_utc':utc(),'queued_unprocessed':len(queued-processed),'receipts':len(processed),
            'tool_presence':{x:bool(shutil.which(x)) for x in ['git','node','trae','copilot','hf']},
            'automatic_inference':False,'installed_is_not_authenticated':True}
    def mark(self,label,reason):
        targets=self.items if label=='*' else {label:self.items[label]} if label in self.items else {}
        for item in targets.values():item.mark(time.time(),self.cfg.get('debounce_seconds',3))
        self.state_changed=True;self.last_event=reason
    def save(self):
        self.sequence+=1
        atomic(self.state/'state.json',{'schema':1,'sequence':self.sequence,'utc':utc(),'workspaces':{k:x.data for k,x in self.items.items()},'metrics':self.metrics})
        self.state_changed=False
    def heartbeat(self):
        watch_status={key: bool(w.is_alive() and not w.failure) for key,w in self.watchers.items()}
        self.ready=bool(watch_status) and all(watch_status.values())
        blocked=[k for k,v in self.items.items() if v.data['circuit']]
        phase='paused' if self.mode=='paused' else 'blocked' if blocked or not self.ready else 'working' if self.active else 'idle'
        active={k:self.active[k] for k in ('action','label','started')} if self.active else None
        atomic(self.state/'heartbeat.json',{'service':'WORLD.EXE-LocalOps','instance':self.nonce,'pid':os.getpid(),'utc':utc(),'heartbeat_epoch':time.time(),
            'ready':self.ready,'phase':phase,'mode':self.mode,'binding_verified':True,'runtime_pinned':True,'sequence':self.sequence,
            'agents':self.agent_status,'active':active,'watchers':watch_status,'blocked_workspaces':blocked,'metrics':self.metrics,'last_event':self.last_event,
            'workspaces':{k:{a:v.data.get(a) for a in ['source_head','fingerprint','remote_fingerprint','remote_commit','last_verified_utc','last_capture','dirty','attempts','circuit','error']}
                for k,v in self.items.items()},'authority':{'source_checkpoints':True,'source_edits':False,'model_calls':False,'releases':False,'apple_writes':False}})
    def handle_events(self):
        for _ in range(256):
            try:kind,a,b=self.events.get_nowait()
            except queue.Empty:break
            if kind=='source':
                name,event=b
                if a=='@agents':self.observe_agents();continue
                self.metrics['source_events']+=1;self.mark(a,event)
                if event in {'overflow','watch_error'}:log_event(self.state,event,workspace=a)
            elif kind=='control':
                command=a;response=b
                if command in {'pause','resume'}:
                    self.mode='paused' if command=='pause' else 'running';atomic(self.state/'control.json',{'mode':self.mode,'utc':utc()})
                    if command=='resume':self.mark('*','explicit_resume')
                elif command=='reconcile':self.mark('*','explicit_reconcile')
                elif command=='retry':
                    for item in self.items.values():item.reset_retry();item.data.pop('failed_generation',None)
                    self.watch_failures={};self.mark('*','explicit_retry')
                elif command=='stop':atomic(self.state/'stop.json',{'intentional':True,'utc':utc()});self.running=False
                self.state_changed=True;log_event(self.state,'operator_control',command=command)
                if not response.cancelled():response.set_result({'command':command,'accepted':True,'mode':self.mode,'in_flight_operation_finishes':bool(self.active)})
        if self.overflow.is_set():self.overflow.clear();self.mark('*','event_queue_overflow');log_event(self.state,'event_queue_overflow')
    def maintain_watches(self):
        now=time.time()
        for key,watch in list(self.watchers.items()):
            if watch.is_alive() and not watch.failure:continue
            budget=self.watch_failures.setdefault(key,{'count':0,'due':now+2})
            if budget['count']>=3 or now<budget['due']:continue
            watch.close();budget['count']+=1;budget['due']=now+[2,5,15][budget['count']-1]
            self.start_watch(key,*self.watch_defs[key]);self.mark('*','watcher_reconnected')
            log_event(self.state,'watcher_restart',watch=key,attempt=budget['count'])
    def operation(self,action,label,fp=None,archive_hash=None):
        verify_files(self.cfg)
        cmd=[self.cfg['python'],str(Path(self.cfg['release'])/'snapshot.py'),'--config',self.config_path,'--config-hash',self.config_hash,action,'--label',label]
        if action=='publish':cmd+=['--fingerprint',fp,'--archive-hash',archive_hash]
        rc,out,err=bounded_run(cmd,timeout=60 if action=='capture' else 180,cwd=self.cfg['release'])
        try:result=json.loads(out)
        except Exception:raise GateError('helper_invalid_response')
        if rc and result.get('ok'):raise GateError('helper_exit_mismatch')
        return result
    def finish_operation(self):
        if not self.active or not self.active['future'].done():return
        a=self.active;self.active=None;item=self.items[a['label']];d=item.data
        try:result=a['future'].result()
        except Exception as e:result={'ok':False,'error':str(e) if isinstance(e,GateError) else type(e).__name__,'permanent':False}
        if result.get('ok'):
            r=result['result']
            if a['action']=='capture':
                item.captured(r,a['generation']);self.metrics['captures']+=1
                d.pop('failed_generation',None)
                if r['status']=='unchanged':
                    self.metrics['unchanged']+=1;d['remote_fingerprint']=r['fingerprint'];d['remote_commit']=r.get('commit')
                    if r.get('last_verified_utc'):d['last_verified_utc']=r['last_verified_utc']
                else:log_event(self.state,'local_snapshot',workspace=a['label'],fingerprint=r['fingerprint'],bytes=r['source_bytes'])
            else:
                item.published(r,a['fingerprint']);self.metrics['publishes']+=1
                log_event(self.state,'checkpoint_verified',workspace=a['label'],fingerprint=a['fingerprint'],commit=r['commit'],status=r['status'])
        else:
            self.metrics['failures']+=1;item.fail(time.time(),result.get('error','operation_failed'),result.get('permanent',False))
            if a['action']=='capture':
                d['due']=d['next_retry'];d['failed_generation']=a['generation']
            log_event(self.state,'operation_blocked' if d['circuit'] else 'operation_retry',workspace=a['label'],action=a['action'],error=d['error'],attempt=d['attempts'])
        self.state_changed=True
    def schedule(self):
        if self.active or self.mode!='running' or not self.running:return
        now=time.time()
        for label,item in self.items.items():
            d=item.data
            if d['dirty'] and now>=d['due'] and (not d['circuit'] or d['generation']>d.get('failed_generation',-1)):
                self.active={'action':'capture','label':label,'started':utc(),'generation':d['generation'],
                    'future':self.pool.submit(self.operation,'capture',label)};return
        for label,item in self.items.items():
            d=item.data
            if item.pending() and not d['circuit'] and now>=d['next_retry']:
                self.active={'action':'publish','label':label,'started':utc(),'fingerprint':d['fingerprint'],
                    'future':self.pool.submit(self.operation,'publish',label,d['fingerprint'],d['archive_sha256'])};return
    def run(self):
        self.http=LocalHTTP((self.cfg['host'],self.cfg['port']),make_handler(self))
        threading.Thread(target=self.http.serve_forever,daemon=True,name='worldexe-local-http').start()
        self.watch_all();log_event(self.state,'worker_started',pid=os.getpid(),instance=self.nonce)
        heartbeat_due=0
        try:
            while self.running:
                now=time.time()
                if now-self.last_step>30 or now<self.last_step:
                    self.mark('*','wake_or_clock_reconciliation')
                self.last_step=now
                # Safety audit catches missed notifications; unchanged trees do not contact GitHub.
                if now-self.last_audit>=1800:
                    self.last_audit=now;verify_files(self.cfg);self.mark('*','inventory_safety_audit')
                self.handle_events();self.maintain_watches();self.finish_operation();self.schedule()
                if self.state_changed:self.save()
                if now>=heartbeat_due:self.heartbeat();heartbeat_due=now+2
                time.sleep(.25)
        finally:
            for watch in self.watchers.values():watch.close()
            self.http.shutdown();self.http.server_close()
            self.pool.shutdown(wait=False,cancel_futures=True)
            log_event(self.state,'worker_stopped',instance=self.nonce)


def guardian(cfg,path,config_hash):
    state=Path(cfg['state']);state.mkdir(parents=True,exist_ok=True)
    with file_lock(state/'guardian.lock'):
        if (state/'stop.json').exists():return 0
        old=read_json(state/'guardian.json',{})
        budget=RestartBudget(old.get('restart_times',[]));nonce=None
        while True:
            verify_files(cfg)
            nonce=uuid.uuid4().hex
            gate=state/'launch.json';gate.unlink(missing_ok=True)
            cmd=[cfg['python'],str(Path(cfg['release'])/'supervisor.py'),'--config',path,'--config-hash',config_hash,'serve','--nonce',nonce]
            with ChildJob() as job:
                log=state/'worker.log'
                if log.exists() and log.stat().st_size>256000:os.replace(log,state/'worker.previous.log')
                with log.open('ab') as output:
                    p=subprocess.Popen(cmd,stdin=subprocess.DEVNULL,stdout=output,stderr=output,
                        cwd=cfg['release'],creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0),start_new_session=(os.name!='nt'))
                    job.assign(p)
                    atomic(gate,{'nonce':nonce,'guardian_pid':os.getpid(),'worker_pid':p.pid})
                    atomic(state/'guardian.json',{'utc':utc(),'guardian_pid':os.getpid(),'worker_pid':p.pid,'instance':nonce,'restart_times':budget.times,'circuit':False})
                    start=time.time();last_progress=start;reason='worker_exit'
                    while p.poll() is None:
                        if (state/'stop.json').exists():kill_owned_process(p);return 0
                        try:heartbeat=read_json(state/'heartbeat.json',{})
                        except GateError:heartbeat={}
                        now=time.time()
                        if heartbeat.get('instance')==nonce:
                            last_progress=max(last_progress,heartbeat.get('heartbeat_epoch',0))
                        # Sleep/resume never counts as a worker fault before a recovery grace period.
                        if now-last_progress>40 and now-start>60:
                            time.sleep(3)
                            fresh=read_json(state/'heartbeat.json',{})
                            if fresh.get('instance')!=nonce or time.time()-fresh.get('heartbeat_epoch',0)>40:
                                reason='heartbeat_stalled';kill_owned_process(p);break
                        time.sleep(2)
            if (state/'stop.json').exists():return 0
            delay=budget.record(time.time())
            atomic(state/'guardian.json',{'utc':utc(),'guardian_pid':os.getpid(),'last_worker_pid':p.pid,'restart_times':budget.times,'circuit':delay is None,'reason':reason})
            log_event(state,'worker_recovery' if delay is not None else 'guardian_circuit_open',reason=reason,exit=p.returncode,delay=delay)
            if delay is None:return 0
            time.sleep(delay)

def client(cfg,command):
    state=Path(cfg['state'])
    token=(state/'control.token').read_text().strip()
    path='/v1/status' if command=='status' else '/v1/control'
    data=None if command=='status' else json.dumps({'command':command}).encode()
    req=urllib.request.Request(f'http://127.0.0.1:{cfg["port"]}'+path,data=data,
        headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req,timeout=5) as response:return json.loads(response.read(131072))

def main():
    sys.dont_write_bytecode=True
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);parser.add_argument('--config-hash',required=True)
    parser.add_argument('action',choices=['guardian','serve','ctl']);parser.add_argument('--nonce');parser.add_argument('--command',default='status')
    a=parser.parse_args();cfg=load_config(a.config,a.config_hash)
    if a.action=='guardian':return guardian(cfg,a.config,a.config_hash)
    if a.action=='ctl':
        if a.command not in {'status','pause','resume','retry','reconcile','stop'}:raise GateError('unknown_control')
        print(json.dumps(client(cfg,a.command),indent=2));return 0
    if not a.nonce or len(a.nonce)!=32:raise GateError('guardian_launch_required')
    state=Path(cfg['state']);deadline=time.time()+10
    while time.time()<deadline:
        gate=read_json(state/'launch.json',{})
        if gate.get('nonce')==a.nonce and gate.get('worker_pid')==os.getpid():break
        time.sleep(.1)
    else:raise GateError('unassigned_worker_refused')
    with file_lock(state/'worker.lock'):Controller(cfg,a.config,a.config_hash,a.nonce).run()
    return 0
if __name__=='__main__':
    try:raise SystemExit(main())
    except GateError as e:print(json.dumps({'blocked':str(e)}));raise SystemExit(2)
