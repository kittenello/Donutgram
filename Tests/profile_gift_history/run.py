"""Compile the production history helpers with small fixtures (requires Swift)."""

from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "submodules/TelegramCore/Sources/TelegramEngine/Payments/StarGifts.swift"
HELPERS = (
    "giftsMatchForHistory",
    "giftHistoryKeys",
    "giftWasUpgraded",
    "matchGiftHistory",
    "sortedGiftHistory",
    "distinctGiftsForHistory",
    "giftsWithDisappeared",
    "reindexGiftHistory",
    "updatedGiftHistory",
    "removingDisappearedGift",
)


def extract_helper(source, name):
    marker = f"static func {name}("
    start = source.index(marker)
    line_start = source.rfind("\n", 0, start) + 1
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[line_start:end].replace("public static func", "static func")


def method_body(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def check_displayed_count(source):
    # The own profile's «N (M) подарков»: every action that takes one of the account's gifts off the list takes it off
    # the displayed count too, before the gift leaves the list, where removeFromDisplayedCount looks it up.
    for name in ("convertStarGift", "deleteStarGift", "transferStarGift", "withdrawStarGift"):
        assert source.count(f"    func {name}(") == 1, name
        method = method_body(source, f"    func {name}(")
        removal = method.index("self.gifts.removeAll(where: { $0.reference == reference })")
        displayed = method.find("self.removeFromDisplayedCount(reference: reference)")
        assert 0 <= displayed < removal, f"{name} must update the displayed count before it removes the gift"


def main():
    source = SOURCE.read_text(encoding="utf-8")
    check_displayed_count(source)
    swift = shutil.which("swiftc")
    if swift is None:
        raise SystemExit("swiftc is required; run this check on macOS with Xcode.")
    helpers = "\n".join(extract_helper(source, name) for name in HELPERS)
    fixture = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
    assert fixture.count("// PRODUCTION_HELPERS") == 1
    with tempfile.TemporaryDirectory(prefix="donutgram-gift-history-") as directory:
        directory = Path(directory)
        harness = directory / "main.swift"
        executable = directory / "gift-history-tests"
        harness.write_text(fixture.replace("// PRODUCTION_HELPERS", helpers), encoding="utf-8")
        subprocess.run([swift, str(harness), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
