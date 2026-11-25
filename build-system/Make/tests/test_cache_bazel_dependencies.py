import hashlib
import importlib.util
import io
import json
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

    def test_verified_download_is_reused_without_network(self):
        with patch.object(cache, "open_archive", return_value=io.BytesIO(self.content)) as download:
            cache.populate(self.directory, self.archives)
            cache.populate(self.directory, self.archives)
        self.assertEqual(download.call_count, 1)
        self.assertEqual((self.directory / "archive.tar.gz").read_bytes(), self.content)
        self.assertFalse(list(self.directory.glob("*.part")))

    def test_incorrect_checksum_is_not_published(self):
        with patch.object(cache, "open_archive", return_value=io.BytesIO(b"wrong archive")):
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                cache.populate(self.directory, self.archives)
        self.assertFalse(list(self.directory.iterdir()))

    def test_corrupt_cache_is_replaced(self):
        (self.directory / "archive.tar.gz").write_bytes(b"corrupt")
        with patch.object(cache, "open_archive", return_value=io.BytesIO(self.content)):
            cache.populate(self.directory, self.archives)
        self.assertEqual((self.directory / "archive.tar.gz").read_bytes(), self.content)

    def test_tampered_registry_metadata_is_rejected(self):
        lock = self.directory / "MODULE.bazel.lock"
        lock.write_text(json.dumps({"registryFileHashes": {"https://example.test/source.json": self.digest}}), encoding="utf-8")
        with patch.object(cache, "open_url", return_value=io.BytesIO(b"changed metadata")):
            with self.assertRaisesRegex(ValueError, "registry checksum mismatch"):
                cache.locked_archives(lock)

    def test_release_api_is_used_when_mirror_is_absent(self):
        url = "https://github.com/owner/repo/releases/download/v1/archive.tar.gz"
        metadata = json.dumps({"assets": [{"name": "archive.tar.gz", "url": "https://api.github.com/repos/owner/repo/releases/assets/123"}]}).encode()
        with patch.object(cache, "open_url", side_effect=[cache.urllib.error.URLError("not mirrored"), io.BytesIO(metadata), io.BytesIO(self.content)]) as download:
            with cache.open_archive(url) as response:
                self.assertEqual(response.read(), self.content)
        self.assertEqual(download.call_args_list[0].args[0], "https://mirror.bazel.build/github.com/owner/repo/releases/download/v1/archive.tar.gz")
        self.assertEqual(download.call_args_list[-1].args[0], "https://api.github.com/repos/owner/repo/releases/assets/123")

    def test_api_token_is_not_forwarded_to_asset_host(self):
        request = cache.urllib.request.Request("https://api.github.com/repos/owner/repo/releases/assets/123", headers={"Authorization": "Bearer test-only-value"})
        redirected = cache.ReleaseRedirectHandler().redirect_request(request, None, 302, "Found", {}, "https://release-assets.githubusercontent.com/archive")
        self.assertIsNone(redirected.get_header("Authorization"))

    def test_identical_filenames_keep_both_versions(self):
        other = b"second version"
        other_digest = hashlib.sha256(other).hexdigest()
        archives = self.archives + [("archive.tar.gz", other_digest, "https://example.test/other")]
        with patch.object(cache, "open_archive", side_effect=[io.BytesIO(self.content), io.BytesIO(other)]):
            cache.populate(self.directory, archives)
        self.assertEqual((self.directory / self.digest / "archive.tar.gz").read_bytes(), self.content)
        self.assertEqual((self.directory / other_digest / "archive.tar.gz").read_bytes(), other)

    def test_best_effort_skips_a_failing_archive_and_keeps_the_rest(self):
        good = b"good archive"
        archives = [("broken.tar.gz", self.digest, "https://example.test/broken"), ("good.tar.gz", hashlib.sha256(good).hexdigest(), "https://example.test/good")]
        with patch.object(cache, "open_archive", side_effect=[cache.urllib.error.URLError("offline"), io.BytesIO(good)]):
            cache.populate(self.directory, archives, strict=False)
        self.assertFalse((self.directory / "broken.tar.gz").exists())
        self.assertEqual((self.directory / "good.tar.gz").read_bytes(), good)
        self.assertFalse(list(self.directory.glob("*.part")))

    def test_best_effort_never_publishes_a_checksum_mismatch(self):
        with patch.object(cache, "open_archive", return_value=io.BytesIO(b"wrong archive")):
            cache.populate(self.directory, self.archives, strict=False)
        self.assertFalse(list(self.directory.iterdir()))

    def test_best_effort_skips_unreachable_registry_metadata(self):
        lock = self.directory / "MODULE.bazel.lock"
        lock.write_text(json.dumps({"registryFileHashes": {"https://example.test/source.json": self.digest}}), encoding="utf-8")
        with patch.object(cache, "open_url", side_effect=cache.urllib.error.URLError("offline")):
            self.assertEqual(cache.locked_archives(lock, strict=False), [])

    def test_declared_host_tools_keep_repository_checksums(self):
        root = Path(__file__).resolve().parents[3]
        archives = cache.declared_archives(root / "MODULE.bazel")
        tools = {name: digest for name, digest, _ in archives}
        self.assertEqual(tools["ninja-mac.zip"], "89a287444b5b3e98f88a945afa50ce937b8ffd1dcc59c555ad9b1baf855298c9")
        self.assertIn("cmake-4.1.2-macos-universal.tar.gz", tools)
        self.assertFalse(any("linux" in name for name in tools))


if __name__ == "__main__":
    unittest.main()
