import Foundation
import DGPluginModel

struct DGStaticJSONParser {
    private let bytes: [UInt8]
    private(set) var offset = 0
    private var nodes = 0

    init(_ data: Data) { self.bytes = Array(data) }

    mutating func complete() throws -> DGPluginJSON {
        let result = try self.value(depth: 0)
        self.whitespace()
        guard self.offset == self.bytes.count else { throw self.invalid() }
        return result
    }

    mutating func singleFileManifest() throws -> DGPluginJSON {
        try self.token("const")
        try self.token("_plugin")
        try self.token("=")
        guard try self.string() == "donutgram" else { throw self.invalid() }
        try self.token(";")
        try self.token("const")
        try self.token("manifest")
        try self.token("=")
        let result = try self.value(depth: 0)
        try self.token(";")
        guard self.offset <= 131072 else { throw self.invalid() }
        return result
    }

    mutating func marker() throws {
        try self.token("const")
        try self.token("_plugin")
        try self.token("=")
        guard try self.string() == "donutgram" else { throw self.invalid() }
        try self.token(";")
    }

    private mutating func value(depth: Int) throws -> DGPluginJSON {
        self.nodes += 1
        guard depth <= 24, self.nodes <= 8192 else { throw self.invalid() }
        self.whitespace()
        guard self.offset < self.bytes.count else { throw self.invalid() }
        switch self.bytes[self.offset] {
        case 34: return .string(try self.string())
        case 123:
            self.offset += 1
            var result: [String: DGPluginJSON] = [:]
            self.whitespace()
            if self.consume(125) { return .object(result) }
            while true {
                let key = try self.string()
                guard !["__proto__", "prototype", "constructor"].contains(key), result[key] == nil else { throw self.invalid() }
                try self.token(":")
                result[key] = try self.value(depth: depth + 1)
                self.whitespace()
                if self.consume(125) { return .object(result) }
                try self.token(",")
            }
        case 91:
            self.offset += 1
            var result: [DGPluginJSON] = []
            self.whitespace()
            if self.consume(93) { return .array(result) }
            while true {
                result.append(try self.value(depth: depth + 1))
                self.whitespace()
                if self.consume(93) { return .array(result) }
                try self.token(",")
            }
        case 116: try self.token("true"); return .bool(true)
        case 102: try self.token("false"); return .bool(false)
        case 110: try self.token("null"); return .null
        default:
            let start = self.offset
            while self.offset < self.bytes.count, [UInt8(45), 43, 46, 69, 101].contains(self.bytes[self.offset]) || (self.offset < self.bytes.count && self.bytes[self.offset] >= 48 && self.bytes[self.offset] <= 57) {
                self.offset += 1
            }
            guard self.offset > start, self.offset - start <= 64 else { throw self.invalid() }
            let data = Data(self.bytes[start ..< self.offset])
            guard let number = try? JSONDecoder().decode(Double.self, from: data), number.isFinite else { throw self.invalid() }
            return .number(number)
        }
    }

    private mutating func string() throws -> String {
        self.whitespace()
        guard self.consume(34) else { throw self.invalid() }
        let start = self.offset - 1
        var escaped = false
        while self.offset < self.bytes.count, self.offset - start <= 16384 {
            let character = self.bytes[self.offset]
            self.offset += 1
            if character == 34 && !escaped {
                guard let result = try? JSONDecoder().decode(String.self, from: Data(self.bytes[start ..< self.offset])), !result.unicodeScalars.contains(where: { $0.value == 0 }) else { throw self.invalid() }
                return result
            }
            if character == 92 { escaped = !escaped } else { escaped = false }
        }
        throw self.invalid()
    }

    private mutating func token(_ token: String) throws {
        self.whitespace()
        let expected = Array(token.utf8)
        guard self.offset + expected.count <= self.bytes.count, self.bytes[self.offset ..< self.offset + expected.count].elementsEqual(expected) else { throw self.invalid() }
        self.offset += expected.count
        if let last = expected.last, (last >= 65 && last <= 90) || (last >= 97 && last <= 122) {
            if self.offset < self.bytes.count {
                let next = self.bytes[self.offset]
                guard !((next >= 65 && next <= 90) || (next >= 97 && next <= 122) || (next >= 48 && next <= 57) || next == 95 || next == 36) else { throw self.invalid() }
            }
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        if self.offset < self.bytes.count && self.bytes[self.offset] == byte { self.offset += 1; return true }
        return false
    }

    private mutating func whitespace() {
        while self.offset < self.bytes.count, [UInt8(9), 10, 13, 32].contains(self.bytes[self.offset]) { self.offset += 1 }
    }

    private func invalid() -> DGPluginError { return DGPluginError(code: "invalid_metadata", message: "invalid static plugin metadata") }
}
