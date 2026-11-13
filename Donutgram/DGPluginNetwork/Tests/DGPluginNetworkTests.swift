import Foundation
import XCTest
import DGPluginModel
import DGPluginNetwork

final class DGPluginNetworkTests: XCTestCase {
    func testPublicAddressClassificationRejectsSpecialAndAmbiguousForms() {
        for address in ["8.8.8.8", "1.1.1.1", "93.184.216.34", "2001:4860:4860::8888", "2606:4700:4700::1111", "2a00:1450:4001::200e"] { XCTAssertTrue(DGPluginPublicAddress.isAllowed(address), address) }
        for address in ["0.1.2.3", "10.1.2.3", "100.64.0.1", "100.127.255.255", "127.0.0.1", "169.254.169.254", "172.16.1.1", "172.31.255.255", "192.0.0.9", "192.0.2.1", "192.88.99.1", "192.168.1.1", "198.18.1.1", "198.19.255.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255", "::", "::1", "::ffff:8.8.8.8", "::ffff:808:808", "64:ff9b::808:808", "2001::1", "2001:db8::1", "2002:0808:0808::1", "3fff::1", "fc00::1", "fe80::1", "ff02::1", "2001:4860::1%en0", "010.1.1.1", "127.1", "0x7f000001", "2130706433", "1.2.3.256", "2001:::1", "2001::1::2"] { XCTAssertFalse(DGPluginPublicAddress.isAllowed(address), address) }
    }

    func testExactGrantedOriginAndRestrictedRequestShape() throws {
        let valid: DGPluginJSON = .object(["url": .string("https://example.org/data?q=a%20b")])
        let request = try DGPluginPublicRequest.validated(valid, allowedOrigins: ["https://example.org"])
        XCTAssertEqual(request.host, "example.org")
        XCTAssertEqual(request.target, "/data?q=a%20b")
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(String(data: request.wireBytes, encoding: .utf8), "GET /data?q=a%20b HTTP/1.1\r\nHost: example.org\r\nAccept: application/json, text/plain;q=0.9\r\nAccept-Encoding: identity\r\nConnection: close\r\nUser-Agent: DonutgramPluginPublic/1\r\n\r\n")
        for url in ["http://example.org/", "https://example.org.attacker.test/", "https://example.org@evil.org/", "https://example.org:444/", "https://example.org/#secret", "https://EXAMPLE.org/", "https://example.org./", "https://127.0.0.1/", "https://example.org/\r\nInjected:yes", "https://example.org//other", "https://example.org\\@evil.org/"] {
            XCTAssertThrowsError(try DGPluginPublicRequest.validated(.object(["url": .string(url)]), allowedOrigins: ["https://example.org"]), url)
        }
        for extra in ["headers", "body", "accountId", "cookies"] { XCTAssertThrowsError(try DGPluginPublicRequest.validated(.object(["url": .string("https://example.org/"), extra: .string("x")]), allowedOrigins: ["https://example.org"])) }
        XCTAssertThrowsError(try DGPluginPublicRequest.validated(.object(["url": .string("https://example.org/"), "method": .string("POST")]), allowedOrigins: ["https://example.org"]))
        XCTAssertThrowsError(try DGPluginPublicRequest.validated(valid, allowedOrigins: []))
    }

