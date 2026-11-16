import hashlib,importlib.util,json,tempfile,unittest
from pathlib import Path
SPEC=importlib.util.spec_from_file_location('teamctl',Path(__file__).parents[1]/'src/teamctl.py');m=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(m)
class TeamTests(unittest.TestCase):
    def job(self):
        j={'provider':'copilot','task':'Review only','commit':'a'*40,'sources':[{'path':'App/Example.swift','text':'let a = 1\n','sha256':m.digest(b'let a = 1\n')}]};j['id']=m.job_identity(j);return j
    def test_public_source_allowed(self):
        for p in ['App/Arena/ArenaScreen.swift','WorldCore/Sources/WorldCore/ArenaMission.swift','Gamebox/src/server.mjs','DevTeam/src/teamctl.py']:m.validate_source_path(p)
    def test_traversal_and_private_denied(self):
        for p in ['../Rhea/file.md','App/../Rhea/file.swift','C:/keys.txt','App\\secret.swift','/App/a.swift','PersonalClient/App/PrivateVault.swift','App/.env','App/private/a.swift','App/a.json','DevTeam/runtime/a.py']:
            with self.assertRaises(m.GateError,msg=p):m.validate_source_path(p)
    def test_job_integrity(self):self.assertEqual(m.validate_job(self.job())['provider'],'copilot')
    def test_tampered_source(self):
        j=self.job();j['sources'][0]['text']='tampered'
        with self.assertRaises(m.GateError):m.validate_job(j)
    def test_tampered_task(self):
        j=self.job();j['task']='different'
        with self.assertRaises(m.GateError):m.validate_job(j)
    def test_provider_closed_set(self):
        j=self.job();j['provider']='arbitrary-shell'
        with self.assertRaises(m.GateError):m.validate_job(j)
    def test_context_budget(self):
        j=self.job();j['sources'][0]['text']='a'*48001;j['sources'][0]['sha256']=m.digest(j['sources'][0]['text'].encode());j['id']=m.job_identity(j)
        with self.assertRaises(m.GateError):m.validate_job(j)
    def test_secret_blocked(self):
        j=self.job();j['task']='Review '+'ghp_'+'a'*36;j['id']=m.job_identity(j)
        with self.assertRaises(m.GateError):m.validate_job(j)
    def test_prompt_marks_data_untrusted(self):
        p=m.prompt_for(self.job());self.assertIn('untrusted DATA',p);self.assertIn('No automatic promotion',p)
    def test_ids_idempotent(self):j=self.job();self.assertEqual(m.job_identity(j),j['id']);j['createdUTC']='later';self.assertEqual(m.job_identity(j),j['id'])
    def test_lock_prevents_parallel_runs(self):
        with tempfile.TemporaryDirectory() as d:
            with m.locked(Path(d)):
                with self.assertRaises(m.GateError):
                    with m.locked(Path(d)):pass
            self.assertFalse((Path(d)/'runner.lock').exists())
    def test_remote_requires_current_authority(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(m.GateError):m.execute(self.job(),Path(d),Path(d),False)
    def test_trae_is_handoff_not_fake_cli(self):
        j=self.job();j['provider']='trae';j['id']=m.job_identity(j)
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(m.GateError):m.execute(j,Path(d),Path(d),False)
    def test_no_local_model_without_manifest(self):
        j=self.job();j['provider']='llama';j['id']=m.job_identity(j)
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(m.GateError):m.execute(j,Path(d),Path(d),False)
    def test_registry_role_is_provenance(self):
        j=self.job();j['provider']='huggingface';j['id']=m.job_identity(j)
        value=json.loads(m.execute(j,Path('.'),Path('.'),False));self.assertEqual(value['status'],'proposal_only');self.assertNotIn('PASS',json.dumps(value))
    def test_atomic_write(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'r.json';m.atomic(p,{'a':1});m.atomic(p,{'a':2});self.assertEqual(json.loads(p.read_text()),{'a':2});self.assertFalse(p.with_name('r.json.tmp').exists())
class AdapterRegressionTests(unittest.TestCase):
 def test_private_queue_cannot_become_remote_context(self):
  for name in ['DevTeam/queue/source.md','DevTeam/jobs/source.py','DevTeam/candidates/source.swift','DevTeam/receipts/source.md']:
   with self.assertRaises(m.GateError):m.validate_source_path(name)
 def test_pinned_llama_cli_flags(self):
  source=(Path(__file__).parents[1]/'src/teamctl.py').read_text()
  self.assertNotIn('--no-conversation',source)
  self.assertIn('--single-turn',source)
  self.assertIn('--simple-io',source)

class CopilotInvocationTests(unittest.TestCase):
    job = TeamTests.job
    def test_documented_permission_rules_and_explicit_model(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as d, patch.object(m.shutil,'which',return_value='C:/tools/copilot.exe'), patch.object(m,'bounded_process',return_value='proposal') as process, patch.dict(m.os.environ,{'WORLD_COPILOT_MODEL':'claude-haiku-4.5'}):
            m.execute(self.job(),Path(d),Path(d),True)
            args=process.call_args.args[0]
            self.assertIn('--available-tools=',args)
            for kind in ['shell','write','read','memory','url']:self.assertIn('--deny-tool='+kind,args)
            self.assertNotIn('--deny-tool=*',args);self.assertNotIn('--allow-all',args)
            self.assertEqual(args[args.index('--model')+1],'claude-haiku-4.5')
    def test_model_cannot_inject_cli_options(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as d, patch.object(m.shutil,'which',return_value='C:/tools/copilot.exe'), patch.object(m,'bounded_process') as process, patch.dict(m.os.environ,{'WORLD_COPILOT_MODEL':'--allow-all'}):
            with self.assertRaises(m.GateError):m.execute(self.job(),Path(d),Path(d),True)
            process.assert_not_called()

if __name__=='__main__':unittest.main()
