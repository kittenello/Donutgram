import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("cache_dependencies", Path(__file__).resolve().parents[1] / "CacheBazelDependencies.py")
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class CacheBazelDependenciesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.content = b"verified archive"
        self.digest = hashlib.sha256(self.content).hexdigest()
        self.archives = [("archive.tar.gz", self.digest, "https://example.test/archive")]
        self.patch = patch.object(cache, "ARCHIVES", self.archives)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_verified_download_is_reused_without_network(self):
        with patch.object(cache.urllib.request, "urlopen", return_value=io.BytesIO(self.content)) as download:
            cache.populate(self.directory)
            cache.populate(self.directory)
        self.assertEqual(download.call_count, 1)
        self.assertEqual((self.directory / "archive.tar.gz").read_bytes(), self.content)
        self.assertFalse(list(self.directory.glob("*.part")))

    def test_incorrect_checksum_is_not_published(self):
        with patch.object(cache.urllib.request, "urlopen", return_value=io.BytesIO(b"wrong archive")):
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                cache.populate(self.directory)
        self.assertFalse(list(self.directory.iterdir()))

    def test_corrupt_cache_is_replaced(self):
        (self.directory / "archive.tar.gz").write_bytes(b"corrupt")
        with patch.object(cache.urllib.request, "urlopen", return_value=io.BytesIO(self.content)):
            cache.populate(self.directory)
        self.assertEqual((self.directory / "archive.tar.gz").read_bytes(), self.content)


if __name__ == "__main__":
    unittest.main()
