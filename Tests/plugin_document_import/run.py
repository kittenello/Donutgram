from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SIGNALS = ROOT / "submodules/SSignalKit/SwiftSignalKit/Source"
UI = ROOT / "Donutgram/DGPluginsUI/Sources"


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def prepare():
    controller = (UI / "DGPluginsController.swift").read_text(encoding="utf-8")
    document = block(controller, "public func dgOpenPluginDocument(")
    icon = block(controller, "public func dgPluginDocumentIcon(")
    assert "dgPluginValidateDocument(source: source" in document
    assert "Queue.concurrentDefaultQueue()" not in document + icon
    assert "deliverOn(dgPluginDocumentIconQueue)" in icon
    assert 'Queue(name: "donutgram.plugin.document-icon"' in controller
    assert "DGPluginInstaller.preview(data: data, fileName: fileName)" in document
    assert "limit + 1" in document and "read.dispose(); fetch.dispose()" in document
    assert "mode: .loading" not in document and "case loading" not in controller
    assert "presentOverlay(overlay)" in document and "overlay?.dismiss()" in document
    assert "operation?.finish(nil)" in document and "dgPluginDocumentImports[key] = operation" in document
    assert "case let .success(package):\n            present(dgPluginInstallController" in document
    image_item = controller.split("        case .image:", 1)[1].split("        case .action", 1)[0]
    assert "ItemListTextItem(" not in image_item
    contents = [(SIGNALS / name).read_text(encoding="utf-8") for name in ["Atomic.swift", "Disposable.swift", "Subscriber.swift", "Signal.swift", "Queue.swift", "Timer.swift"]]
    for name, marker in [("Signal_Take.swift", "public func take<T, E>(_ count:"), ("Signal_Mapping.swift", "public func map<T, E, R>("), ("Signal_Dispatch.swift", "public func deliverOn<T, E>(_ queue:"), ("Signal_Timing.swift", "public func timeout<T, E>(")]:
        contents.append(block((SIGNALS / name).read_text(encoding="utf-8"), marker))
    contents.append((ROOT / "Donutgram/DGPluginModel/Sources/DGPluginModel.swift").read_text(encoding="utf-8"))
    contents.append((UI / "DGPluginDocumentValidation.swift").read_text(encoding="utf-8").replace("import SwiftSignalKit\n", "").replace("import DGPluginModel\n", ""))
    row = controller[controller.index("private struct DGPluginRow:"):controller.index("    func item(presentationData:")]
    contents.append("typealias ItemListSectionId = Int32\n" + row.replace(": ItemListNodeEntry", ": Comparable") + "}\n")
    contents.append(block((ROOT / "submodules/MergeLists/Sources/MergeLists.swift").read_text(encoding="utf-8"), "public func mergeListsStableWithUpdates<T>(leftList: [T], rightList: [T], isLess:"))
    return "\n".join(contents)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--swiftc")
    parser.add_argument("--sdk")
    args = parser.parse_args()
    source = prepare()
    if args.source_only:
        print("plugin document integration checks passed; Swift behavior was not run")
        return
    swift = args.swiftc or shutil.which("swiftc")
    if not swift:
        raise SystemExit("swiftc is required for document ordering checks")
    with tempfile.TemporaryDirectory(prefix="donutgram-plugin-document-") as temporary:
        directory = Path(temporary)
        main_file = directory / "main.swift"
        shim = Path(__file__).with_name("windows-locks.swift").read_text(encoding="utf-8") if os.name == "nt" else ""
        main_file.write_text(shim + "\n" + source + "\n" + Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8"), encoding="utf-8")
        executable = directory / ("checks.exe" if os.name == "nt" else "checks")
        options = ["-sdk", args.sdk] if args.sdk else []
        subprocess.run([swift, *options, "-swift-version", "5", str(main_file), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True, timeout=15)


if __name__ == "__main__":
    main()
