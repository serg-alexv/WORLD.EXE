import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('fusion_launch',ROOT/'scripts/fusion_simulator_launch.py')
launch=importlib.util.module_from_spec(spec);spec.loader.exec_module(launch)

class FusionBoundaries(unittest.TestCase):
    def test_feed_is_separate_compilation_module_without_game_dependency(self):
        project=(ROOT/'project.yml').read_text(encoding='utf-8')
        feature=project.split('  PersonalFeedFeature:\n',1)[1].split('  FusionFeedTests:',1)[0]
        self.assertIn('type: library.static',feature)
        for name in ['WorldCore','EvidenceCore','LocalLlama','ARKit','RoomPlan']:self.assertNotIn(name,feature)
        for source in (ROOT/'PersonalClient/App').glob('*.swift'):
            text=source.read_text(encoding='utf-8')
            for name in ['import WorldCore','import EvidenceCore','import LocalLlama','import ARKit','import RoomPlan']:
                self.assertNotIn(name,text,str(source))
    def test_static_feature_products_are_linked_by_the_host(self):
        text=(ROOT/'project.yml').read_text(encoding='utf-8')
        host=text.split('  WorldEXE:\n',1)[1].split('  PersonalFeedFeature:\n',1)[0]
        for product in ['FeedDomain','FeedAdapters','FeedStore']:
            self.assertIn('product: '+product,host)
    def test_host_only_imports_feature_at_workspace_boundary(self):
        for source in (ROOT/'App').rglob('*.swift'):
            text=source.read_text(encoding='utf-8')
            for name in ['import FeedDomain','import FeedAdapters','import FeedStore','FeedSession','PrivateVault']:
                self.assertNotIn(name,text,str(source))
            if source.name!='FusionRootView.swift':self.assertNotIn('import PersonalFeedFeature',text)
    def test_feed_closes_and_does_not_claim_os_isolation(self):
        view=(ROOT/'PersonalClient/App/FeedViews.swift').read_text(encoding='utf-8')
        self.assertIn('.onDisappear { session.lock() }',view)
        self.assertIn('не отдельная песочница iOS',view)
        self.assertIn('presentation == .standalone',view)
    def test_hub_is_default_and_test_shortcut_is_debug_simulator_only(self):
        root=(ROOT/'App/FusionRootView.swift').read_text(encoding='utf-8')
        self.assertIn('@State private var workspace: Workspace = .hub',root)
        guarded=root.split('#if DEBUG && targetEnvironment(simulator)',1)[1].split('#else',1)[0]
        self.assertIn('-ui-testing',guarded);self.assertIn('-fusion-ui-testing',guarded)
        self.assertIn('FusionRootView()', (ROOT/'App/WorldEXEApp.swift').read_text())
    def test_private_switch_waits_for_engine_and_stops_sensors(self):
        source=(ROOT/'App/HomeView.swift').read_text(encoding='utf-8')
        self.assertIn('await brain.unload()',source)
        self.assertIn('guard !brain.isBusy && !brain.isLoaded',source)
        self.assertIn('room.suspendForWorkspaceExit()',source)
        room=(ROOT/'App/RoomCaptureModel.swift').read_text(encoding='utf-8')
        shutdown=room.split('func suspendForWorkspaceExit()',1)[1].split('func reset()',1)[0]
        self.assertIn('contactSession?.pause()',shutdown);self.assertNotIn('removeItem',shutdown)
    def test_real_feature_tests_and_usage_description_are_registered(self):
        project=(ROOT/'project.yml').read_text()
        self.assertIn('NSFaceIDUsageDescription',project)
        self.assertIn('- name: FusionFeedTests',project)
        self.assertIn('sources: [PersonalClient/AppTests]',project)
    def test_known_busy_only_is_retried(self):
        calls=[];sleeps=[]
        results=[SimpleNamespace(returncode=1,stdout='',stderr='FBSOpenApplicationServiceErrorDomain Busy installing or uninstalling'),SimpleNamespace(returncode=0,stdout='launched',stderr='')]
        def run(*a,**k):calls.append(a);return results.pop(0)
        launch.launch('sim','bundle',[],run=run,sleep=sleeps.append)
        self.assertEqual(len(calls),2);self.assertEqual(sleeps,[3])
    def test_unknown_launch_error_remains_failure(self):
        def run(*a,**k):return SimpleNamespace(returncode=1,stdout='',stderr='Application crashed')
        with self.assertRaises(RuntimeError):launch.launch('sim','bundle',[],run=run,sleep=lambda _:self.fail('Must not retry crash'))
    def test_busy_retry_is_bounded(self):
        calls=[]
        def run(*a,**k):calls.append(a);return SimpleNamespace(returncode=1,stdout='',stderr='FBSOpenApplicationServiceErrorDomain Busy installing or uninstalling')
        with self.assertRaises(RuntimeError):launch.launch('sim','bundle',[],run=run,sleep=lambda _:None)
        self.assertEqual(len(calls),4)

if __name__=='__main__':unittest.main()
