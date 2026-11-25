"""Builds the plugin runtime's C/C++ suites with the host compiler and runs them under run_watchdog.py.

The same steps as run-tests.ps1 (Windows, Visual Studio clang), for macOS CI and any clang or gcc: the engine
checksums in engine-lock.json, the bootstrap embedded in DGPluginBootstrap.swift, the regression and isolated
native-work scenarios against the production C host, and the engine's own default-policy suites.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1]
ROOT = RUNTIME.parents[1]
ENGINE_SOURCES = ["quickjs", "dtoa", "libregexp", "libunicode"]


def check_engine_lock():
    lock = json.loads((RUNTIME / "engine-lock.json").read_text(encoding="utf-8"))
    for name, expected in lock["files"].items():
        data = (ROOT / name).read_bytes().replace(b"\r\n", b"\n")
        if hashlib.sha256(data).hexdigest() != expected:
            raise SystemExit("engine checksum mismatch: " + name)


def check_bootstrap():
    bootstrap = (RUNTIME / "Sources/bootstrap.js").read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n")
    embedded = (RUNTIME / "Sources/DGPluginBootstrap.swift").read_text(encoding="utf-8").replace("\r\n", "\n")
    if bootstrap not in embedded:
        raise SystemExit("the bootstrap embedded in DGPluginBootstrap.swift differs from bootstrap.js")


def run(command):
    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, check=True, cwd=ROOT)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", help="directory for objects and executables (a temporary one by default)")
    parser.add_argument("--skip", action="append", default=[], help="a native-work scenario to leave out")
    args = parser.parse_args()
    cc = os.environ.get("CC") or shutil.which("clang") or shutil.which("gcc")
    cxx = os.environ.get("CXX") or shutil.which("clang++") or shutil.which("g++")
    if not cc or not cxx:
        raise SystemExit("a C and a C++ compiler are required")
    check_engine_lock()
    check_bootstrap()
    build = Path(args.build) if args.build else Path(tempfile.mkdtemp(prefix="donutgram-plugin-runtime-"))
    build.mkdir(parents=True, exist_ok=True)
    suffix = ".exe" if os.name == "nt" else ""
    # The fixtures recurse to the engine's 512 KiB limit on the main thread; Windows' default is only 1 MiB.
    stack = ["-Wl,--stack,8388608"] if os.name == "nt" else []
    libraries = [] if os.name == "nt" else ["-lm", "-lpthread"]
    objects = []
    for source in ENGINE_SOURCES:
        output = build / (source + ".o")
        run([cc, "-c", "-O2", "-DQUICKJS_NG_BUILD", "-Ithird-party/quickjs-ng/include", "-Ithird-party/quickjs-ng/quickjs",
             "third-party/quickjs-ng/quickjs/" + source + ".c", "-w", "-o", str(output)])
        objects.append(str(output))
    host = [cxx, "-std=c++17", "-O2", "-DQUICKJS_NG_BUILD", "-IDonutgram/DGPluginRuntime/CHost/include", "-Ithird-party/quickjs-ng/include",
            "Donutgram/DGPluginRuntime/CHost/DGPluginCHost.cpp"]
    regression = build / ("runtime-tests" + suffix)
    native = build / ("native-work-tests" + suffix)
    run(host + ["Donutgram/DGPluginRuntime/Tests/RuntimeTests.cpp"] + objects + stack + libraries + ["-o", str(regression)])
    run(host + ["Donutgram/DGPluginRuntime/Tests/NativeWorkTests.cpp"] + objects + stack + libraries + ["-o", str(native)])
    defaults = {}
    for suite in ["smoke", "host"]:
        output = build / ("quickjs-" + suite + "-tests" + suffix)
        shim = ["third-party/quickjs-ng/shim/qjs_shim.c"] if suite == "smoke" else []
        run([cc, "-O2", "-DQUICKJS_NG_BUILD", "-Wno-deprecated-declarations", "-Ithird-party/quickjs-ng/include", "-Ithird-party/quickjs-ng/quickjs",
             "third-party/quickjs-ng/tests/quickjs_" + suite + "_test.c"] + shim + objects + stack + libraries + ["-o", str(output)])
        defaults[suite] = str(output)
    command = [sys.executable, str(RUNTIME / "Tests/run_watchdog.py"), "--regression", str(regression), "--native", str(native),
               "--bootstrap", str(RUNTIME / "Sources/bootstrap.js"), "--default-smoke", defaults["smoke"], "--default-host", defaults["host"]]
    for case in args.skip:
        command += ["--skip", case]
    run(command)


if __name__ == "__main__":
    main()