    func testContentLengthAndIncrementalCompletion() throws {
        let prefix = Data("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Type: text/plain\r\nSet-Cookie: no=exposure\r\n\r\nhe".utf8)
        XCTAssertNil(try DGPluginHTTPResponse.parse(prefix, method: "GET", endOfStream: false))
        let response = try XCTUnwrap(DGPluginHTTPResponse.parse(prefix + Data("llo".utf8), method: "GET", endOfStream: false))
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, Data("hello".utf8))
        XCTAssertEqual(response.headers, ["content-type": "text/plain"])
        XCTAssertThrowsError(try DGPluginHTTPResponse.parse(prefix, method: "GET", endOfStream: true))
        XCTAssertThrowsError(try DGPluginHTTPResponse.parse(prefix + Data("llo!".utf8), method: "GET", endOfStream: true))
    }

    func testRepeatedResponseMetadataAndStrictFraming() throws {
        let wire = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\nVary: Accept\r\nVary: Origin\r\nCache-Control: public\r\nCache-Control: max-age=60\r\n\r\nok"
        let response = try XCTUnwrap(DGPluginHTTPResponse.parse(Data(wire.utf8), method: "GET", endOfStream: true))
        XCTAssertEqual(response.body, Data("ok".utf8))
        XCTAssertEqual(response.headers, ["cache-control": "public, max-age=60"])
        for header in ["Content-Length: 0\r\ncOnTeNt-LeNgTh: 0", "Transfer-Encoding: chunked\r\nTransfer-Encoding: chunked", "Content-Encoding: identity\r\nContent-Encoding: gzip"] {
            XCTAssertThrowsError(try DGPluginHTTPResponse.parse(Data(("HTTP/1.1 200 OK\r\n" + header + "\r\n\r\n").utf8), method: "GET", endOfStream: true))
        }
    }

    func testChunkedBodyAndClosureFraming() throws {
        let prefix = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
        let wire = Data((prefix + "2\r\nhe\r\n3\r\nllo\r\n0\r\n\r\n").utf8)
        for count in 1 ..< wire.count { XCTAssertNil(try DGPluginHTTPResponse.parse(wire.prefix(count), method: "GET", endOfStream: false), "prefix \(count)") }
        XCTAssertEqual(try DGPluginHTTPResponse.parse(wire, method: "GET", endOfStream: true)?.body, Data("hello".utf8))
        let close = Data("HTTP/1.0 200 OK\r\n\r\nhello".utf8)
        XCTAssertNil(try DGPluginHTTPResponse.parse(close, method: "GET", endOfStream: false))
        XCTAssertEqual(try DGPluginHTTPResponse.parse(close, method: "GET", endOfStream: true)?.body, Data("hello".utf8))
        for body in ["1;x=y\r\na\r\n0\r\n\r\n", "1\r\na!\r\n0\r\n\r\n", "0\r\nX-Trailer: a\r\n\r\n"] { XCTAssertThrowsError(try DGPluginHTTPResponse.parse(Data((prefix + body).utf8), method: "GET", endOfStream: true)) }
    }

    func testDeniesRedirectsAmbiguousHeadersAndUnboundedBodies() {
        for headers in ["HTTP/1.1 302 Found\r\nLocation: https://127.0.0.1/", "HTTP/1.1 101 Upgrade", "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nContent-Length: 0", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 0", "HTTP/1.1 200 OK\r\nContent-Encoding: gzip", "HTTP/1.1 200 OK\r\nContent-Length: 9999999999", "HTTP/1.1 200 OK\r\n folded: no"] {
            XCTAssertThrowsError(try DGPluginHTTPResponse.parse(Data((headers + "\r\n\r\n").utf8), method: "GET", endOfStream: true))
        }
        XCTAssertThrowsError(try DGPluginHTTPResponse.parse(Data(repeating: 65, count: 16385), method: "GET", endOfStream: false))
        let oversized = Data("HTTP/1.1 200 OK\r\n\r\n".utf8) + Data(repeating: 65, count: 48 * 1024 + 1)
        XCTAssertThrowsError(try DGPluginHTTPResponse.parse(oversized, method: "GET", endOfStream: true))
    }

    func testHeadAndJsonBridgeBounds() throws {
        XCTAssertEqual(try DGPluginHTTPResponse.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 2000000\r\n\r\n".utf8), method: "HEAD", endOfStream: false)?.body, Data())
        XCTAssertThrowsError(try DGPluginHTTPResponse.parse(Data("HTTP/1.1 204 No Content\r\n\r\nx".utf8), method: "GET", endOfStream: true))
        let binary = try XCTUnwrap(DGPluginHTTPResponse.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\n".utf8) + Data([255]), method: "GET", endOfStream: true))
        XCTAssertThrowsError(try binary.json(url: "https://example.org/"))
        let escaping = try XCTUnwrap(DGPluginHTTPResponse.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 49152\r\n\r\n".utf8) + Data(repeating: 0, count: 49152), method: "GET", endOfStream: true))
        XCTAssertThrowsError(try escaping.json(url: "https://example.org/"))
    }
}
