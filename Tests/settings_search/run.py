from pathlib import Path
import argparse
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
UI = ROOT / "Donutgram/DGSettingsUI/Sources"


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def prepare():
    search = (UI / "DGSettingsSearch.swift").read_text(encoding="utf-8")
    features = (UI / "DGFeatureControllers.swift").read_text(encoding="utf-8")
    links = (UI / "DGSettingLinks.swift").read_text(encoding="utf-8")
    controller = (UI / "DGSettingsController.swift").read_text(encoding="utf-8")
    pages = dict(re.findall(r'case (\w+) = "([^"]+)"', links))
    catalog = {}
    for page, title, rows in re.findall(r'    add\("([^"]+)", "([^"]+)", \[(.*?)\](?:, parent: "[^"]+")?\)', search, re.S):
        assert page not in catalog, page
        entries = re.findall(r'\("([^"]*)", "([^"]+)", "[^"]*"\)', rows)
        assert all(key for key, _ in entries), (page, "empty row key duplicates the section route")
        assert len(dict(entries)) == len(entries), (page, "duplicate row keys")
        catalog[page] = dict(entries)
    # Entries drawn by their own items report a fixed key, such as the speed slider's.
    fixed_keys = dict(re.findall(r'case \.(\w+): return DGSettingItemTag\(key: "([^"]+)"\)', controller))
    page_keys = {}
    for page, body in re.findall(r'dgController\(context: context, page: \.(\w+), title: .*?, focusKey: focusKey, entries: \{(.*?)\n    \}', features, re.S):
        page = pages.get(page, page)
        # Every setting a page shows can be found, under the title it shows. A profile row shows its caption.
        for key, title in re.findall(r'\.(?:toggle|menu|disclosure|action|value)\(\d+,\s*\d+,\s*"([^"]+)",\s*"([^"]+)"', body):
            assert catalog.get(page, {}).get(key) == title, (page, key, title)
        for key, caption in re.findall(r'\.profileRow\(\d+,\s*\d+,\s*"([^"]+)",\s*"([^"]+)"', body):
            assert catalog.get(page, {}).get(key, "").lower() == caption.lower(), (page, key, caption)
        keys = set(re.findall(r'\.(?:toggle|menu|disclosure|action|value|input|profileRow)\(\d+,\s*\d+,\s*"([^"]+)"', body))
        keys |= {key for kind, key in fixed_keys.items() if "." + kind + "(" in body}
        page_keys[page] = keys
    # And every result leads to a row its page shows: a page built without dgController tags the row itself.
    sources = "".join(path.read_text(encoding="utf-8") for path in UI.glob("*.swift"))
    for page, rows in catalog.items():
        for key in rows:
            if page in page_keys:
                assert key in page_keys[page], (page, key)
            else:
                assert 'DGSettingItemTag(key: "%s")' % key in sources, (page, key)
    assert 'listEntries.insert(.input(-3, -2, "settingsSearch", state.searchQuery' in controller
    assert 'dgSettingsControllerForLink(context: context, page: item.page, key: item.key)' in controller
    assert 'state.searchQuery = value' in controller
    enum = block(links, "enum DGSettingsPage:")
    shown_row = block(features, "private func dgShownRow(").replace("DGSimpleSettings.shared", "testSettings")
    fixture = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
    return search.replace("import DGSimpleSettings\n", "") + "\n" + enum + "\n" + shown_row + "\n" + fixture


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    source = prepare()
    if args.source_only:
        print("settings search catalog coverage and integration checks passed; Swift execution was not run")
        return
    swift = shutil.which("swiftc")
    if not swift:
        raise SystemExit("swiftc is required for behavior checks")
    with tempfile.TemporaryDirectory(prefix="donutgram-settings-search-") as temporary:
        directory = Path(temporary)
        main_file = directory / "main.swift"
        main_file.write_text(source, encoding="utf-8")
        executable = directory / "checks"
        settings = (ROOT / "Donutgram/DGSimpleSettings/Sources").glob("*.swift")
        subprocess.run([swift, "-warnings-as-errors", *map(str, settings), str(main_file), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
        for name in ["DGSettingsController.swift", "DGSettingsSearch.swift", "DGFeatureControllers.swift"]:
            subprocess.run([swift, "-frontend", "-parse", str(UI / name)], check=True)


if __name__ == "__main__":
    main()
