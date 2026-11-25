import Foundation

public enum DGPluginCanonicalJSON {
    public static let format = "dg-canonical-v1"

    public static func encode(_ value: DGPluginJSON) throws -> Data {
        try value.validateLimits(maximumDepth: 24, maximumNodes: 8192)
        var output = Data()
        func text(_ value: String) {
            let bytes = Data(value.utf8)
            output.append(Data("s\(bytes.count):".utf8))
            output.append(bytes)
        }
        func append(_ value: DGPluginJSON) throws {
            switch value {
            case .null: output.append(110)
            case let .bool(value): output.append(value ? 116 : 102)
            case let .number(value):
                guard value.isFinite else { throw DGPluginError(code: "invalid_signature", message: "nonfinite canonical number") }
                output.append(100)
                let bits = (value == 0 ? Double(0) : value).bitPattern
                for shift in stride(from: 56, through: 0, by: -8) { output.append(UInt8(truncatingIfNeeded: bits >> shift)) }
            case let .string(value): text(value)
            case let .array(values):
                output.append(Data("a\(values.count):".utf8))
                for value in values { try append(value) }
            case let .object(values):
                output.append(Data("o\(values.count):".utf8))
                for key in values.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
                    text(key)
                    try append(values[key]!)
                }
            }
        }
        try append(value)
        return output
    }
}
