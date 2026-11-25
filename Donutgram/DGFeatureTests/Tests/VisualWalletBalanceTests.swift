import XCTest
import DGSimpleSettings

final class VisualWalletBalanceTests: XCTestCase {
    func testDecimalAmountUsesExactNanograms() {
        XCTAssertEqual(donutgramParseVisualWalletBalance("1000"), 1_000_000_000_000)
        XCTAssertEqual(donutgramParseVisualWalletBalance(" 123,456789012 "), 123_456_789_012)
        XCTAssertEqual(donutgramParseVisualWalletBalance("0.000000001"), 1)
        XCTAssertEqual(donutgramParseVisualWalletBalance("0"), 0)
        XCTAssertEqual(donutgramParseVisualWalletBalance("1,"), 1_000_000_000)
    }

    func testAmountsAtInt64BoundaryDoNotOverflow() {
        XCTAssertEqual(donutgramParseVisualWalletBalance("9223372036.854775807"), Int64.max)
        XCTAssertNil(donutgramParseVisualWalletBalance("9223372036.854775808"))
        XCTAssertNil(donutgramParseVisualWalletBalance("9223372037"))
        XCTAssertNil(donutgramParseVisualWalletBalance("9223372036854775808"))
    }

    func testEmptyAndInvalidAmountsDisableOverride() {
        for value in ["", " ", "-1", "NaN", "inf", "1e3", "1.2.3", "1,2.3", "0.0000000001", ".", "1 000", "١"] {
            XCTAssertNil(donutgramParseVisualWalletBalance(value), value)
        }
    }

    func testBalanceIsAccountSpecificAndCanBeCleared() {
        let settings = DGSimpleSettings.shared
        let firstAccount = Int64.min + 132
        let secondAccount = Int64.min + 133
        let previousFirst = settings.visualWalletBalanceText(accountId: firstAccount)
        let previousSecond = settings.visualWalletBalanceText(accountId: secondAccount)
        defer {
            settings.setVisualWalletBalanceText(previousFirst, accountId: firstAccount)
            settings.setVisualWalletBalanceText(previousSecond, accountId: secondAccount)
        }
        settings.setVisualWalletBalanceText("10,5", accountId: firstAccount)
        settings.setVisualWalletBalanceText("0", accountId: secondAccount)
        XCTAssertEqual(settings.visualWalletBalance(accountId: firstAccount), 10_500_000_000)
        XCTAssertEqual(settings.visualWalletBalance(accountId: secondAccount), 0)
        settings.setVisualWalletBalanceText("", accountId: firstAccount)
        XCTAssertNil(settings.visualWalletBalance(accountId: firstAccount))
        XCTAssertEqual(settings.visualWalletBalance(accountId: secondAccount), 0)
    }
}
