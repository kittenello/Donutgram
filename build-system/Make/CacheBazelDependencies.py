import hashlib
import base64
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


class ReleaseRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        redirected = super().redirect_request(request, response, code, message, headers, new_url)
        if redirected is not None and urllib.parse.urlparse(new_url).hostname != urllib.parse.urlparse(request.full_url).hostname:
            redirected.remove_header("Authorization")
        return redirected


def open_url(url):
    accept = "application/octet-stream" if "/releases/assets/" in url else "*/*"
    request = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "donutgram-build"})
    if urllib.parse.urlparse(url).hostname == "api.github.com" and os.environ.get("GITHUB_TOKEN"):
        request.add_header("Authorization", "Bearer " + os.environ["GITHUB_TOKEN"])
    return urllib.request.build_opener(ReleaseRedirectHandler()).open(request, timeout=120)


def open_archive(url):
    release = re.fullmatch(r"https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^/?]+)", url)
    if release is None:
        return open_url(url)
    try:
        return open_url(url.replace("https://github.com/", "https://mirror.bazel.build/github.com/", 1))
    except (urllib.error.URLError, TimeoutError):
        owner, repository, tag, name = release.groups()
        with open_url(f"https://api.github.com/repos/{owner}/{repository}/releases/tags/{tag}") as response:
            metadata = json.load(response)
        asset = next(asset for asset in metadata["assets"] if asset["name"] == urllib.parse.unquote(name))
        return open_url(asset["url"])


def locked_archives(lock_path):
    lock = json.loads(lock_path.read_text(encoding="utf-8"))

    def resolve(item):
        url, expected = item
        with open_url(url) as response:
            content = response.read()
        if hashlib.sha256(content).hexdigest() != expected:
            raise ValueError("registry checksum mismatch: " + url)
        source = json.loads(content)
        archive_url = source.get("url")
        if not archive_url or not source["integrity"].startswith("sha256-"):
            return None
        digest = base64.b64decode(source["integrity"][7:], validate=True).hex()
        return Path(urllib.parse.urlparse(archive_url).path).name, digest, archive_url

    sources = [(url, digest) for url, digest in lock["registryFileHashes"].items() if url.endswith("/source.json")]
    with ThreadPoolExecutor(max_workers=4) as pool:
        return [archive for archive in pool.map(resolve, sources) if archive is not None]


def populate(directory, archives):
    directory.mkdir(parents=True, exist_ok=True)
    for name, expected, url in archives:
        destination = directory / name
        if destination.is_file() and hashlib.sha256(destination.read_bytes()).hexdigest() == expected:
            print("cached " + name, flush=True)
            continue
        temporary = destination.with_suffix(destination.suffix + ".part")
        try:
            digest = hashlib.sha256()
            with open_archive(url) as response, temporary.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    digest.update(chunk)
                    output.write(chunk)
            if digest.hexdigest() != expected:
                raise ValueError("archive checksum mismatch: " + name)
            os.replace(temporary, destination)
            print("cached " + name, flush=True)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    populate(Path(sys.argv[1]), locked_archives(Path(__file__).resolve().parents[2] / "MODULE.bazel.lock"))
