import concurrent.futures, hashlib, http.client, importlib.util, json, os, queue, subprocess, sys, tempfile, threading, time, unittest
from pathlib import Path
from unittest.mock import patch
SOURCE=Path(__file__).resolve().parents[1]/'src'
if (SOURCE/'localops').is_dir():SOURCE=SOURCE/'localops'
sys.path.insert(0,str(SOURCE))
import common, snapshot, supervisor
from winwatch import DirectoryWatch, ChildJob

class StateTests(unittest.TestCase):
    def test_debounce_coalesces(self):
        x=common.WorkItem();x.mark(10,3);x.mark(11,3)
        self.assertEqual(x.data['due'],14);self.assertEqual(x.data['generation'],2)
    def test_continuous_edits_have_deadline(self):
        x=common.WorkItem()
        for t in range(60):x.mark(t,3)
        self.assertEqual(x.data['due'],30)
    def test_changed_during_capture_remains_dirty(self):
        x=common.WorkItem();x.mark(1);generation=x.data['generation'];x.mark(2)
        x.captured({'fingerprint':'a','source_head':'b','files':1,'source_bytes':1},generation)
        self.assertTrue(x.data['dirty'])
    def test_capture_and_publish_have_separate_truth(self):
        x=common.WorkItem();x.mark(1)
        x.captured({'fingerprint':'a','source_head':'b','files':1,'source_bytes':1,'archive':'x','archive_sha256':'y'},1)
        self.assertTrue(x.pending());self.assertIsNone(x.data['remote_commit'])
        x.published({'commit':'c','verified_utc':'d'},'a');self.assertFalse(x.pending())
    def test_old_completion_does_not_ack_new_snapshot(self):
        x=common.WorkItem({'fingerprint':'new','archive':'archive'});x.published({'commit':'c','verified_utc':'d'},'old')
        self.assertTrue(x.pending())
    def test_retry_is_bounded(self):
        x=common.WorkItem()
        for n in range(5):x.fail(1,'network')
        self.assertTrue(x.data['circuit']);self.assertEqual(x.data['attempts'],5)
    def test_authentication_failure_opens_circuit(self):
        x=common.WorkItem();x.fail(0,'authentication_blocked',True);self.assertTrue(x.data['circuit'])
    def test_auth_circuit_is_not_reset_by_source_edits(self):
        x=common.WorkItem();x.fail(0,'authentication_blocked',True)
        x.mark(1);x.captured({'fingerprint':'new','source_head':'sha','files':1,'source_bytes':1},1)
        self.assertTrue(x.data['circuit']);self.assertTrue(x.data['operator_retry_required'])
    def test_manual_retry_reopens(self):
        x=common.WorkItem();x.fail(0,'authentication_blocked',True);x.reset_retry();self.assertFalse(x.data['circuit'])
    def test_restart_budget_survives_serialization(self):
        b=common.RestartBudget();self.assertEqual([b.record(n) for n in range(4)],[2,5,15,None])
        c=common.RestartBudget(json.loads(json.dumps(b.times)));self.assertIsNone(c.record(5))
    def test_restart_budget_window_expires(self):
        b=common.RestartBudget([1,2,3]);self.assertEqual(b.record(700),2)
    def test_machine_user_salt_binding(self):
        self.assertNotEqual(common.binding({'sid':'a'},'x'),common.binding({'sid':'b'},'x'))
        self.assertNotEqual(common.binding({'sid':'a'},'x'),common.binding({'sid':'a'},'y'))
    def test_atomic_state_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'s.json';common.atomic(p,{'n':1});common.atomic(p,{'n':2});self.assertEqual(common.read_json(p),{'n':2})
            self.assertEqual(list(Path(d).glob('*.tmp')),[])
    def test_corrupt_state_is_not_silently_reset(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'s.json';p.write_text('{')
            with self.assertRaises(common.GateError):common.read_json(p,{})
    def test_exclusive_lock(self):
        with tempfile.TemporaryDirectory() as d:
            with common.file_lock(Path(d)/'l'):
                with self.assertRaises(common.GateError):
                    with common.file_lock(Path(d)/'l'):pass
            with common.file_lock(Path(d)/'l'):pass
    def test_runtime_tamper_blocks(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'a.py';p.write_text('first');cfg={'release':d,'pins':{'a.py':common.file_hash(p)}}
            common.verify_files(cfg);p.write_text('changed')
            with self.assertRaises(common.GateError):common.verify_files(cfg)
    def test_manifest_traversal_blocks(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(common.GateError):common.verify_files({'release':d,'pins':{'../a.py':'a'*64}})
    def test_bounded_subprocess_timeout(self):
        with self.assertRaises(common.GateError):common.bounded_run([sys.executable,'-c','import time;time.sleep(20)'],timeout=.15)
    def test_bounded_subprocess_exit_recorded(self):
        rc,out,err=common.bounded_run([sys.executable,'-c','print("ok");raise SystemExit(4)'])
        self.assertEqual(rc,4);self.assertEqual(out.strip(),b'ok')

class FakeController:
    def __init__(self,d):
        self.state=Path(d);self.cfg={'port':0};self.token='a'*64;self.nonce='1'*32;self.events=queue.Queue();self.commands=[]
        common.atomic(self.state/'heartbeat.json',{'ready':True,'phase':'idle','utc':common.utc(),'test':True})

class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.c=FakeController(self.tmp.name)
        self.server=supervisor.LocalHTTP(('127.0.0.1',0),supervisor.make_handler(self.c));self.c.cfg['port']=self.server.server_address[1]
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
    def tearDown(self):self.server.shutdown();self.server.server_close();self.tmp.cleanup()
    def request(self,path,method='GET',auth=False,headers=None,body=None):
        h=dict(headers or {})
        if auth:h['Authorization']='Bearer '+self.c.token
        connection=http.client.HTTPConnection('127.0.0.1',self.c.cfg['port'],timeout=3)
        connection.request(method,path,body=body,headers=h);r=connection.getresponse();data=json.loads(r.read());connection.close();return r.status,data
    def test_health_without_secrets(self):
        status,data=self.request('/healthz');self.assertEqual(status,200);self.assertNotIn('token',str(data));self.assertNotIn('test',data)
    def test_status_requires_auth(self):self.assertEqual(self.request('/v1/status')[0],401)
    def test_status_with_auth(self):self.assertTrue(self.request('/v1/status',auth=True)[1]['test'])
    def test_dns_rebinding_host_denied(self):self.assertEqual(self.request('/healthz',headers={'Host':'attacker.example'})[0],403)
    def test_browser_origin_denied(self):self.assertEqual(self.request('/healthz',headers={'Origin':'https://attacker.example'})[0],403)
    def test_query_token_denied(self):self.assertEqual(self.request('/v1/status?token=abc',auth=True)[0],400)
    def test_unknown_control_denied(self):self.assertEqual(self.request('/v1/control','POST',True,{'Content-Type':'application/json'},'{"command":"shell"}')[0],400)
    def test_arbitrary_extra_control_fields_denied(self):self.assertEqual(self.request('/v1/control','POST',True,{'Content-Type':'application/json'},'{"command":"pause","argv":["rm"]}')[0],400)
    def test_large_body_denied(self):self.assertEqual(self.request('/v1/control','POST',True,{'Content-Type':'application/json'},'x'*1100)[0],400)
    def test_control_requires_auth(self):self.assertEqual(self.request('/v1/control','POST',False,{'Content-Type':'application/json'},'{"command":"pause"}')[0],401)
    def test_real_control_roundtrip(self):
        def consume():
            kind,command,future=self.c.events.get(timeout=3);self.c.commands.append(command);future.set_result({'accepted':True})
        threading.Thread(target=consume).start()
        self.assertTrue(self.request('/v1/control','POST',True,{'Content-Type':'application/json'},'{"command":"pause"}')[1]['accepted'])
        self.assertEqual(self.c.commands,['pause'])

class DummyPolicy:
    @staticmethod
    def allowed(name,tracked):return name.endswith('.py')
    @staticmethod
    def safe_content(name,data,tracked):
        if b'PRIVATE KEY' in data:raise ValueError('secret')

class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.repo=self.root/'repo';self.bare=self.root/'remote.git'
        self.state=self.root/'state';self.state.mkdir();self.checkpoints=self.root/'checkpoints';self.checkpoints.mkdir()
        def cmd(*args):subprocess.run(args,check=True,capture_output=True)
        cmd('git','init','--bare',str(self.bare));cmd('git','init',str(self.repo))
        cmd('git','-C',str(self.repo),'config','user.name','Synthetic QA');cmd('git','-C',str(self.repo),'config','user.email','qa@example.invalid')
        (self.repo/'sample.py').write_text('print("synthetic")\n');cmd('git','-C',str(self.repo),'add','sample.py');cmd('git','-C',str(self.repo),'commit','-m','synthetic')
        cmd('git','-C',str(self.repo),'remote','add','origin',str(self.bare))
        self.cfg={'state':str(self.state),'checkpoints':str(self.checkpoints)}
        self.scope_patch=patch.object(snapshot,'scope',return_value=self.repo);self.scope_patch.start()
        self.policy_patch=patch.object(snapshot,'policy',return_value=DummyPolicy());self.policy_patch.start()
    def tearDown(self):
        self.scope_patch.stop();self.policy_patch.stop()
        # Windows indexing/AV can briefly retain a finished Git process's directory handle.
        # Bounded cleanup retry is not a waiver: persistent sharing violations still fail.
        for attempt in range(8):
            try:self.tmp.cleanup();break
            except PermissionError:
                if attempt==7:raise
                time.sleep(.1*(attempt+1))
    def capture(self):return snapshot.capture(self.cfg,'qa')
    def test_local_capture_works_without_remote(self):
        subprocess.run(['git','-C',str(self.repo),'remote','set-url','origin',str(self.root/'missing')],check=True)
        r=self.capture();self.assertEqual(r['status'],'captured');self.assertTrue(Path(r['archive']).exists())
    def test_touch_does_not_change_content_identity(self):
        a=self.capture();os.utime(self.repo/'sample.py',None);b=self.capture();self.assertEqual(a['fingerprint'],b['fingerprint'])
    def test_private_directories_excluded(self):
        (self.repo/'private').mkdir();(self.repo/'private/secret.py').write_text('PRIVATE KEY')
        r=self.capture();rows,_=snapshot.read_archive(self.cfg,'qa',r['fingerprint'],r['archive_sha256'])
        self.assertFalse(any('private' in name for name,_,_ in rows))
    def test_secret_fails_closed(self):
        (self.repo/'sample.py').write_text('PRIVATE KEY')
        with self.assertRaises(common.GateError):self.capture()
    def test_archive_tamper_blocks_publish(self):
        r=self.capture();Path(r['archive']).write_bytes(b'bad')
        with self.assertRaises(common.GateError):snapshot.publish(self.cfg,'qa',r['fingerprint'],r['archive_sha256'])
    def test_frozen_publish_not_mutable_source(self):
        before=subprocess.check_output(['git','-C',str(self.repo),'rev-parse','HEAD']).strip()
        index=(self.repo/'.git/index').read_bytes();r=self.capture();(self.repo/'sample.py').write_text('newer change')
        result=snapshot.publish(self.cfg,'qa',r['fingerprint'],r['archive_sha256'])
        actual=subprocess.check_output(['git','--git-dir',str(self.bare),'show',result['commit']+':sample.py'])
        self.assertIn(b'synthetic',actual);self.assertEqual(index,(self.repo/'.git/index').read_bytes())
        self.assertEqual(before,subprocess.check_output(['git','-C',str(self.repo),'rev-parse','HEAD']).strip())
    def test_remote_success_is_verified(self):
        r=self.capture();result=snapshot.publish(self.cfg,'qa',r['fingerprint'],r['archive_sha256'])
        self.assertEqual(result['branch'],'refs/heads/checkpoints/wd/qa')
        self.assertEqual(result['commit'],subprocess.check_output(['git','--git-dir',str(self.bare),'rev-parse',result['branch']]).decode().strip())
    def test_crash_after_push_reconciles_without_duplicate(self):
        r=self.capture();a=snapshot.publish(self.cfg,'qa',r['fingerprint'],r['archive_sha256']);(self.checkpoints/'qa.json').unlink()
        b=snapshot.publish(self.cfg,'qa',r['fingerprint'],r['archive_sha256'])
        self.assertEqual(a['commit'],b['commit']);self.assertEqual(b['status'],'reconciled_existing')
    def test_unchanged_capture_never_contacts_remote(self):
        r=self.capture();snapshot.publish(self.cfg,'qa',r['fingerprint'],r['archive_sha256'])
        original=snapshot.safe_git
        def guarded(root,args,*a,**k):
            self.assertNotIn(args[0],['fetch','push','ls-remote']);return original(root,args,*a,**k)
        with patch.object(snapshot,'safe_git',side_effect=guarded):self.assertEqual(self.capture()['status'],'unchanged')
    def test_missing_archive_refused(self):
        with self.assertRaises(common.GateError):snapshot.read_archive(self.cfg,'qa','a'*64,'b'*64)

@unittest.skipUnless(os.name=='nt','Windows native acceptance')
class WindowsNativeTests(unittest.TestCase):
    def test_real_file_change_notification(self):
        with tempfile.TemporaryDirectory() as d:
            seen=queue.Queue();watch=DirectoryWatch(d,lambda name,kind:seen.put((name,kind)));watch.start();self.assertTrue(watch.ready.wait(5))
            try:
                time.sleep(.1)
                (Path(d)/'synthetic.py').write_text('test')
                deadline=time.time()+5;found=False
                while time.time()<deadline:
                    name,kind=seen.get(timeout=5)
                    if name=='synthetic.py':found=True;break
                self.assertTrue(found);self.assertIsNone(watch.failure)
            finally:watch.close()
            self.assertFalse(watch.is_alive())
    def test_job_close_terminates_owned_child(self):
        p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)'],creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            job=ChildJob();job.assign(p);job.close();p.wait(timeout=10);self.assertIsNotNone(p.returncode)
        finally:
            if p.poll() is None:p.kill();p.wait()

if __name__=='__main__':unittest.main()
