"""Validate the built Simulator binary's embedded entitlement section, not device signing.
Xcode's link log embeds *-Simulated.xcent into __TEXT,__entitlements.
Real Keychain round-trip/UI tests remain mandatory after this structural guard.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import plistlib
import struct
from pathlib import Path

IDENTITY = '398XACWZ7G.org.worldexe.personalfeed'

def require(condition: bool, message: str) -> None:
    if not condition: raise ValueError(message)

def slices(data: bytes) -> list[bytes]:
    require(32 <= len(data) <= 256 * 1024 * 1024, 'Invalid binary size')
    if data[:4] not in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        return [data]
    wide = data[:4] == b'\xca\xfe\xba\xbf'
    count = struct.unpack_from('>I', data, 4)[0]
    stride = 32 if wide else 20
    require(1 <= count <= 16 and 8 + count * stride <= len(data), 'Invalid fat architecture table')
    result = []
    for i in range(count):
        p = 8 + i * stride
        offset, size = struct.unpack_from('>QQ' if wide else '>II', data, p + 8)
        require(offset >= 8 + count * stride and size >= 32 and offset + size <= len(data), 'Invalid fat slice bounds')
        result.append(data[offset:offset + size])
    return result

def embedded(data: bytes) -> list[dict]:
    result = []
    for part in slices(data):
        require(part[:4] == b'\xcf\xfa\xed\xfe', 'Expected little-endian 64-bit Mach-O simulator slice')
        commands, command_bytes = struct.unpack_from('<II', part, 16)
        require(commands <= 4096 and 32 + command_bytes <= len(part), 'Invalid Mach-O load commands')
        position, found = 32, []
        for _ in range(commands):
            require(position + 8 <= 32 + command_bytes, 'Truncated load command')
            command, size = struct.unpack_from('<II', part, position)
            require(size >= 8 and position + size <= 32 + command_bytes, 'Invalid load command size')
            if command == 0x19:  # LC_SEGMENT_64
                require(size >= 72, 'Truncated segment')
                nsections = struct.unpack_from('<I', part, position + 64)[0]
                require(nsections <= 4096 and 72 + nsections * 80 <= size, 'Invalid section table')
                for n in range(nsections):
                    section = position + 72 + n * 80
                    name = part[section:section+16].split(b'\0', 1)[0]
                    segment = part[section+16:section+32].split(b'\0', 1)[0]
                    if name == b'__entitlements' and segment == b'__TEXT':
                        length = struct.unpack_from('<Q', part, section+40)[0]
                        offset = struct.unpack_from('<I', part, section+48)[0]
                        require(0 < length <= 1024*1024 and offset+length <= len(part), 'Invalid entitlement bounds')
                        value = plistlib.loads(part[offset:offset+length].rstrip(b'\0'))
                        require(isinstance(value, dict), 'Entitlements are not a dictionary')
                        found.append(value)
            position += size
        require(position == 32 + command_bytes, 'Load command size mismatch')
        require(len(found) == 1, 'Each simulator slice must contain exactly one entitlement section')
        value = found[0]
        require(value.get('application-identifier') == IDENTITY, 'Wrong simulator application identity')
        require(value.get('keychain-access-groups') == [IDENTITY], 'Wrong or shared Keychain group')
        require(not value.get('com.apple.security.application-groups'), 'Unexpected shared app container')
        result.append(value)
    return result

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    try:
        require(args.binary.stat().st_size <= 256*1024*1024, 'Binary too large')
        data = args.binary.read_bytes(); values = embedded(data)
        receipt = {'binarySHA256': hashlib.sha256(data).hexdigest(), 'simulatorSlices': len(values),
                   'applicationIdentifier': IDENTITY, 'embeddedIdentityVerified': True,
                   'scope': 'Simulator binary only; not a device provisioning or Keychain runtime result'}
        args.receipt.write_text(json.dumps(receipt, indent=2), encoding='utf-8')
        print(json.dumps(receipt))
    except (ValueError, OSError, struct.error, plistlib.InvalidFileException) as error:
        parser.exit(2, f'Simulator identity validation failed: {error}\n')

if __name__ == '__main__': main()
