import importlib.util,unittest
from pathlib import Path
R=Path(__file__).parents[2]
spec=importlib.util.spec_from_file_location('checkpoints',R/'scripts/github_checkpoint.py');cp=importlib.util.module_from_spec(spec);spec.loader.exec_module(cp)
class ArenaDevTeamGuards(unittest.TestCase):
 def test_team_sources_backed_up(self):
  for n in ['world.ps1','WORLD.EXE.code-workspace','.vscode/tasks.json','DevTeam/config/team.json','DevTeam/README.md','DevTeam/docs/WINDOWS_WORKSTATION.md','DevTeam/src/teamctl.py','DevTeam/tests/test_teamctl.py']:self.assertTrue(cp.allowed(n,False),n)
 def test_private_team_state_never_backed_up(self):
  for n in ['DevTeam/jobs/job.json','DevTeam/src/private/job.py','DevTeam/receipts/result.md','DevTeam/src/secret.p8','DevTeam/src/.env','DevTeam/src/__pycache__/x.pyc','DevTeam/runtime/model.gguf','DevTeam/config/secrets.json','.vscode/settings.json']:self.assertFalse(cp.allowed(n,True),n)
 def test_new_arena_has_no_private_source_imports(self):
  for p in (R/'App/Arena').glob('*.swift'):
   s=p.read_text();self.assertNotIn('PersonalFeedFeature',s);self.assertNotIn('FeedDomain',s);self.assertNotIn('URLSession',s)
 def test_pair_services_are_separate(self):
  self.assertIn('ContactPeer(serviceType:"world-arena")',(R/'App/Arena/ArenaSession.swift').read_text())
  self.assertIn('serviceType: String = ContactPeer.service',(R/'App/Contact/ContactPeer.swift').read_text())
  self.assertIn('_world-arena._tcp',(R/'project.yml').read_text())
 def test_physical_device_gate_is_not_a_launch_argument(self):
  s=(R/'App/Arena/ArenaSession.swift').read_text();self.assertIn('#if targetEnvironment(simulator)',s);self.assertNotIn('arguments.contains',s)
  s=(R/'WorldCore/Sources/WorldCore/ArenaMission.swift').read_text();self.assertIn('iPhone19,2',s);self.assertIn('iPhone19,7',s)
 def test_human_peer_cannot_choose_actor(self):
  s=(R/'App/Arena/ArenaSession.swift').read_text();self.assertIn('state.apply(input,player:"guest")',s)
 def test_camera_lifecycle_and_mesh_are_bounded(self):
  s=(R/'App/Arena/ArenaScene.swift').read_text();self.assertIn('view.session.pause()',s);self.assertIn('meshIDs.count<48',s);self.assertIn('80_000',s)
 def test_candidate_and_release_identity_match(self):
  for n in ['project.yml','scripts/release.sh','scripts/ci.sh']:self.assertIn('0.5.0',(R/n).read_text())
  self.assertIn('refs/heads/main',(R/'scripts/release.sh').read_text())
 def test_scheduled_workflow_has_no_model_or_release_authority(self):
  s=(R/'.github/workflows/devteam.yml').read_text();self.assertIn('contents: read',s);self.assertNotIn('secrets.',s);self.assertNotIn('workflow_dispatch:',s.split('run:',1)[-1]);self.assertNotIn('testflight.yml',s)
if __name__=='__main__':unittest.main()
