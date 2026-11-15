#!/usr/bin/env python3
"""Verify actual app/IPA identity before claiming or uploading a release."""
import argparse
import json
import plistlib
import zipfile
from pathlib import Path


def read_identity(path: Path) -> dict:
    if path.is_dir():
        return plistlib.loads((path / 'Info.plist').read_bytes())
    if path.suffix.lower() != '.ipa':
        raise ValueError('Expected an .app directory or a signed .ipa file')
    with zipfile.ZipFile(path) as archive:
        candidates = [n for n in archive.namelist() if n.startswith('Payload/')
                      and n.endswith('.app/Info.plist') and n.count('/') == 2]
        if len(candidates) != 1:
            raise ValueError('IPA must contain exactly one root application Info.plist')
        return plistlib.loads(archive.read(candidates[0]))


def verify(info: dict, version: str, build: str, bundle: str) -> dict:
    expected = {'CFBundleIdentifier': bundle, 'CFBundleShortVersionString': version,
                'CFBundleVersion': build}
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f'{key}: expected {value!r}, actual {info.get(key)!r}; release stopped')
    return {'bundle': bundle, 'version': version, 'build': build, 'identity_verified': True}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--bundle', default='org.worldexe.prototype')
    args = parser.parse_args()
    try:
        receipt = verify(read_identity(args.path), args.version, args.build, args.bundle)
    except (ValueError, OSError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        parser.exit(2, f'App identity verification failed: {error}\n')
    print(json.dumps(receipt, sort_keys=True))


if __name__ == '__main__':
    main()
