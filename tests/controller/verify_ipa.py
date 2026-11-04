#!/usr/bin/env python3
"""Inspect a built IPA; no installation or game-directory access.
Usage: verify_ipa.py Air.ipa output-directory [--baseline-ipa existing-base.ipa]
"""
import argparse
import hashlib
import io
import json
import pathlib
import plistlib
import struct
import subprocess
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('ipa', type=pathlib.Path)
parser.add_argument('output', type=pathlib.Path)
parser.add_argument('--baseline-ipa', type=pathlib.Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

def binary_details(data):
    assert data[:4] == b'\xcf\xfa\xed\xfe', 'Expected thin little-endian Mach-O 64'
    assert struct.unpack_from('<I', data, 4)[0] == 0x100000C, 'Expected ARM64'
    offset = 32
    result = {'architecture': 'arm64', 'entitlements': {}}
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 0x32:
            platform, minimum, sdk = struct.unpack_from('<III', data, offset + 8)
            result.update(platform=platform, minimum_os=minimum, sdk=sdk)
        if command == 0x1D:
            sig_offset, sig_size = struct.unpack_from('<II', data, offset + 8)
            signature = data[sig_offset:sig_offset + sig_size]
            magic, _, count = struct.unpack_from('>III', signature)
            assert magic == 0xFADE0CC0, 'Expected embedded signature superblob'
            for i in range(count):
                slot, blob_offset = struct.unpack_from('>II', signature, 12 + 8 * i)
                if slot == 5:
                    _, length = struct.unpack_from('>II', signature, blob_offset)
                    result['entitlements'] = plistlib.loads(signature[blob_offset + 8:blob_offset + length])
        offset += size
    assert result.get('platform') == 2, 'Expected iOS device platform, not macOS or simulator'
    return result

def app_paths(archive):
    info = next(n for n in archive.namelist() if n.endswith('.app/Info.plist') and n.count('/') == 2)
    prefix = info[:-len('Info.plist')]
    plist = plistlib.loads(archive.read(info))
    return prefix, plist, prefix + plist['CFBundleExecutable']

def class_packages(data):
    with zipfile.ZipFile(io.BytesIO(data)) as jar:
        return {n.rsplit('/', 1)[0] for n in jar.namelist()
                if n.endswith('.class') and '/' in n and not n.startswith('META-INF/')}

with zipfile.ZipFile(args.ipa) as archive:
    prefix, info, executable = app_paths(archive)
    native = archive.read(executable)
    report = {'sha256': hashlib.sha256(args.ipa.read_bytes()).hexdigest(),
              'bundle_id': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
              'native': binary_details(native), 'jars': {}}
    assert report['bundle_id'] == 'com.air-devs.air' and report['version'] == '5.1.0'
    binary = args.output / 'AngelAuraAmethyst'
    binary.write_bytes(native)
    symbols = subprocess.check_output(['nm', '-gU', str(binary)], text=True)
    symbol = '_Java_org_lwjgl_glfw_GamepadBridge_nativeSnapshot'
    assert symbol in symbols, 'Missing exported JNI entry point'
    report['native']['jni_symbol'] = symbol
    common = {}
    for name in archive.namelist():
        if name.startswith(prefix + 'libs/') and name.endswith('.jar'):
            relative = name[len(prefix + 'libs/'):]
            dest = args.output / 'libs' / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(archive.read(name))
            if '/' not in relative:
                assert not relative.startswith('lwjgl'), 'Flat LWJGL jar alongside selected variants'
                common[relative] = class_packages(dest.read_bytes())
    for version in ['333', '341']:
        path = args.output / 'libs' / ('lwjgl-' + version) / 'lwjgl.jar'
        packages = class_packages(path.read_bytes())
        assert not {name: packages & p for name, p in common.items() if packages & p}, 'JPMS split package'
        with zipfile.ZipFile(path) as jar:
            for name in ['GLFW', 'GamepadBridge', 'GamepadBridge$Source', 'GamepadBridge$Listener']:
                data = jar.read('org/lwjgl/glfw/' + name + '.class')
                assert data[:4] == b'\xca\xfe\xba\xbe' and struct.unpack_from('>H', data, 6)[0] == 52
            assert b'AIC event bus controller' not in jar.read('org/lwjgl/glfw/GLFW.class'), 'Old phantom stub packaged'
            assert 'org/lwjgl/system/Struct.class' in jar.namelist()
        report['jars'][version] = {'bridge': True, 'java_major': 52, 'split_packages': False}
    if args.baseline_ipa:
        with zipfile.ZipFile(args.baseline_ipa) as baseline:
            bp, bi, be = app_paths(baseline)
            assert bi['CFBundleIdentifier'] == info['CFBundleIdentifier']
            assert binary_details(baseline.read(be))['entitlements'] == report['native']['entitlements'], 'Changed signing entitlements'
            frameworks = lambda z, p: {n[len(p):] for n in z.namelist() if n.startswith(p + 'Frameworks/')}
            assert frameworks(archive, prefix) == frameworks(baseline, bp), 'Changed framework inventory'
            report['baseline'] = {'same_bundle_id': True, 'same_entitlements': True, 'same_framework_inventory': True}
print(json.dumps(report, indent=2))
