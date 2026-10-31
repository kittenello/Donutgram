import datetime
from pathlib import Path
import plistlib
import subprocess
import unittest


PROFILES = Path(__file__).resolve().parents[2] / 'fake-codesigning' / 'profiles'
BUNDLE_SUFFIXES = {
    'Telegram': '',
    'BroadcastUpload': '.BroadcastUpload',
    'Intents': '.SiriIntents',
    'NotificationContent': '.NotificationContent',
    'NotificationService': '.NotificationService',
    'Share': '.Share',
    'WatchApp': '.watchkitapp',
    'WatchExtension': '.watchkitapp.watchkitextension',
    'Widget': '.Widget',
}


def decode_profile(path):
    result = subprocess.run(
        ['openssl', 'cms', '-verify', '-inform', 'DER', '-noverify', '-in', str(path)],
        capture_output=True,
        check=True,
    )
    return plistlib.loads(result.stdout)


class FakeCodesigningProfilesTests(unittest.TestCase):
    def test_profiles_keep_the_expected_application_identifiers(self):
        self.assertEqual({p.stem for p in PROFILES.glob('*.mobileprovision')}, set(BUNDLE_SUFFIXES))
        for name, suffix in BUNDLE_SUFFIXES.items():
            with self.subTest(profile=name):
                profile = decode_profile(PROFILES / (name + '.mobileprovision'))
                self.assertEqual(profile['TeamIdentifier'], ['C67CF9S4VU'])
                self.assertEqual(
                    profile['Entitlements']['application-identifier'],
                    'C67CF9S4VU.ph.telegra.Telegraph' + suffix,
                )

    def test_profiles_and_certificates_have_at_least_thirty_days_left(self):
        deadline = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(days=30)
        for name in BUNDLE_SUFFIXES:
            with self.subTest(profile=name):
                profile = decode_profile(PROFILES / (name + '.mobileprovision'))
                self.assertLessEqual(profile['CreationDate'], deadline - datetime.timedelta(days=30))
                self.assertGreater(profile['ExpirationDate'], deadline)
                self.assertTrue(profile['DeveloperCertificates'])
                for certificate in profile['DeveloperCertificates']:
                    result = subprocess.run(
                        ['openssl', 'x509', '-inform', 'DER', '-noout', '-checkend', str(30 * 24 * 60 * 60)],
                        input=certificate,
                        capture_output=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
