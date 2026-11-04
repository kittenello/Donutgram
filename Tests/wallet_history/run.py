import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


parser = argparse.ArgumentParser()
parser.add_argument("--source-only", action="store_true")
args = parser.parse_args()
models = (ROOT / "submodules/WalletContext/Sources/WalletModels.swift").read_text(encoding="utf-8")
history = (ROOT / "submodules/WalletContext/Sources/WalletTransactions.swift").read_text(encoding="utf-8")
screen_path = ROOT / "submodules/TelegramUI/Components/Wallet/WalletScreen/Sources"
presentation = (screen_path / "WalletHistoryContentState.swift").read_text(encoding="utf-8").replace("import WalletContext\n", "")
screen = (screen_path / "WalletScreen.swift").read_text(encoding="utf-8")
assert "hasLoaded: true" in block(history, "mutating func applyRefresh(")
assert "hasLoaded: true" in block(history, "mutating func applyPage(")
assert "hasLoaded: previous.hasLoaded" in block(history, "func failed(")
assert "WalletHistoryContentState.resolve(state: self.walletState" in screen
assert "self?.component?.walletContext.retryHistory()" in screen
assert 'if historyContent == .intro {' in screen
fixture = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
state = block(models, "struct TransactionsState:").replace("public ", "")
source = fixture.replace("struct TransactionsState {}", state) + "\n" + presentation
if args.source_only:
    print("wallet history state integration checks passed; Swift behavior was not executed")
    raise SystemExit(0)
swift = shutil.which("swiftc")
if not swift:
    raise SystemExit("swiftc is required")
with tempfile.TemporaryDirectory(prefix="donutgram-wallet-history-") as temporary:
    main = Path(temporary) / "main.swift"
    executable = Path(temporary) / "checks"
    main.write_text(source, encoding="utf-8")
    subprocess.run([swift, "-warnings-as-errors", str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
    for path in [screen_path / "WalletScreen.swift", screen_path / "WalletHistoryContentState.swift"]:
        subprocess.run([swift, "-frontend", "-parse", str(path)], check=True)
