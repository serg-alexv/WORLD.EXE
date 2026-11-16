import importlib.util
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('identity', Path(__file__).parents[1] / 'verify_app_identity.py')
identity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(identity)


class ReleaseIdentityTests(unittest.TestCase):
    def setUp(self):
        self.info = {'CFBundleIdentifier': 'org.worldexe.prototype',
                     'CFBundleShortVersionString': '0.2.0', 'CFBundleVersion': '5.1'}

    def test_accepts_exact_identity(self):
        self.assertTrue(identity.verify(self.info, '0.2.0', '5.1', 'org.worldexe.prototype')['identity_verified'])

    def test_rejects_xcodegen_default_version(self):
        self.info['CFBundleShortVersionString'] = '1.0'
        with self.assertRaises(ValueError):
            identity.verify(self.info, '0.2.0', '5.1', 'org.worldexe.prototype')

    def test_rejects_default_build(self):
        self.info['CFBundleVersion'] = '1'
        with self.assertRaises(ValueError):
            identity.verify(self.info, '0.2.0', '5.1', 'org.worldexe.prototype')

    def test_rejects_other_bundle(self):
        self.info['CFBundleIdentifier'] = 'org.example.unrelated'
        with self.assertRaises(ValueError):
            identity.verify(self.info, '0.2.0', '5.1', 'org.worldexe.prototype')

    def test_rejects_unexpanded_build_setting(self):
        self.info['CFBundleVersion'] = '$(CURRENT_PROJECT_VERSION)'
        with self.assertRaises(ValueError):
            identity.verify(self.info, '0.2.0', '5.1', 'org.worldexe.prototype')

    def test_reads_app(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'WorldEXE.app'
            root.mkdir()
            (root / 'Info.plist').write_bytes(plistlib.dumps(self.info))
            self.assertEqual(identity.read_identity(root), self.info)

    def test_reads_only_root_app_from_ipa(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'WorldEXE.ipa'
            with zipfile.ZipFile(path, 'w') as z:
                z.writestr('Payload/WorldEXE.app/Info.plist', plistlib.dumps(self.info))
                z.writestr('Payload/WorldEXE.app/Frameworks/llama.framework/Info.plist', plistlib.dumps({'CFBundleVersion':'1'}))
            self.assertEqual(identity.read_identity(path), self.info)

    def test_rejects_ambiguous_ipa(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'WorldEXE.ipa'
            with zipfile.ZipFile(path, 'w') as z:
                for name in ['One', 'Two']:
                    z.writestr(f'Payload/{name}.app/Info.plist', plistlib.dumps(self.info))
            with self.assertRaises(ValueError):
                identity.read_identity(path)


if __name__ == '__main__':
    unittest.main()
