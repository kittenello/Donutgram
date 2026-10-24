from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "submodules/TelegramCore/Sources"
FORMATTING = ROOT / "submodules/TelegramStringFormatting/Sources/PresenceStrings.swift"


def extract(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def main():
    compiler = shutil.which("swiftc")
    if compiler is None:
        raise SystemExit("swiftc is required; run on macOS with Xcode.")
    activity = (CORE / "Donutgram/DonutgramApproximatePresence.swift").read_text(encoding="utf-8")
    presence = (CORE / "SyncCore/SyncCore_TelegramUserPresence.swift").read_text(encoding="utf-8").replace("import Postbox", "")
    formatting = FORMATTING.read_text(encoding="utf-8")
    functions = [extract(activity, marker) for marker in (
        "func donutgramActivityGroup(",
        "func donutgramRecordMessageActivity(",
        "public func donutgramApproximateLastSeenTimestamp(",
    )]
    functions += [extract(formatting, marker) for marker in (
        "public func stringForTimestamp(day: Int32, month: Int32, year: Int32,",
        "public func stringForDonutgramApproximatePresence(",
    )]
    fixture = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
    settings = (ROOT / "Donutgram/DGSimpleSettings/Sources/DGSimpleSettings.swift").read_text(encoding="utf-8")
    fixture = fixture.replace("SETTINGS_MIGRATION", extract(settings, "if defaults.bool(forKey: Key.approximateLastSeen)"))
    fixture = fixture.replace("SETTINGS_MEMBERS", "\n".join(extract(settings, marker) for marker in (
        "private func bool(",
        "private func setBool(",
        "public var approximateLastSeen: Bool",
        "public var approximateLastSeenStartedAt: Int32?",
    )))
    fixture = fixture.replace("PRODUCTION_CODE", presence + "\n" + "\n".join(functions))
    with tempfile.TemporaryDirectory(prefix="approximate-presence-") as directory:
        directory = Path(directory)
        main_file = directory / "main.swift"
        executable = directory / "presence-tests"
        main_file.write_text(fixture, encoding="utf-8")
        subprocess.run([compiler, str(main_file), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
        for path in subprocess.check_output(["git", "diff", "--name-only", "origin/master", "--", "*.swift"], cwd=ROOT, text=True).splitlines():
            subprocess.run([compiler, "-frontend", "-parse", str(ROOT / path)], check=True)
        subprocess.run([compiler, "-frontend", "-parse", str(CORE / "Donutgram/DonutgramApproximatePresence.swift")], check=True)


if __name__ == "__main__":
    main()
