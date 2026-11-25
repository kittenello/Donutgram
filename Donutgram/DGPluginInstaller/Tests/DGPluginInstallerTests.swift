import Foundation
import XCTest
#if canImport(CryptoKit)
import CryptoKit
#endif
import DGPluginModel
@testable import DGPluginInstaller

final class DGPluginInstallerTests: XCTestCase {
    private let metadata = "{\"kind\":\"donutgram.plugin\",\"schemaVersion\":1,\"id\":\"dev.example.test\",\"name\":\"test\",\"version\":\"1.0.0\",\"description\":\"test plugin\",\"apiVersion\":\"^1.0.0\",\"permissions\":[]}"

    private func source(_ metadata: String? = nil, suffix: String = "throw new Error('preview must never run');") -> Data {
        return Data(("const _plugin = \"donutgram\";\nconst manifest = " + (metadata ?? self.metadata) + ";\n" + suffix).utf8)
    }

    func testNativeSHA256KnownVectors() {
        XCTAssertEqual(DGPluginInstaller.digest(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(DGPluginInstaller.digest(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testStaticPreviewDoesNotRunTopLevelCode() throws {
        let data = self.source()
        let result = try DGPluginInstaller.preview(data: data, fileName: "example.donut.js")
        XCTAssertEqual(result.manifest.id, "dev.example.test")
        XCTAssertEqual(result.originalData, data)
        XCTAssertEqual(result.files["main.js"], data)
        XCTAssertEqual(result.trust, "authorUnverified")
        XCTAssertEqual(result.publisherIdentity, "unverified")
        XCTAssertNil(result.iconData)
    }

    func testNormalJavascriptIsNotAPlugin() {
        XCTAssertThrowsError(try DGPluginInstaller.preview(data: self.source(), fileName: "example.js"))
        XCTAssertThrowsError(try DGPluginInstaller.preview(data: Data("const _plugin = \"other\";".utf8), fileName: "example.donut.js"))
    }

    func testPreviewOwnsMutableInputBytes() throws {
        let original = self.source()
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: original.count, alignment: 1)
        defer { pointer.deallocate() }
        original.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self), count: original.count)
        let external = Data(bytesNoCopy: pointer, count: original.count, deallocator: .none)
        let package = try DGPluginInstaller.preview(data: external, fileName: "example.donut.js")
        pointer.storeBytes(of: UInt8(0), as: UInt8.self)
        XCTAssertEqual(package.originalData, original)
        XCTAssertEqual(package.digest, DGPluginInstaller.digest(original))
    }

    func testDuplicateAndComputedMetadataRejected() {
        let fragments = [
            self.metadata.replacingOccurrences(of: "\"name\":\"test\"", with: "\"name\":\"first\",\"name\":\"second\""),
            self.metadata.replacingOccurrences(of: "\"name\":\"test\"", with: "\"name\":getName()"),
            self.metadata.replacingOccurrences(of: "\"name\":\"test\"", with: "get name(){return 'test'}"),
            self.metadata.replacingOccurrences(of: "\"name\":\"test\"", with: "...globalThis"),
            self.metadata.replacingOccurrences(of: "\"name\":\"test\"", with: "\"__proto__\":{}"),
            self.metadata.replacingOccurrences(of: "\"name\":\"test\"", with: "\"name\":\"test\"+\"suffix\"")
        ]
        for fragment in fragments {
            XCTAssertThrowsError(try DGPluginInstaller.preview(data: self.source(fragment), fileName: "example.donut.js"))
        }
    }

    func testForbiddenCapabilitiesAndProfileCombinationsRejected() {
        for permission in [
            "{\"capability\":\"account.logout\",\"scope\":\"all\",\"reason\":\"test\"}",
            "{\"capability\":\"composer.read\",\"scope\":\"all\",\"reason\":\"test\"}",
            "{\"capability\":\"network.public\",\"scope\":\"declaredOrigins\",\"reason\":\"test\",\"origins\":[\"https://example.org\"]}"
        ] {
            let metadata = self.metadata.replacingOccurrences(of: "\"permissions\":[]", with: "\"permissions\":[" + permission + "]")
            XCTAssertThrowsError(try DGPluginInstaller.preview(data: self.source(metadata), fileName: "example.donut.js"))
        }
        let privateNetwork = self.metadata.replacingOccurrences(of: "\"permissions\":[]", with: "\"profile\":\"publicNetwork\",\"permissions\":[{\"capability\":\"composer.read\",\"scope\":\"activeComposer\",\"reason\":\"test\"}]")
        XCTAssertThrowsError(try DGPluginInstaller.preview(data: self.source(privateNetwork), fileName: "example.donut.js"))
    }

    func testUnknownFieldsAndIncompatibleVersionsRejected() {
        for metadata in [
            self.metadata.replacingOccurrences(of: "\"name\":\"test\"", with: "\"unknown\":true,\"name\":\"test\""),
            self.metadata.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
            self.metadata.replacingOccurrences(of: "\"1.0.0\"", with: "\"1.0.0-01\""),
            self.metadata.replacingOccurrences(of: "\"apiVersion\":\"^1.0.0\"", with: "\"apiVersion\":\"^9.0.0\""),
            self.metadata.replacingOccurrences(of: "\"name\":\"test\"", with: "\"minClientVersion\":\"999.0\",\"name\":\"test\"")
        ] {
            XCTAssertThrowsError(try DGPluginInstaller.preview(data: self.source(metadata), fileName: "example.donut.js"))
        }
    }

    func testArchivePreviewAndBrokenOptionalIcon() throws {
        let metadata = self.metadata.replacingOccurrences(of: "\"name\":\"test\"", with: "\"icon\":\"assets/icon.png\",\"name\":\"test\"")
        let archive = self.zip([( "manifest.json", Data(metadata.utf8)), ("main.js", self.source()), ("assets/icon.png", Data("not a png".utf8))])
        let result = try DGPluginInstaller.preview(data: archive, fileName: "example.dgplugin")
        XCTAssertEqual(result.files.count, 3)
        XCTAssertNil(result.iconData)
    }

    func testTraversalCaseCollisionAndCorruptionRejected() {
        for paths in [["../main.js"], ["/main.js"], ["a\\main.js"], ["main.js", "MAIN.js"], ["a.js", "A.js/main.js"], ["main.js", "main.js"]] {
            let archive = self.zip(paths.map { ($0, self.source()) })
            XCTAssertThrowsError(try DGBoundedArchive(data: archive).files())
        }
        var corrupt = self.zip([("main.js", self.source())])
        corrupt[35] ^= 1
        XCTAssertThrowsError(try DGBoundedArchive(data: corrupt).files())
        XCTAssertThrowsError(try DGBoundedArchive(data: Data(repeating: 0, count: 21)).files())
    }

    func testUntrustedSignatureAndModifiedCodeRejected() throws {
        #if canImport(CryptoKit)
        let key = Curve25519.Signing.PrivateKey()
        let main = self.source()
        var parser = DGStaticJSONParser(Data(self.metadata.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let canonical = try DGPluginCanonicalJSON.encode(parser.complete())
        var payload = Data("donutgram.plugin.signature.v1\n".utf8)
        for (name, content) in [("main.js", main), ("manifest.json", canonical)] {
            payload.append(Data("\(name.utf8.count):\(name):\(DGPluginInstaller.digest(content))\n".utf8))
        }
        let signature = try key.signature(for: payload)
        let envelope: [String: DGPluginJSON] = ["algorithm": .string("Ed25519"), "canonicalization": .string(DGPluginCanonicalJSON.format), "publicKey": .string(key.publicKey.rawRepresentation.base64EncodedString()), "signature": .string(signature.base64EncodedString())]
        let signatureData = try encoder.encode(DGPluginJSON.object(envelope))
        let archive = self.zip([("manifest.json", Data(self.metadata.utf8)), ("main.js", main), ("signature.json", signatureData)])
        let result = try DGPluginInstaller.preview(data: archive, fileName: "example.dgplugin")
        XCTAssertEqual(result.trust, "signatureVerified")
        XCTAssertEqual(result.publisherIdentity, "ed25519:" + DGPluginInstaller.digest(key.publicKey.rawRepresentation))
        let modified = self.zip([("manifest.json", Data(self.metadata.utf8)), ("main.js", self.source(suffix: "while(true){}")), ("signature.json", signatureData)])
        XCTAssertThrowsError(try DGPluginInstaller.preview(data: modified, fileName: "example.dgplugin"))
        let invalidEnvelope = self.zip([("manifest.json", Data(self.metadata.utf8)), ("main.js", main), ("signature.json", Data("{}".utf8))])
        XCTAssertThrowsError(try DGPluginInstaller.preview(data: invalidEnvelope, fileName: "example.dgplugin"))
        #else
        let envelope: DGPluginJSON = .object(["algorithm": .string("Ed25519"), "canonicalization": .string(DGPluginCanonicalJSON.format), "publicKey": .string(Data(repeating: 0, count: 32).base64EncodedString()), "signature": .string(Data(repeating: 0, count: 64).base64EncodedString())])
        let archive = self.zip([("manifest.json", Data(self.metadata.utf8)), ("main.js", self.source()), ("signature.json", try JSONEncoder().encode(envelope))])
        do {
            _ = try DGPluginInstaller.preview(data: archive, fileName: "example.dgplugin")
            XCTFail("signed package must not bypass unavailable native verification")
        } catch let error as DGPluginError { XCTAssertEqual(error.code, "feature_unavailable") }
        #endif
    }

    func testCrossToolCanonicalSignatureFixture() throws {
        let data = Data(base64Encoded: "ew0KICAiZm9ybWF0IjogImRnLWNhbm9uaWNhbC12MSIsDQogICJ2ZWN0b3JzIjogWw0KICAgIHsNCiAgICAgICJ2YWx1ZSI6IG51bGwsDQogICAgICAiYmFzZTY0IjogImJnPT0iLA0KICAgICAgInNoYTI1NiI6ICIxYjE2YjFkZjUzOGJhMTJkYzNmOTdlZGJiODVjYWE3MDUwZDQ2YzE0ODEzNDI5MGZlYmE4MGY4MjM2YzgzZGI5Ig0KICAgIH0sDQogICAgew0KICAgICAgInZhbHVlIjogdHJ1ZSwNCiAgICAgICJiYXNlNjQiOiAiZEE9PSIsDQogICAgICAic2hhMjU2IjogImUzYjk4YTRkYTMxYTEyN2Q0YmRlNmU0MzAzM2Y2NmJhMjc0Y2FiMGViN2ViMWM3MGVjNDE0MDJiZjYyNzNkZDgiDQogICAgfSwNCiAgICB7DQogICAgICAidmFsdWUiOiBmYWxzZSwNCiAgICAgICJiYXNlNjQiOiAiWmc9PSIsDQogICAgICAic2hhMjU2IjogIjI1MmYxMGM4MzYxMGViY2ExYTA1OWMwYmFlODI1NWViYTJmOTViZTRkMWQ3YmNmYTg5ZDcyNDhhODJkOWYxMTEiDQogICAgfSwNCiAgICB7DQogICAgICAidmFsdWUiOiAtMC4wLA0KICAgICAgImJhc2U2NCI6ICJaQUFBQUFBQUFBQUEiLA0KICAgICAgInNoYTI1NiI6ICIwMTlmNzYxMjc3NTdmNWQyOWRkMzNmYmRjYTIxMWZkYzBlY2U5YjA5Mzk5NWZkYjI3MDZhNWE4ODA1YzBlMmI5Ig0KICAgIH0sDQogICAgew0KICAgICAgInZhbHVlIjogMC4xMjUsDQogICAgICAiYmFzZTY0IjogIlpEL0FBQUFBQUFBQSIsDQogICAgICAic2hhMjU2IjogIjk2YzE1MzEyMDc5OGYxZDdjM2FkZjFhZDkwMTkyNzZmOGI2YzI4OWMzYTc4MDJjOTk4NTM0M2UzNTRkMjJlOTUiDQogICAgfSwNCiAgICB7DQogICAgICAidmFsdWUiOiAxZS0zMCwNCiAgICAgICJiYXNlNjQiOiAiWkRtMFNFdis2OEtnIiwNCiAgICAgICJzaGEyNTYiOiAiMjU4NmI2MGM4Mjc3MWQxZTViNWJmNWRjYzY1OTRlNTZjMzgwNGQ3NzBjNTViNmE0ZTc5N2I4M2ZlNDdlMzdjYyINCiAgICB9LA0KICAgIHsNCiAgICAgICJ2YWx1ZSI6ICLDqS9cbumbqiIsDQogICAgICAiYmFzZTY0IjogImN6YzZ3Nmt2Q3VtYnFnPT0iLA0KICAgICAgInNoYTI1NiI6ICI2MzcwYmM1YmRiYTU3MzM2NzI5NzY1ZjBiN2MyY2JlOGVlODEwNWRhYTdjOGM3M2JlODA0ZGFjOThmY2NiOTIyIg0KICAgIH0sDQogICAgew0KICAgICAgInZhbHVlIjogew0KICAgICAgICAieiI6IDEsDQogICAgICAgICLDpCI6IDIsDQogICAgICAgICJhIjogWw0KICAgICAgICAgIG51bGwsDQogICAgICAgICAgZmFsc2UsDQogICAgICAgICAgew0KICAgICAgICAgICAgIm5lc3RlZCI6IC0yLjc1DQogICAgICAgICAgfQ0KICAgICAgICBdDQogICAgICB9LA0KICAgICAgImJhc2U2NCI6ICJiek02Y3pFNllXRXpPbTVtYnpFNmN6WTZibVZ6ZEdWa1pNQUdBQUFBQUFBQWN6RTZlbVEvOEFBQUFBQUFBSE15T3NPa1pFQUFBQUFBQUFBQSIsDQogICAgICAic2hhMjU2IjogIjJhMWVlMjFiZDRhZmRhNGY1ZWU0NTdiZGQwOTYwNDY3YzkwNDlhMmFlOWMyZGM5MzIzNTEwMDY3ZTg3NTY5OWEiDQogICAgfSwNCiAgICB7DQogICAgICAidmFsdWUiOiB7DQogICAgICAgICLugIAiOiAxLA0KICAgICAgICAi8JCAgCI6IDINCiAgICAgIH0sDQogICAgICAiYmFzZTY0IjogImJ6STZjek02N29DQVpEL3dBQUFBQUFBQWN6UTY4SkNBZ0dSQUFBQUFBQUFBQUE9PSIsDQogICAgICAic2hhMjU2IjogImI4YmRlNDhkZjk5YTRiYmNmMTQ2ZjQxZjkyYmY0NzRlZDVjZjBlYTkzNGZmZmJjYmI4ZmUzNmRlMGU5MWFmYmYiDQogICAgfQ0KICBdLA0KICAiZmlsZXMiOiB7DQogICAgIm1hbmlmZXN0Lmpzb24iOiAiZXlKcmFXNWtJam9pWkc5dWRYUm5jbUZ0TG5Cc2RXZHBiaUlzSW5OamFHVnRZVlpsY25OcGIyNGlPakVzSW1sa0lqb2laR1YyTG1WNFlXMXdiR1V1YzJsbmJtRjBkWEpsTFdacGVIUjFjbVVpTENKdVlXMWxJam9pYzJsbmJtRjBkWEpsSU9tYnFpSXNJblpsY25OcGIyNGlPaUl4TGpBdU1DSXNJbVJsYzJOeWFYQjBhVzl1SWpvaVkzSnZjM010ZEc5dmJDQmpZVzV2Ym1sallXd2dabWw0ZEhWeVpTSXNJbUZ3YVZabGNuTnBiMjRpT2lKZU1TNHdMakFpTENKd1pYSnRhWE56YVc5dWN5STZXMTBzSW5ObGRIUnBibWR6VTJOb1pXMWhJanA3SW5SNWNHVWlPaUp2WW1wbFkzUWlMQ0p3Y205d1pYSjBhV1Z6SWpwN0ltWnlZV04wYVc5dUlqcDdJblI1Y0dVaU9pSnVkVzFpWlhJaUxDSjBhWFJzWlNJNkltWnlZV04wYVc5dUlpd2laR1ZtWVhWc2RDSTZNQzR4TWpVc0ltMXBibWx0ZFcwaU9pMHlMamMxTENKdFlYaHBiWFZ0SWpveFpTc3pNSDE5ZlgwPSIsDQogICAgIm1haW4uanMiOiAiWTI5dWMzUWdYM0JzZFdkcGJpQTlJQ0prYjI1MWRHZHlZVzBpT3lCa1pXWnBibVZRYkhWbmFXNG9lMkZqZEdsMllYUmxLQ2w3ZlgwcE93PT0iLA0KICAgICJzaWduYXR1cmUuanNvbiI6ICJleUpoYkdkdmNtbDBhRzBpT2lKRlpESTFOVEU1SWl3aVkyRnViMjVwWTJGc2FYcGhkR2x2YmlJNkltUm5MV05oYm05dWFXTmhiQzEyTVNJc0luQjFZbXhwWTB0bGVTSTZJbW8zVm5ONE5XUnJSRW81WTNsWFNqWk5MM0IwV1RaNVMyRlRjVTlUWTI0eGNIRm9TVVU1YWtWcVMzYzlJaXdpYzJsbmJtRjBkWEpsSWpvaU9ESkxiSFJEYjBsU1VtVk5aV3hOWmpoTGVVVlFOWGt4YmxBMk5rdE1kWEp6YUZOT2VrRjJkV1ZXYlhWb1ZDOTNTV05KYlZFeFdsTTFRVkZzTlZGRGVFMXpVWEUxWkRCQ2IyRk1UVzVSV0dNMVRFUTNSR2M5UFNKOSINCiAgfSwNCiAgInBheWxvYWRCYXNlNjQiOiAiWkc5dWRYUm5jbUZ0TG5Cc2RXZHBiaTV6YVdkdVlYUjFjbVV1ZGpFS056cHRZV2x1TG1wek9qZ3hORGd3TlRRNE1UVm1NalUyWldNMk1EbGpZek15WldaaE16Qm1ObU0zTVRZMU5ERmtOalU1TTJNMFpUbGpPRGM1TlRCaFpqSXdOVGxoTlRRME1HVUtNVE02YldGdWFXWmxjM1F1YW5OdmJqbzBNVEV5TnpCak1HWmxZalZqTnpka05EazFNR1ptWm1VNU56bGpNV0l4WkdWak1XSmtaVEkyTVRka01HSTFPRFZtT1dFeU9EQTJNMkUxTW1ZeFlXVXdDZz09Ig0KfQ0K")!
        let fixture = try JSONDecoder().decode(DGPluginJSON.self, from: data).objectValue!
        guard case let .array(vectors)? = fixture["vectors"], case let .object(encodedFiles)? = fixture["files"] else { return XCTFail("missing signature fixture") }
        for vector in vectors {
            let fields = vector.objectValue!
            let encoded = try DGPluginCanonicalJSON.encode(fields["value"]!)
            XCTAssertEqual(encoded, Data(base64Encoded: fields["base64"]!.stringValue!)!)
            XCTAssertEqual(DGPluginInstaller.digest(encoded), fields["sha256"]!.stringValue!)
        }
        var files = encodedFiles.mapValues { Data(base64Encoded: $0.stringValue!)! }
        let archive = self.zip(files.map { ($0.key, $0.value) })
        #if canImport(CryptoKit)
        let verified = try DGPluginInstaller.preview(data: archive, fileName: "fixture.dgplugin")
        XCTAssertEqual(verified.trust, "signatureVerified")
        files["main.js"]!.append(Data(";void 0;".utf8))
        XCTAssertThrowsError(try DGPluginInstaller.preview(data: self.zip(files.map { ($0.key, $0.value) }), fileName: "fixture.dgplugin"))
        #else
        do { _ = try DGPluginInstaller.preview(data: archive, fileName: "fixture.dgplugin"); XCTFail("unavailable signature verification accepted") }
        catch let error as DGPluginError { XCTAssertEqual(error.code, "feature_unavailable") }
        #endif
        var envelope = try JSONDecoder().decode(DGPluginJSON.self, from: files["signature.json"]!).objectValue!
        for version in [DGPluginJSON.null, .string("unknown"), .string("json-sorted-keys")] {
            if version == .null { envelope.removeValue(forKey: "canonicalization") } else { envelope["canonicalization"] = version }
            files["signature.json"] = try JSONEncoder().encode(DGPluginJSON.object(envelope))
            do { _ = try DGPluginInstaller.preview(data: self.zip(files.map { ($0.key, $0.value) }), fileName: "fixture.dgplugin"); XCTFail("invalid canonicalization accepted") }
            catch let error as DGPluginError { XCTAssertEqual(error.code, "invalid_signature") }
        }
    }

    func testSizeAndMetadataNestingLimits() {
        XCTAssertThrowsError(try DGPluginInstaller.preview(data: Data(repeating: 0, count: 8 * 1024 * 1024 + 1), fileName: "example.dgplugin"))
        let nested = String(repeating: "[", count: 30) + "null" + String(repeating: "]", count: 30)
        var parser = DGStaticJSONParser(Data(nested.utf8))
        XCTAssertThrowsError(try parser.complete())
    }

    private func zip(_ files: [(String, Data)]) -> Data {
        var local = Data()
        var central = Data()
        func word(_ value: UInt32, width: Int = 4) -> Data { return Data((0 ..< width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
        func crc(_ data: Data) -> UInt32 {
            var result: UInt32 = 0xffffffff
            for byte in data {
                result ^= UInt32(byte)
                for _ in 0 ..< 8 { result = (result >> 1) ^ ((result & 1) == 1 ? 0xedb88320 : 0) }
            }
            return result ^ 0xffffffff
        }
        for (name, data) in files {
            let path = Data(name.utf8)
            let offset = UInt32(local.count)
            let checksum = crc(data)
            local.append(word(0x04034b50))
            local.append(word(20, width: 2)); local.append(word(0x800, width: 2)); local.append(word(0, width: 2))
            local.append(word(0)); local.append(word(checksum)); local.append(word(UInt32(data.count))); local.append(word(UInt32(data.count)))
            local.append(word(UInt32(path.count), width: 2)); local.append(word(0, width: 2)); local.append(path); local.append(data)
            central.append(word(0x02014b50)); central.append(word(20, width: 2)); central.append(word(20, width: 2))
            central.append(word(0x800, width: 2)); central.append(word(0, width: 2)); central.append(word(0))
            central.append(word(checksum)); central.append(word(UInt32(data.count))); central.append(word(UInt32(data.count)))
            central.append(word(UInt32(path.count), width: 2)); central.append(word(0, width: 2)); central.append(word(0, width: 2))
            central.append(word(0, width: 2)); central.append(word(0, width: 2)); central.append(word(0)); central.append(word(offset)); central.append(path)
        }
        let start = UInt32(local.count)
        local.append(central); local.append(word(0x06054b50)); local.append(word(0)); local.append(word(UInt32(files.count), width: 2)); local.append(word(UInt32(files.count), width: 2))
        local.append(word(UInt32(central.count))); local.append(word(start)); local.append(word(0, width: 2))
        return local
    }
}
