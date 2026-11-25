import Foundation
import WinSDK
import DGPluginModel
import DGPluginInstaller

private struct Generator {
    var state: UInt64 = 0xd06a2026
    mutating func next(_ upper: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 16) % UInt64(upper))
    }
    mutating func mutate(_ source: Data, iteration: Int) -> Data {
        if iteration % 17 == 0 { return source }
        var bytes = [UInt8](source)
        for _ in 0 ... next(4) {
            switch next(4) {
            case 0: if !bytes.isEmpty { bytes[next(bytes.count)] = UInt8(next(256)) }
            case 1: if !bytes.isEmpty { bytes.remove(at: next(bytes.count)) }
            case 2: if bytes.count < 8192 { bytes.insert(UInt8(next(256)), at: next(bytes.count + 1)) }
            default: if !bytes.isEmpty { bytes.removeLast(next(bytes.count + 1)) }
            }
        }
        return Data(bytes)
    }
}

private struct FuzzFailure: Error { let message: String }
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw FuzzFailure(message: message) }
}
private func rejected(_ name: String, _ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw FuzzFailure(message: "mandatory rejection failed: " + name)
}
private func verify(_ package: DGVerifiedPluginPackage, bytes: Data) throws {
    try check(package.originalData == bytes && package.digest == DGPluginInstaller.digest(bytes), "package ownership/digest")
    try check(package.files.count <= 128 && package.files.values.reduce(0, { $0 + $1.count }) <= 4 * 1024 * 1024, "expanded package bounds")
    for (path, content) in package.files {
        let pieces = path.components(separatedBy: "/")
        try check(!path.hasPrefix("/") && !path.contains("\\") && !pieces.contains("") && !pieces.contains(".") && !pieces.contains("..") && content.count <= 1024 * 1024, "accepted path/file bounds")
    }
    var changed = bytes
    if !changed.isEmpty { changed[0] ^= 255 }
    try check(package.originalData == bytes, "accepted package aliases caller mutation")
}
private func verify(_ state: DGPluginRenderedState) throws {
    var stack = state.nodes.map { ($0, 0) }
    var count = 0
    while let (node, depth) = stack.popLast() {
        count += 1
        try check(count <= 128 && depth <= 6, "accepted rendered tree bounds")
        stack.append(contentsOf: node.children.map { ($0, depth + 1) })
    }
}

@main
private enum FuzzMain {
    static func main() {
        do { try run() }
        catch { FileHandle.standardError.write(Data("production fuzz failed: \(error)\n".utf8)); ExitProcess(1) }
    }

