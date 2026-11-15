#!/usr/bin/env python3
"""Read Xcode's simulator-only embedded entitlements, not macOS signature entitlements.
Xcode places iOS simulator identity in __TEXT,__entitlements; the host ad-hoc
signature can legitimately have an empty dictionary. This verifier never edits a binary.
"""
import argparse
import plistlib
import struct
from pathlib import Path

IDENTITY = '398XACWZ7G.org.worldexe.personalfeed'


def thin_sections(data: bytes) -> list[bytes]:
    if len(data) < 32 or data[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected a little-endian 64-bit Mach-O simulator slice')
    count, commands_size = struct.unpack_from('<II', data, 16)
    if count > 4096 or commands_size > len(data) - 32:
        raise ValueError('Invalid Mach-O command bounds')
    position = 32
    found = []
    for _ in range(count):
        if position + 8 > 32 + commands_size:
            raise ValueError('Truncated load command')
        command, size = struct.unpack_from('<II', data, position)
        if size < 8 or position + size > 32 + commands_size:
            raise ValueError('Invalid load command length')
        if command == 0x19:
            if size < 72:
                raise ValueError('Truncated segment')
            sections = struct.unpack_from('<I', data, position + 64)[0]
            if sections > (size - 72) // 80:
                raise ValueError('Invalid section bounds')
            for i in range(sections):
                s = position + 72 + 80 * i
                name = data[s:s+16].rstrip(b'\0')
                segment = data[s+16:s+32].rstrip(b'\0')
                if name == b'__entitlements' and segment == b'__TEXT':
                    length = struct.unpack_from('<Q', data, s + 40)[0]
                    offset = struct.unpack_from('<I', data, s + 48)[0]
                    if length < 1 or length > 1024 * 1024 or offset > len(data) or length > len(data)-offset:
                        raise ValueError('Invalid embedded-entitlement bounds')
                    found.append(data[offset:offset+length].rstrip(b'\0'))
        position += size
    if position != 32 + commands_size or len(found) != 1:
        raise ValueError('Expected exactly one embedded simulator entitlement dictionary')
    return found


def extract(data: bytes) -> list[dict]:
    if len(data) > 128 * 1024 * 1024:
        raise ValueError('Executable exceeds validation bound')
    magic = data[:4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        if len(data) < 8:
            raise ValueError('Truncated universal header')
        count = struct.unpack_from('>I', data, 4)[0]
        size = 32 if magic[-1] == 0xbf else 20
        if not 1 <= count <= 8 or 8 + count * size > len(data):
            raise ValueError('Invalid universal architecture count')
        slices = []
        for i in range(count):
            p = 8 + i * size
            offset, length = struct.unpack_from('>QQ' if size == 32 else '>II', data, p + 8)
            if offset < 8 + count * size or offset > len(data) or length > len(data) - offset:
                raise ValueError('Invalid universal slice bounds')
            slices.extend(thin_sections(data[offset:offset+length]))
    else:
        slices = thin_sections(data)
    values = [plistlib.loads(raw) for raw in slices]
    for value in values:
        if value.get('application-identifier') != IDENTITY:
            raise ValueError('Wrong embedded simulator application identity')
        if value.get('keychain-access-groups') != [IDENTITY]:
            raise ValueError('Unexpected simulator Keychain access group')
        if value.get('com.apple.security.application-groups'):
            raise ValueError('Personal client must not share an App Group')
    return values


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.executable.stat().st_size > 128 * 1024 * 1024:
        parser.exit(2, 'Oversized executable\n')
    try:
        values = extract(args.executable.read_bytes())
        args.output.write_bytes(plistlib.dumps(values[0]))
    except (ValueError, struct.error, plistlib.InvalidFileException) as error:
        parser.exit(2, f'Simulator identity validation failed: {error}\n')
    print(f'Verified embedded simulator Keychain identity in {len(values)} architecture slice(s).')


if __name__ == '__main__':
    main()
