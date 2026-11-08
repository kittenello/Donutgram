import Foundation
import DGPluginModel

public struct DGPluginHTTPResponse {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public func json(url: String) throws -> DGPluginJSON {
        guard let text = String(data: body, encoding: .utf8) else { throw DGPluginError(code: "invalid_response", message: "public response must contain valid utf8 text") }
        let result: DGPluginJSON = .object(["url": .string(url), "status": .number(Double(status)), "headers": .object(headers.mapValues(DGPluginJSON.string)), "body": .string(text)])
        guard try JSONEncoder().encode(result).count <= 60 * 1024 else { throw DGPluginError(code: "quota_exceeded", message: "encoded public response exceeds bridge quota") }
        return result
    }

    public static func parse(_ data: Data, method: String, endOfStream: Bool) throws -> DGPluginHTTPResponse? {
        guard data.count <= 96 * 1024 else { throw DGPluginError(code: "quota_exceeded", message: "public response exceeds wire quota") }
        guard let boundary = data.range(of: Data([13, 10, 13, 10])) else {
            guard data.count <= 16 * 1024, !endOfStream else { throw DGPluginError(code: "invalid_response", message: "public response headers are missing or oversized") }
            return nil
        }
        guard boundary.lowerBound <= 16 * 1024, let headerText = String(data: data[..<boundary.lowerBound], encoding: .utf8), headerText.unicodeScalars.allSatisfy({ $0.value == 9 || $0.value == 10 || $0.value == 13 || ($0.value >= 32 && $0.value <= 126) }) else { throw DGPluginError(code: "invalid_response", message: "invalid public response headers") }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let statusLine = lines.first, statusLine.utf8.count <= 256 else { throw DGPluginError(code: "invalid_response", message: "invalid status line") }
        let pieces = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard pieces.count >= 2, ["HTTP/1.1", "HTTP/1.0"].contains(String(pieces[0])), pieces[1].count == 3, pieces[1].utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let status = Int(pieces[1]), status >= 200, status <= 599 else { throw DGPluginError(code: "invalid_response", message: "unsupported public response status") }
        guard !(300 ... 399).contains(status) else { throw DGPluginError(code: "redirect_denied", message: "public request redirects are not followed") }
        guard lines.count <= 65 else { throw DGPluginError(code: "quota_exceeded", message: "too many response headers") }
        var headers: [String: String] = [:]
        let token = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~")
        for line in lines.dropFirst() {
            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { throw DGPluginError(code: "invalid_response", message: "malformed response header") }
            let name = String(line[..<colon]).lowercased()
            let rawValue = line[line.index(after: colon)...]
            guard !name.isEmpty, name.utf8.count <= 128, name.unicodeScalars.allSatisfy(token.contains), headers[name] == nil,
                  rawValue.unicodeScalars.allSatisfy({ $0.value == 9 || ($0.value >= 32 && $0.value <= 126) }) else { throw DGPluginError(code: "invalid_response", message: "ambiguous response headers") }
            headers[name] = rawValue.trimmingCharacters(in: .whitespaces)
        }
        guard headers["content-encoding"] == nil || headers["content-encoding"]?.lowercased() == "identity" else { throw DGPluginError(code: "invalid_response", message: "compressed responses are not accepted") }
        guard headers["transfer-encoding"] == nil || headers["transfer-encoding"]?.lowercased() == "chunked", headers["transfer-encoding"] == nil || headers["content-length"] == nil else { throw DGPluginError(code: "invalid_response", message: "ambiguous response framing") }
        let remaining = Data(data[boundary.upperBound...])
        let body: Data
        if method == "HEAD" || status == 204 || status == 205 {
            guard remaining.isEmpty else { throw DGPluginError(code: "invalid_response", message: "unexpected response body") }
            body = Data()
        } else if headers["transfer-encoding"] != nil {
            guard let decoded = try decodeChunks(remaining, endOfStream: endOfStream) else { return nil }
            body = decoded
        } else if let lengthValue = headers["content-length"] {
            guard !lengthValue.isEmpty, lengthValue.utf8.count <= 10, lengthValue.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let length = Int(lengthValue), length <= 48 * 1024 else { throw DGPluginError(code: "quota_exceeded", message: "public response body exceeds quota") }
            guard remaining.count <= length else { throw DGPluginError(code: "invalid_response", message: "response exceeds declared content length") }
            if remaining.count < length {
                guard !endOfStream else { throw DGPluginError(code: "invalid_response", message: "truncated public response") }
                return nil
            }
            body = remaining
        } else {
            guard remaining.count <= 48 * 1024 else { throw DGPluginError(code: "quota_exceeded", message: "public response body exceeds quota") }
            guard endOfStream else { return nil }
            body = remaining
        }
        let visible = headers.filter { ["content-type", "etag", "last-modified", "cache-control"].contains($0.key) }
        return DGPluginHTTPResponse(status: status, headers: visible, body: body)
    }

    private static func decodeChunks(_ data: Data, endOfStream: Bool) throws -> Data? {
        var offset = 0
        var result = Data()
        var chunks = 0
        while offset <= data.count {
            guard let lineEnd = data.range(of: Data([13, 10]), in: offset ..< data.count) else {
                guard data.count - offset <= 16, !endOfStream else { throw DGPluginError(code: "invalid_response", message: "invalid chunk header") }
                return nil
            }
            let sizeData = data[offset ..< lineEnd.lowerBound]
            guard !sizeData.isEmpty, sizeData.count <= 8, sizeData.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102) }), let sizeText = String(data: sizeData, encoding: .ascii), let size = Int(sizeText, radix: 16) else { throw DGPluginError(code: "invalid_response", message: "unsupported chunk framing") }
            offset = lineEnd.upperBound
            chunks += 1
            guard chunks <= 1024, size <= 48 * 1024 - result.count else { throw DGPluginError(code: "quota_exceeded", message: "chunked response exceeds quota") }
            if size == 0 {
                guard data.count - offset <= 2 else { throw DGPluginError(code: "invalid_response", message: "response trailers are not accepted") }
                guard data.count - offset == 2 else {
                    guard !endOfStream else { throw DGPluginError(code: "invalid_response", message: "truncated chunk terminator") }
                    return nil
                }
                guard data[offset] == 13, data[offset + 1] == 10 else { throw DGPluginError(code: "invalid_response", message: "invalid chunk terminator") }
                return result
            }
            guard data.count - offset >= size + 2 else {
                guard !endOfStream else { throw DGPluginError(code: "invalid_response", message: "truncated response chunk") }
                return nil
            }
            result.append(data[offset ..< offset + size])
            offset += size
            guard data[offset] == 13, data[offset + 1] == 10 else { throw DGPluginError(code: "invalid_response", message: "invalid chunk delimiter") }
            offset += 2
        }
        return nil
    }
}