    static func run() throws {
        let start = ProcessInfo.processInfo.systemUptime
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let uiFixtures = URL(fileURLWithPath: CommandLine.arguments[2])
        let metadata = "{\"kind\":\"donutgram.plugin\",\"schemaVersion\":1,\"id\":\"dev.example.fuzz\",\"name\":\"fuzz\",\"version\":\"1.0.0\",\"description\":\"fuzz fixture\",\"apiVersion\":\"^1.0.0\",\"permissions\":[]}"
        let prefix = "const _plugin=\"donutgram\";const manifest="
        let valid = Data((prefix + metadata + ";globalThis.previewExecuted=true;while(true){}").utf8)
        try verify(DGPluginInstaller.preview(data: valid, fileName: "fuzz.donut.js"), bytes: valid)
        for value in ["(()=>{throw Error('executed')})()", "{get name(){throw Error('executed')}}", "{...{}}", "{\"kind\":\"donutgram.plugin\",\"kind\":\"duplicate\"}"] {
            try rejected("static expression/duplicate metadata") { _ = try DGPluginInstaller.preview(data: Data((prefix + value + ";").utf8), fileName: "fuzz.donut.js") }
        }
        let archive = try Data(contentsOf: directory.appendingPathComponent("valid.deflate.dgplugin"))
        try verify(DGPluginInstaller.preview(data: archive, fileName: "fuzz.dgplugin"), bytes: archive)
        for name in ["traversal", "case-collision", "expanded-limit", "file-count", "nested", "symlink", "mismatched-local-crc"] {
            let bytes = try Data(contentsOf: directory.appendingPathComponent(name + ".dgplugin"))
            try rejected("hostile ZIP " + name) { _ = try DGPluginInstaller.preview(data: bytes, fileName: "fuzz.dgplugin") }
        }
        for text in ["1e999", "{", String(repeating: "[", count: 70) + "0" + String(repeating: "]", count: 70)] {
            try rejected("bridge nonfinite/malformed/depth") { _ = try JSONDecoder().decode(DGPluginJSON.self, from: Data(text.utf8)) }
        }
        struct PageFixture: Decodable { let name: String; let page: DGPluginJSON; let valid: Bool }
        let fixtures = try JSONDecoder().decode([PageFixture].self, from: Data(contentsOf: uiFixtures))
        for fixture in fixtures {
            var accepted = false
            do { try verify(DGPluginRenderedState(page: fixture.page, pluginName: "fuzz", validity: { true }, callback: { _, _ in })); accepted = true }
            catch let error as FuzzFailure { throw error } catch {}
            try check(accepted == fixture.valid, "shared UI oracle: " + fixture.name)
        }
        var random = Generator()
        let bridgeSeeds = [Data("{\"id\":1,\"method\":\"settings.set\",\"params\":{\"values\":{\"x\":[null,true,0.125,\"雪\"]}}}".utf8), Data("[]".utf8), Data(String(repeating: "[", count: 60).utf8) + Data("0".utf8) + Data(String(repeating: "]", count: 60).utf8)]
        let page: DGPluginJSON = .object(["id": .string("fuzz"), "title": .string("fuzz"), "nodes": .array([.object(["id": .string("text"), "type": .string("text"), "text": .string("passive 雪")])])])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let pageBytes = try encoder.encode(page)
        var accepted = [0, 0, 0, 0]
        for iteration in 0 ..< 1000 {
            try check(ProcessInfo.processInfo.systemUptime - start < 10, "fuzz exceeded ten-second budget")
            let source = random.mutate(iteration % 2 == 0 ? valid : Data(metadata.utf8), iteration: iteration)
            do { try verify(DGPluginInstaller.preview(data: source, fileName: "fuzz.donut.js"), bytes: source); accepted[0] += 1 }
            catch let error as FuzzFailure { throw error } catch {}
            let zip = random.mutate(archive, iteration: iteration)
            do { try verify(DGPluginInstaller.preview(data: zip, fileName: "fuzz.dgplugin"), bytes: zip); accepted[1] += 1 }
            catch let error as FuzzFailure { throw error } catch {}
            let bridge = random.mutate(bridgeSeeds[random.next(bridgeSeeds.count)], iteration: iteration)
            do {
                let decoded = try JSONDecoder().decode(DGPluginJSON.self, from: bridge)
                let encoded = try JSONEncoder().encode(decoded)
                let restored = try JSONDecoder().decode(DGPluginJSON.self, from: encoded)
                try check(restored == decoded, "accepted bridge roundtrip")
                accepted[2] += 1
            } catch let error as FuzzFailure { throw error } catch {}
            let candidate = random.mutate(pageBytes, iteration: iteration)
            let value = (try? JSONDecoder().decode(DGPluginJSON.self, from: candidate)) ?? .string(String(decoding: candidate, as: UTF8.self))
            do { try verify(DGPluginRenderedState(page: value, pluginName: "fuzz", validity: { true }, callback: { _, _ in })); accepted[3] += 1 }
            catch let error as FuzzFailure { throw error } catch {}
        }
        try check(accepted.allSatisfy { $0 > 0 && $0 < 1000 }, "mutations did not exercise both acceptance and rejection")
        print("production fuzz seed=0xd06a2026 parser=1000 zip=1000 bridge=1000 ui=1000 accepted=\(accepted) sharedUI=\(fixtures.count) elapsed=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime - start))s")
    }
}
