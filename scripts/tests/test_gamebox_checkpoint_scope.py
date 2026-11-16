"""Gamebox source recovery must never become a runtime-data backup."""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('checkpoint_gamebox', Path(__file__).parents[1] / 'github_checkpoint.py')
checkpoint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checkpoint)

class GameboxCheckpointScope(unittest.TestCase):
    def test_source_is_included(self):
        for name in ['Gamebox/package.json', 'Gamebox/README.md', 'Gamebox/.gitignore',
                     'Gamebox/config/demo.json', 'Gamebox/config/schedules.json',
                     'Gamebox/src/arena.mjs', 'Gamebox/test/server.test.mjs',
                     'Gamebox/tools/worldctl.mjs', 'Gamebox/docs/ACCEPTANCE.md']:
            self.assertTrue(checkpoint.allowed(name, False), name)

    def test_runtime_and_provider_data_are_excluded_even_when_tracked(self):
        for name in ['Gamebox/state/control.json', 'Gamebox/runtime/events.json',
                     'Gamebox/config/operator.token', 'Gamebox/config/account.json',
                     'Gamebox/src/private.json', 'Gamebox/test/hornet-export.json',
                     'Gamebox/docs/private-screenshot.png', 'Gamebox/.env.local',
                     'Gamebox/node_modules/vendor/index.mjs', 'Gamebox/build/log.txt',
                     'Gamebox/exports/presence.csv', 'Gamebox/../Rhea/file.swift',
                     'WORLD.EXE-ops/fusion-first-external-review.json']:
            self.assertFalse(checkpoint.allowed(name, True), name)

if __name__ == '__main__':
    unittest.main()
