"""Source-only boundary guards. Runtime tests live in the isolated Swift package and iOS targets."""
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / 'PersonalClient'

class PersonalFeedBoundaries(unittest.TestCase):
    def test_personal_core_never_imports_game_sensor_model_or_network(self):
        for f in (CLIENT/'Core/Sources').rglob('*.swift'):
            text=f.read_text()
            for banned in ['import WorldCore', 'import EvidenceCore', 'import ARKit', 'import RoomPlan', 'import LocalLlama', 'import UIKit', 'URLSession']:
                self.assertNotIn(banned,text,str(f))
    def test_target_has_separate_bundle_no_app_group_or_camera(self):
        text=(CLIENT/'project.yml').read_text()
        self.assertIn('org.worldexe.personalfeed',text)
        for forbidden in ['org.worldexe.prototype','NSCameraUsageDescription','NSMicrophoneUsageDescription','com.apple.security.application-groups','LocalLlama','WorldCore']:
            self.assertNotIn(forbidden,text)
    def test_keychain_fixture_identity_is_simulator_only(self):
        project=(CLIENT/'project.yml').read_text()
        self.assertIn('"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": Generated/Simulator.entitlements',project)
        self.assertEqual(project.count('CODE_SIGN_ENTITLEMENTS'),1)
        script=(ROOT/'scripts/personal_feed_ci.sh').read_text()
        self.assertIn("'keychain-access-groups':['398XACWZ7G.org.worldexe.personalfeed']",script)
        self.assertNotIn("'keychain-access-groups':['*']",script)
        self.assertIn('testRealKeychainRoundTripUsesDistinctTestService',(CLIENT/'AppTests/PersonalFeedTests.swift').read_text())
    def test_no_content_logs(self):
        for f in (CLIENT/'App').rglob('*.swift'):
            text=f.read_text()
            for forbidden in ['print(', 'NSLog(', 'Logger(', 'OSLog(']: self.assertNotIn(forbidden,text,str(f))
    def test_storage_and_key_protection_are_explicit(self):
        text=(CLIENT/'App/PrivateVault.swift').read_text()
        for required in ['AES.GCM.seal','AES.GCM.open','kSecAttrAccessibleWhenUnlockedThisDeviceOnly','completeFileProtection','isExcludedFromBackup = true']:
            self.assertIn(required,text)
    def test_no_fake_hornet_endpoint(self):
        for f in (CLIENT/'App').rglob('*.swift'):
            text=f.read_text()
            self.assertNotIn('api.hornet',text)
            self.assertNotIn('api.grindr',text)
            self.assertNotIn('Bearer ',text)
    def test_auth_bypass_only_debug_simulator(self):
        text=(CLIENT/'App/FeedSession.swift').read_text()
        start=text.index('#if DEBUG && targetEnvironment(simulator)')
        stop=text.index('#endif',start)
        self.assertIn('-feed-ui-testing',text[start:stop])
        self.assertEqual(text.count('-feed-ui-testing'),1)
    def test_transport_has_no_cookies_and_does_not_follow_redirect(self):
        text=(CLIENT/'App/FeedTransport.swift').read_text()
        self.assertIn('config.httpCookieStorage = nil',text)
        self.assertIn('config.urlCredentialStorage = nil',text)
        self.assertIn('completionHandler(nil)',text)
        self.assertIn('ImportTable.maxBytes - data.count',text)
    def test_fixtures_are_synthetic(self):
        text=(CLIENT/'Core/Sources/FeedStore/SyntheticDemo.swift').read_text()
        self.assertIn('provider: .demonstration',text)
        self.assertIn('acquisition: .syntheticDemo',text)
        self.assertNotIn('provider: .hornet',text)
    def test_workflow_does_not_use_signing_secrets(self):
        text=(ROOT/'.github/workflows/personal-feed.yml').read_text()
        self.assertNotIn('secrets.',text)
        self.assertNotIn('pull_request_target',text)
        self.assertNotIn('PrivateData',text)

if __name__=='__main__': unittest.main()
