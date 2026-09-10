"""Exercise the upload gate with real zip/plist files and rejected bundles."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    'ipa_inspection', Path(__file__).with_name('inspect-release-ipa.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ExportedAppTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'Airline Empire.ipa'
        self.info = {
            'CFBundleIdentifier': 'com.airlineempire.game',
            'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '5',
            'MinimumOSVersion': '17.0', 'ITSAppUsesNonExemptEncryption': False,
            'UIDeviceFamily': [1, 2],
            'UISupportedInterfaceOrientations~ipad': [
                'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
                'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'],
        }
        self.privacy = plistlib.loads((Path(__file__).resolve().parents[1]
            / 'AirlineEmpireApp/Resources/PrivacyInfo.xcprivacy').read_bytes())

    def inspect(self, *, manifest=True, resource=None):
        root = 'Payload/AirlineEmpire.app/'
        with zipfile.ZipFile(self.path, 'w') as archive:
            archive.writestr(root + 'Info.plist', plistlib.dumps(self.info, fmt=plistlib.FMT_BINARY))
            if manifest:
                archive.writestr(root + 'PrivacyInfo.xcprivacy', plistlib.dumps(self.privacy))
            if resource:
                archive.writestr(root + resource, '{}')
        return module.inspect(self.path, '1.0.0', '5')

    def test_valid_export_and_hash(self):
        result = self.inspect()
        self.assertTrue(result['passed'])
        self.assertEqual(len(result['sha256']), 64)

    def test_wrong_build_is_rejected(self):
        self.info['CFBundleVersion'] = '4'
        self.assertFalse(self.inspect()['passed'])

    def test_missing_privacy_manifest_is_rejected(self):
        self.assertFalse(self.inspect(manifest=False)['passed'])

    def test_tracking_contradiction_is_rejected(self):
        self.privacy['NSPrivacyTracking'] = True
        self.assertFalse(self.inspect()['passed'])

    def test_incomplete_ipad_orientations_are_rejected(self):
        self.info['UISupportedInterfaceOrientations~ipad'].remove('UIInterfaceOrientationPortraitUpsideDown')
        self.assertFalse(self.inspect()['passed'])

    def test_test_resources_are_rejected(self):
        for resource in ['AirlineEmpire.storekit', 'store-campaign.json', 'Tests.xctest/Info.plist']:
            with self.subTest(resource=resource):
                self.assertFalse(self.inspect(resource=resource)['passed'])


if __name__ == '__main__':
    unittest.main()
