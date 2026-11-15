"""Synthetic Mach-O fixtures only; no app binary or private data in source."""
import importlib.util
import plistlib
import struct
import unittest
from pathlib import Path

p=Path(__file__).resolve().parents[1]/'verify_personal_feed_simulator.py'
spec=importlib.util.spec_from_file_location('personal_simulator_guard',p)
guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)


def fixture(properties=None):
    props={'application-identifier':guard.IDENTITY,'keychain-access-groups':[guard.IDENTITY]} if properties is None else properties
    payload=plistlib.dumps(props)
    offset=32+72+80
    header=struct.pack('<8I',0xfeedfacf,0x0100000c,0,2,1,152,0,0)
    segment=struct.pack('<II16sQQQQIIII',0x19,152,b'__TEXT',0,4096,0,offset+len(payload),5,5,1,0)
    section=struct.pack('<16s16sQQIIIIIIII',b'__entitlements',b'__TEXT',offset,len(payload),offset,0,0,0,0,0,0,0)
    return header+segment+section+payload


class PersonalSimulatorIdentity(unittest.TestCase):
    def test_reads_actual_embedded_identity(self):
        values=guard.extract(fixture())
        self.assertEqual(values[0]['application-identifier'],guard.IDENTITY)
    def test_rejects_wrong_identity(self):
        with self.assertRaises(ValueError):guard.extract(fixture({'application-identifier':'other'}))
    def test_rejects_shared_keychain_group(self):
        with self.assertRaises(ValueError):guard.extract(fixture({'application-identifier':guard.IDENTITY,'keychain-access-groups':['shared']}))
    def test_rejects_app_groups(self):
        props={'application-identifier':guard.IDENTITY,'keychain-access-groups':[guard.IDENTITY],'com.apple.security.application-groups':['group.shared']}
        with self.assertRaises(ValueError):guard.extract(fixture(props))
    def test_rejects_truncated_slice(self):
        with self.assertRaises(ValueError):guard.extract(fixture()[:80])
    def test_checks_all_universal_slices(self):
        first=fixture();second=fixture()
        header=struct.pack('>II',0xcafebabe,2)
        header+=struct.pack('>5I',0x0100000c,0,48,len(first),0)
        header+=struct.pack('>5I',0x01000007,0,48+len(first),len(second),0)
        self.assertEqual(len(guard.extract(header+first+second)),2)
    def test_rejects_universal_oob(self):
        data=struct.pack('>II5I',0xcafebabe,1,0x0100000c,0,3000,100,0)
        with self.assertRaises(ValueError):guard.extract(data)


if __name__=='__main__':unittest.main()
