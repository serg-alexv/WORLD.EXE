"""Synthetic Mach-O fixtures; no provision or real executable is stored."""
import importlib.util
import plistlib
import struct
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('feed_macho', Path(__file__).parents[1]/'verify_feed_simulator.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def binary(identity=m.IDENTITY, groups=None):
    p = {'application-identifier': identity, 'keychain-access-groups': groups if groups is not None else [identity]}
    payload=plistlib.dumps(p)
    segment_size=72+80; offset=32+segment_size
    header=struct.pack('<IIIIIIII',0xfeedfacf,0x0100000c,0,2,1,segment_size,0,0)
    segment=struct.pack('<II16sQQQQiiII',0x19,segment_size,b'__TEXT',0,len(payload),offset,len(payload),7,5,1,0)
    section=struct.pack('<16s16sQQIIIIIIII',b'__entitlements',b'__TEXT',0,len(payload),offset,0,0,0,0,0,0,0)
    return header+segment+section+payload

class SimulatorIdentityTests(unittest.TestCase):
    def test_exact_embedded_identity(self):
        self.assertEqual(m.embedded(binary())[0]['application-identifier'],m.IDENTITY)
    def test_wrong_app_rejected(self):
        with self.assertRaises(ValueError):m.embedded(binary('398XACWZ7G.other'))
    def test_shared_group_rejected(self):
        with self.assertRaises(ValueError):m.embedded(binary(groups=[m.IDENTITY,'398XACWZ7G.other']))
    def test_wildcard_rejected(self):
        with self.assertRaises(ValueError):m.embedded(binary(groups=['398XACWZ7G.*']))
    def test_section_length_cannot_escape_file(self):
        data=bytearray(binary());struct.pack_into('<Q',data,32+72+40,999999)
        with self.assertRaises(ValueError):m.embedded(bytes(data))
    def test_truncated_command_rejected(self):
        data=bytearray(binary());struct.pack_into('<I',data,32+4,4)
        with self.assertRaises(ValueError):m.embedded(bytes(data))
    def test_missing_section_rejected(self):
        data=bytearray(binary());data[104:120]=b'__other'.ljust(16,b'\0')
        with self.assertRaises(ValueError):m.embedded(bytes(data))
    def test_fat_binary_validates_both_architectures(self):
        part=binary();start=8+40
        header=struct.pack('>II',0xcafebabe,2)
        table=struct.pack('>IIIII',0x0100000c,0,start,len(part),0)+struct.pack('>IIIII',0x01000007,0,start+len(part),len(part),0)
        self.assertEqual(len(m.embedded(header+table+part+part)),2)
    def test_corrupt_fat_slice_rejected(self):
        with self.assertRaises(ValueError):m.embedded(struct.pack('>II',0xcafebabe,20)+bytes(40))

if __name__=='__main__':unittest.main()
