import hashlib
import os
from pathlib import Path
import sys
import urllib.request


ARCHIVES = [
    (
        "bazel-skylib-1.9.0.tar.gz",
        "3b5b49006181f5f8ff626ef8ddceaa95e9bb8ad294f7b5d7b11ea9f7ddaf8c59",
        "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.9.0/bazel-skylib-1.9.0.tar.gz",
    ),
    (
        "rules_rust-0.74.0.tar.gz",
        "d8bcc1e111e98270dc03172e22ef7af9c2f94f3269801618a2b83d20890f8df5",
        "https://api.github.com/repos/bazelbuild/rules_rust/releases/assets/534290059",
    ),
]


def populate(directory):
    directory.mkdir(parents=True, exist_ok=True)
    for name, expected, url in ARCHIVES:
        destination = directory / name
        if destination.is_file() and hashlib.sha256(destination.read_bytes()).hexdigest() == expected:
            print("cached " + name, flush=True)
            continue
        temporary = destination.with_suffix(destination.suffix + ".part")
        try:
            request = urllib.request.Request(url, headers={"Accept": "application/octet-stream", "User-Agent": "donutgram-build"})
            digest = hashlib.sha256()
            with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
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
    populate(Path(sys.argv[1]))
