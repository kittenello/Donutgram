"""Compile the production search helpers of «Сохраненные удаленки» with small fixtures."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "submodules/TelegramCore/Sources/Donutgram"
SEARCH_UI = ROOT / "Donutgram/DGSettingsUI/Sources/DGSavedDeletedMessagesSearch.swift"
HELPERS = {
    "DonutgramSpyStorage.swift": [
        "func donutgramDeletedMessageMatchesQuery(", "func donutgramSearchWords(",
        "func donutgramSearchWordsMatch(",
    ],
    "DonutgramPreservedMedia.swift": [
        "struct DonutgramPreservedMessageSearchEntry", "func donutgramPreservedMessageIds(",
    ],
}


def extract(source, marker):
    start = source.index(marker)
    start = source.rfind("\n", 0, start) + 1
    position = source.index(marker, start) + len(marker)
    if marker.startswith("func "):
        # Skip the parameter list, whose default values may contain braces.
        depth = 1
        while depth:
            depth += (source[position] == "(") - (source[position] == ")")
            position += 1
    opening = source.index("{", position)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].replace("public ", "")


def make_harness():
    helpers = "\n\n".join(
        extract((CORE / file).read_text(encoding="utf-8"), marker)
        for file, markers in HELPERS.items() for marker in markers
    )
    fixture = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
    assert fixture.count("// PRODUCTION_HELPERS") == 1
    ui = SEARCH_UI.read_text(encoding="utf-8")
    # The page searches the prebuilt index, stops superseded scans and follows the found messages.
    assert "donutgramPreservedMessageIds(matching: query, in: index, limit: searchResultLimit + 1, isCancelled:" in ui
    assert "ActionDisposable {" in ui and "isCancelled.swap(true)" in ui
    assert "context.engine.data.subscribe(" in ui
    assert "donutgramSearchWords(query).isEmpty" in ui
    return fixture.replace("// PRODUCTION_HELPERS", helpers)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    harness = make_harness()
    if args.source_only:
        print("Helper extraction and search page source checks passed; Swift execution was not run.")
        return
    swift = shutil.which("swiftc")
    if swift is None:
        raise SystemExit("swiftc is required; run on macOS with Xcode.")
    with tempfile.TemporaryDirectory(prefix="donutgram-deleted-search-") as directory:
        directory = Path(directory)
        source = directory / "main.swift"
        executable = directory / "deleted-search-tests"
        source.write_text(harness, encoding="utf-8")
        subprocess.run([swift, "-warnings-as-errors", str(source), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
        for path in [CORE / file for file in HELPERS] + [SEARCH_UI]:
            subprocess.run([swift, "-frontend", "-parse", str(path)], check=True)


if __name__ == "__main__":
    main()
