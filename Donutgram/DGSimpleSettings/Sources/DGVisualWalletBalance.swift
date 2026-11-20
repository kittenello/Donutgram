import Foundation

public func donutgramParseVisualWalletBalance(_ text: String) -> Int64? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard (1 ... 2).contains(parts.count), !parts[0].isEmpty,
          parts.allSatisfy({ $0.utf8.allSatisfy({ (48 ... 57).contains($0) }) }),
          let whole = Int64(parts[0]) else {
        return nil
    }
    let fraction = parts.count == 2 ? String(parts[1]) : ""
    guard fraction.count <= 9 else { return nil }
    let fractionalValue = Int64(fraction + String(repeating: "0", count: 9 - fraction.count)) ?? 0
    let (scaled, multiplyOverflow) = whole.multipliedReportingOverflow(by: 1_000_000_000)
    let (value, additionOverflow) = scaled.addingReportingOverflow(fractionalValue)
    guard !multiplyOverflow, !additionOverflow else { return nil }
    return value
}
