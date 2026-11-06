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
# A history confirmed empty keeps the wallet's introduction and terms; loading and failures show a status instead.
assert "let showsIntroduction = historyContent == .intro || historyContent == .empty" in screen
assert screen.count("if showsIntroduction {") == 1 and "if !showsIntroduction {" in screen
# The error of a failed state request does not outlive the state that arrives after it.
impl = (ROOT / "submodules/WalletContext/Sources/WalletContextImpl.swift").read_text(encoding="utf-8")
assert "transactions: self.currentState.transactions.withError(.network)," in block(impl, "private func performServerWalletStateRequest(")
assert "? self.currentState.transactions.withError(nil)" in block(impl, "func applyServerWalletState(")
fixture = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
state = block(models, "struct TransactionsState:").replace("public ", "")
source = fixture.replace("struct TransactionsState {}", state) + "\n" + presentation
source += "\n" + block(impl, "extension WalletContext.TransactionsState {") + "\n"
security = (ROOT / "submodules/WalletContext/Sources/WalletSecurity.swift").read_text(encoding="utf-8")
group = block(security, "static func keychainAccessGroup()")
group = group[:group.index("#if os(macOS)")] + group.split("#else", 1)[1].replace("#endif", "")
source += "\nenum WalletVault {\n" + group + "\n}\n"
passcode = (ROOT / "submodules/PasscodeCore/Sources/Passcode.swift").read_text(encoding="utf-8")
assert "public var usesDefaultKeychainAccessGroup: Bool" in passcode
assert "keychain_status=" in (ROOT / "submodules/WalletContext/Sources/WalletLogger.swift").read_text(encoding="utf-8")
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
