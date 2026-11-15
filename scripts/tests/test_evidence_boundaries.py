"""Dependency/recording regression guards, in addition to executable Swift tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class EvidenceBoundaryGuards(unittest.TestCase):
    def test_evidence_core_has_no_game_sensor_or_model_dependencies(self):
        for path in (ROOT/'WorldCore/Sources/EvidenceCore').glob('*.swift'):
            imports = [line.strip() for line in path.read_text().splitlines() if line.strip().startswith('import ')]
            self.assertTrue(all(line == 'import Foundation' for line in imports), str(path))
    def test_game_core_does_not_read_observation_journal(self):
        for path in (ROOT/'WorldCore/Sources/WorldCore').glob('*.swift'):
            text = path.read_text()
            for forbidden in ['import EvidenceCore', 'import ARKit', 'import RoomPlan', 'import LocalLlama']:
                self.assertNotIn(forbidden, text, str(path))
    def test_telemetry_sink_has_no_prompt_or_response_argument(self):
        text = (ROOT/'App/Evidence/EvidenceStore.swift').read_text()
        self.assertIn('confirmedBackend: nil', text)
        self.assertNotIn('brain.response', text)
        self.assertNotIn('prompt:', text)
        self.assertNotIn('capturedImage', text)
    def test_live_room_records_distinguish_archive_and_sensor(self):
        text = (ROOT/'App/RoomCaptureModel.swift').read_text()
        self.assertIn('origin: .restoredArchive', text)
        self.assertIn('origin: .localSensor', text)
        self.assertIn('date: record.processedAt', text)
    def test_both_swift_test_targets_are_registered(self):
        package = (ROOT/'WorldCore/Package.swift').read_text()
        project = (ROOT/'project.yml').read_text()
        self.assertIn('.testTarget(name: "EvidenceCoreTests"', package)
        self.assertIn('WorldEXEUnitTests:', project)
        self.assertIn('- name: WorldEXEUnitTests', project)

if __name__ == '__main__': unittest.main()
