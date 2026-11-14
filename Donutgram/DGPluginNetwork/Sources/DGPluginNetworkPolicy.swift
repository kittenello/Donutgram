import Foundation
import DGPluginModel

public struct DGPluginPublicRequest {
    public let url: String
    public let host: String
    public let target: String
    public let method: String

    public static func validated(_ params: DGPluginJSON, allowedOrigins: [String]) throws -> DGPluginPublicRequest {
        guard let fields = params.objectValue, Set(fields.keys).isSubset(of: ["url", "method"]), let raw = fields["url"]?.stringValue,
              raw.utf8.count <= 2048, raw.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }), !raw.contains("\\"),
              let url = URLComponents(string: raw), url.scheme == "https", let host = url.host, host == host.lowercased(),
              validHostname(host), url.user == nil, url.password == nil, url.port == nil || url.port == 443, url.fragment == nil,
              url.url?.absoluteString == raw, raw.hasPrefix("https://" + host), allowedOrigins.contains("https://" + host) else {
            throw DGPluginError(code: "scope_denied", message: "request must target an exact granted public https origin")
        }
        let method = fields["method"]?.stringValue ?? "GET"
        guard fields["method"] == nil || fields["method"]?.stringValue != nil, ["GET", "HEAD"].contains(method) else {
            throw DGPluginError(code: "invalid_argument", message: "only public GET and HEAD requests are supported")
        }
        let path = url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath
        let target = path + (url.percentEncodedQuery.map { "?" + $0 } ?? "")
        guard target.hasPrefix("/"), !target.hasPrefix("//"), target.utf8.count <= 2048,
              target.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw DGPluginError(code: "invalid_argument", message: "invalid request target")
        }
        return DGPluginPublicRequest(url: raw, host: host, target: target, method: method)
    }

    private static func validHostname(_ host: String) -> Bool {
        guard host.utf8.count <= 253, host.contains("."), !host.hasSuffix("."), !host.contains(":"), host.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 && $0.first != "-" && $0.last != "-" }), labels.last?.contains(where: { $0.isLetter }) == true else { return false }
        return !["localhost", "local", "internal", "invalid", "test", "onion", "alt", "arpa"].contains(String(labels.last ?? ""))
    }

    public var wireBytes: Data {
        return Data("\(method) \(target) HTTP/1.1\r\nHost: \(host)\r\nAccept: application/json, text/plain;q=0.9\r\nAccept-Encoding: identity\r\nConnection: close\r\nUser-Agent: DonutgramPluginPublic/1\r\n\r\n".utf8)
    }
}

public enum DGPluginPublicAddress {
    public static func isAllowed(_ address: String) -> Bool {
        if address.contains(":") { return allowedIPv6(address) }
        guard let bytes = ipv4(address) else { return false }
        return allowedIPv4(bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
    }

    private static func allowedIPv4(_ value: UInt32) -> Bool {
        let blocked: [(UInt32, Int)] = [
            (0x00000000, 8), (0x0a000000, 8), (0x64400000, 10), (0x7f000000, 8),
            (0xa9fe0000, 16), (0xac100000, 12), (0xc0000000, 24), (0xc0000200, 24),
            (0xc01fc400, 24), (0xc034c100, 24), (0xc0586300, 24), (0xc0a80000, 16), (0xc0af3000, 24),
            (0xc6120000, 15), (0xc6336400, 24), (0xcb007100, 24), (0xe0000000, 4), (0xf0000000, 4)
        ]
        return !blocked.contains { prefix, bits in (value >> (32 - bits)) == (prefix >> (32 - bits)) }
    }

    private static func ipv4(_ text: String) -> [UInt8]? {
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 4 else { return nil }
        var result: [UInt8] = []
        for label in labels {
            guard !label.isEmpty, label.count <= 3, label.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), label.count == 1 || label.first != "0", let value = UInt8(label) else { return nil }
            result.append(value)
        }
        return result
    }

    private static func allowedIPv6(_ text: String) -> Bool {
        guard text.utf8.count <= 39, !text.contains("%"), !text.contains("."), text.unicodeScalars.allSatisfy({ $0.isASCII && ($0 == ":" || CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)) }) else { return false }
        let compressed = text.components(separatedBy: "::")
        guard compressed.count <= 2 else { return false }
        func groups(_ part: String) -> [UInt16]? {
            if part.isEmpty { return [] }
            let values = part.split(separator: ":", omittingEmptySubsequences: false)
            var result: [UInt16] = []
            for value in values {
                guard !value.isEmpty, value.count <= 4, let word = UInt16(value, radix: 16) else { return nil }
                result.append(word)
            }
            return result
        }
        guard let first = groups(compressed[0]) else { return false }
        let words: [UInt16]
        if compressed.count == 2 {
            guard let last = groups(compressed[1]), first.count + last.count < 8 else { return false }
            words = first + Array(repeating: 0, count: 8 - first.count - last.count) + last
        } else { words = first }
        guard words.count == 8 else { return false }
        // DNS64 on an IPv6-only network answers for an IPv4-only host inside 64:ff9b::/96. Only that well-known prefix
        // is accepted, and only when the IPv4 address it embeds is allowed itself.
        if words[0] == 0x0064 && words[1] == 0xff9b && words[2 ... 5].allSatisfy({ $0 == 0 }) { return allowedIPv4((UInt32(words[6]) << 16) | UInt32(words[7])) }
        guard words[0] & 0xe000 == 0x2000 else { return false }
        if words[0] == 0x2001 && words[1] < 0x0200 { return false }
        if words[0] == 0x2001 && words[1] == 0x0db8 { return false }
        if words[0] == 0x2002 { return false }
        if words[0] == 0x3fff && words[1] & 0xf000 == 0 { return false }
        if words[0] == 0x2620 && words[1] == 0x004f && words[2] == 0x8000 { return false }
        return true
    }
}
