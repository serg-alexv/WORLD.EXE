import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('checkpoint', Path(__file__).parents[1] / 'github_checkpoint.py')
checkpoint = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checkpoint)


class CheckpointScopeTests(unittest.TestCase):
    def test_new_source_is_included(self):
        self.assertTrue(checkpoint.allowed('App/NewView.swift', False))
        self.assertTrue(checkpoint.allowed('scripts/tests/test_release_identity.py', False))

    def test_builds_models_and_private_keys_excluded(self):
        for name in ['App/secret.p8', 'App/key.p12', 'App/model.gguf', 'build/log.txt',
                     'LocalLlama/Frameworks/llama.framework/Info.plist', '.git/config',
                     'App/.env', 'App/.env.local', 'scripts/__pycache__/x.pyc']:
            self.assertFalse(checkpoint.allowed(name, True), name)

    def test_outside_paths_excluded(self):
        for name in ['../Rhea/README.md', '/etc/config.json', 'Private/notes.md']:
            self.assertFalse(checkpoint.allowed(name, False), name)

    def test_only_tracked_icon_png_allowed(self):
        self.assertTrue(checkpoint.allowed('App/Assets.xcassets/AppIcon.appiconset/AppIcon.png', True))
        self.assertFalse(checkpoint.allowed('App/Assets.xcassets/photo.png', False))
        self.assertFalse(checkpoint.allowed('docs/photo.png', True))

    def test_detects_private_key_and_token_content(self):
        samples = [b'-----BEGIN ' + b'PRIVATE KEY-----', b'ghp_' + b'A' * 36]
        for data in samples:
            with self.assertRaises(ValueError):
                checkpoint.safe_content('App/Fake.swift', data, False)

    def test_accepts_environment_reference_not_secret(self):
        checkpoint.safe_content('.github/workflows/release.yml',
                                b'key: ${{ secrets.ASC_PRIVATE_KEY_P8_BASE64 }}', True)

    def test_personal_client_code_only(self):
        for name in ['PersonalClient/Core/Package.swift', 'PersonalClient/App/FeedViews.swift',
                     'PersonalClient/Core/Sources/FeedDomain/Models.swift',
                     'PersonalClient/project.yml', 'PersonalClient/App/PrivacyInfo.xcprivacy']:
            self.assertTrue(checkpoint.allowed(name, False), name)
        for name in ['PersonalClient/Imports/hornet.json', 'PersonalClient/App/archive.json',
                     'PersonalClient/Core/Tests/private.csv', 'PersonalClient/App/model.gguf',
                     'PersonalClient/App/PrivateData/content.swift', 'PersonalClient/Generated/Info.plist',
                     'PersonalClient/Core/.build/debug/map.json', 'PersonalClient/App/key.p8']:
            self.assertFalse(checkpoint.allowed(name, True), name)

    def test_size_limit(self):
        with self.assertRaises(ValueError):
            checkpoint.safe_content('App/Large.swift', b'x' * (2 * 1024 * 1024 + 1), True)


if __name__ == '__main__':
    unittest.main()
