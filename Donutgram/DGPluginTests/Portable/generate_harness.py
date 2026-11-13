import argparse
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("repository", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    suites = [
        ("Donutgram/DGPluginInstaller/Tests/DGPluginInstallerTests.swift", "DGPluginInstallerTests", "installer"),
        ("Donutgram/DGPluginTests/Tests/DGPluginPolicyTests.swift", "DGPluginPolicyTests", "policy"),
        ("Donutgram/DGPluginTests/Tests/DGPluginHostIntegrationTests.swift", "DGPluginHostIntegrationTests", "host"),
    ]
    lines = [
        "import Foundation",
        "import WinSDK",
        'func report(_ text: String) { FileHandle.standardOutput.write(Data((text + "\\n").utf8)) }',
        "DispatchQueue.global().async {",
        "do {",
        'if let mode = ProcessInfo.processInfo.environment["DG_PLUGIN_RECOVERY_CHILD"] { try runInterruptedRecoveryChild(mode: mode); ExitProcess(0) }',
        'if ProcessInfo.processInfo.environment["DG_PLUGIN_QUOTA_CHILD"] != nil { try runMissingAccountQuotaRegression(child: true); ExitProcess(0) }',
        'if let mode = ProcessInfo.processInfo.environment["DG_PLUGIN_RESTART_MODE"] { try runRestartChild(mode: mode); ExitProcess(0) }',
    ]
    for source, classname, name in suites:
        text = (args.repository / source).read_text(encoding="utf-8")
        (args.output / (name + "-tests.swift")).write_text(text.replace("import XCTest\n", ""), encoding="utf-8")
        methods = re.findall(r"func (test\w+)\(\)([^\{]*)\{", text)
        for method, signature in methods:
            lines.extend(["do {", f"let test = {classname}()", "try test.setUpWithError()"])
            invocation = ("try " if "throws" in signature else "") + "test." + method + "()"
            lines.append("do { " + invocation + "; try test.tearDownWithError() } catch { try? test.tearDownWithError(); throw error }")
            lines.extend([f'report("{classname}.{method}: passed")', "}"])
    lines.extend([
        "try runDeferredSaveRegressions()",
        "try runPluginReviewRegressionTests()",
        "try runNativeActionTests()",
        "try runSemanticVersionTests()",
        "try runPersistenceFaultTests()",
        "try runDurableRemovalRestartTests()",
        "try runInterruptedRecoveryTests()",
        "try runMarkerWriteFailureTests()",
        "try runGeneratedArchiveTests(directory: URL(fileURLWithPath: CommandLine.arguments[1]))",
        'report("all portable production checks passed")',
        "ExitProcess(0)",
        '} catch { report("portable production checks failed: \\(error)"); ExitProcess(1) }',
        "}",
        "dispatchMain()",
    ])
    (args.output / "main.swift").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
