#!/usr/bin/env python3
"""Inspect the actual exported IPA without extracting or modifying its files."""
import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import zipfile


def inspect(path, version, build):
    errors = []
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        infos = [n for n in names if n.startswith('Payload/')
                 and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        if len(infos) != 1:
            raise ValueError('Expected exactly one main app Info.plist in Payload')
        root = infos[0].removesuffix('Info.plist')
        info = plistlib.loads(archive.read(infos[0]))
        expected = {'CFBundleIdentifier': 'com.airlineempire.game',
                    'CFBundleShortVersionString': version,
                    'CFBundleVersion': str(build),
                    'MinimumOSVersion': '17.0',
                    'ITSAppUsesNonExemptEncryption': False}
        for key, wanted in expected.items():
            if info.get(key) != wanted:
                errors.append(f'{key}: expected {wanted!r}, found {info.get(key)!r}')
        if set(info.get('UIDeviceFamily', [])) != {1, 2}:
            errors.append('The shipping app must support iPhone and iPad')
        required_orientations = {'UIInterfaceOrientationPortrait',
                                 'UIInterfaceOrientationPortraitUpsideDown',
                                 'UIInterfaceOrientationLandscapeLeft',
                                 'UIInterfaceOrientationLandscapeRight'}
        ipad = info.get('UISupportedInterfaceOrientations~ipad',
                        info.get('UISupportedInterfaceOrientations', []))
        if not required_orientations.issubset(set(ipad)):
            errors.append('The shipping iPad orientations are incomplete')
        privacy_name = root + 'PrivacyInfo.xcprivacy'
        privacy = plistlib.loads(archive.read(privacy_name)) if privacy_name in names else None
        if privacy is None:
            errors.append('The main app privacy manifest is missing')
        else:
            if privacy.get('NSPrivacyTracking') is not False:
                errors.append('Privacy tracking must explicitly be false')
            if privacy.get('NSPrivacyTrackingDomains', []):
                errors.append('Tracking domains contradict the declared privacy label')
            if privacy.get('NSPrivacyCollectedDataTypes', []):
                errors.append('Collected data types contradict Data Not Collected')
            defaults = [x for x in privacy.get('NSPrivacyAccessedAPITypes', [])
                        if x.get('NSPrivacyAccessedAPIType') == 'NSPrivacyAccessedAPICategoryUserDefaults']
            if len(defaults) != 1 or 'CA92.1' not in defaults[0].get('NSPrivacyAccessedAPITypeReasons', []):
                errors.append('The UserDefaults required-reason declaration is missing')
        test_resources = [n for n in names if n.startswith(root)
                          and (n.endswith('.storekit') or n.endswith('/store-campaign.json')
                               or '.xctest/' in n)]
        if test_resources:
            errors.append('Test-only resources are present in the shipping app')
        return {'sha256': hashlib.sha256(Path(path).read_bytes()).hexdigest(),
                'bundle': {key: info.get(key) for key in expected},
                'minimumOSVersion': info.get('MinimumOSVersion'),
                'deviceFamilies': info.get('UIDeviceFamily'),
                'ipadOrientations': ipad,
                'privacyManifest': privacy,
                'testResources': test_resources,
                'errors': errors, 'passed': not errors,
                'scope': 'Exported bundle inspection; signature/processing and physical-device acceptance are separate.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.ipa, args.version, args.build)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['passed'] else 1)
