import Foundation
import DGPluginModel
import DGPluginArchiveC

struct DGBoundedArchive {
    let data: Data

    func files() throws -> [String: Data] {
        guard self.data.count >= 22, self.data.count <= 8 * 1024 * 1024 else { throw self.invalid() }
        let bytes = [UInt8](self.data)
        func u16(_ offset: Int) throws -> Int {
            guard offset >= 0, offset + 2 <= bytes.count else { throw self.invalid() }
            return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }
        func u32(_ offset: Int) throws -> Int {
            return try u16(offset) | (u16(offset + 2) << 16)
        }
        func extras(_ start: Int, count: Int) throws {
            var offset = start
            let end = start + count
            guard end <= bytes.count else { throw self.invalid() }
            while offset < end {
                guard offset + 4 <= end else { throw self.invalid() }
                let identifier = try u16(offset)
                let size = try u16(offset + 2)
                guard offset + 4 + size <= end, ![0x0001, 0x000d].contains(identifier) else { throw self.invalid() }
                offset += 4 + size
            }
        }
        var end: Int?
        for index in stride(from: bytes.count - 22, through: max(0, bytes.count - 65557), by: -1) {
            if try u32(index) == 0x06054b50, try index + 22 + u16(index + 20) == bytes.count { end = index; break }
        }
        guard let end else { throw self.invalid() }
        guard try u16(end + 4) == 0, try u16(end + 6) == 0 else { throw self.invalid() }
        let count = try u16(end + 10)
        let centralSize = try u32(end + 12)
        let centralStart = try u32(end + 16)
        guard count > 0, count <= 128, try u16(end + 8) == count, centralStart + centralSize == end else { throw self.invalid() }
        var cursor = centralStart
        var expanded = 0
        var result: [String: Data] = [:]
        var names = Set<String>()
        var spans: [Range<Int>] = []
        for _ in 0 ..< count {
            guard try u32(cursor) == 0x02014b50 else { throw self.invalid() }
            let flags = try u16(cursor + 8)
            let method = try u16(cursor + 10)
            let crc = try u32(cursor + 16)
            let compressed = try u32(cursor + 20)
            let size = try u32(cursor + 24)
            let nameSize = try u16(cursor + 28)
            let extraSize = try u16(cursor + 30)
            let commentSize = try u16(cursor + 32)
            let external = try u32(cursor + 38)
            let local = try u32(cursor + 42)
            guard flags & ~0x800 == 0, method == 0 || method == 8, try u16(cursor + 34) == 0,
                  nameSize > 0, nameSize <= 240, size <= 1024 * 1024, compressed <= 8 * 1024 * 1024,
                  cursor + 46 + nameSize + extraSize + commentSize <= end else { throw self.invalid() }
            let rawName = Data(bytes[cursor + 46 ..< cursor + 46 + nameSize])
            try extras(cursor + 46 + nameSize, count: extraSize)
            guard let name = String(data: rawName, encoding: .utf8) else { throw self.invalid() }
            let isDirectory = name.hasSuffix("/")
            let cleanName = isDirectory ? String(name.dropLast()) : name
            try DGPluginInstaller.validatePath(cleanName)
            let normalized = cleanName.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(normalized).inserted else { throw self.invalid() }
            let fileType = (external >> 16) & 0xf000
            guard fileType == 0 || fileType == (isDirectory ? 0x4000 : 0x8000) else { throw self.invalid() }
            guard size <= max(1024 * 1024, compressed * 200), expanded <= 4 * 1024 * 1024 - size else { throw self.invalid() }
            expanded += size
            guard local >= 0, local + 30 <= centralStart, try u32(local) == 0x04034b50,
                  try u16(local + 6) == flags, try u16(local + 8) == method, try u32(local + 14) == crc,
                  try u32(local + 18) == compressed, try u32(local + 22) == size, try u16(local + 26) == nameSize else { throw self.invalid() }
            let localExtra = try u16(local + 28)
            try extras(local + 30 + nameSize, count: localExtra)
            let start = local + 30 + nameSize + localExtra
            let stop = start + compressed
            guard start <= centralStart, stop <= centralStart,
                  Data(bytes[local + 30 ..< local + 30 + nameSize]) == rawName,
                  !spans.contains(where: { $0.overlaps(local ..< stop) }) else { throw self.invalid() }
            spans.append(local ..< stop)
            let packed = Data(bytes[start ..< stop])
            var contents: Data
            if method == 0 {
                guard compressed == size else { throw self.invalid() }
                contents = packed
            } else {
                contents = Data(count: max(1, size))
                let valid = contents.withUnsafeMutableBytes { output in
                    packed.withUnsafeBytes { input in
                        dg_plugin_inflate(input.bindMemory(to: UInt8.self).baseAddress, packed.count, output.bindMemory(to: UInt8.self).baseAddress, size)
                    }
                }
                guard valid == 1 else { throw self.invalid() }
                contents.count = size
            }
            let actualCRC = contents.withUnsafeBytes { dg_plugin_crc32($0.bindMemory(to: UInt8.self).baseAddress, contents.count) }
            guard actualCRC == UInt32(crc) else { throw self.invalid() }
            if isDirectory { guard size == 0 else { throw self.invalid() } }
            else { result[name] = contents }
            cursor += 46 + nameSize + extraSize + commentSize
        }
        guard cursor == end else { throw self.invalid() }
        let paths = Set(result.keys.map { $0.lowercased() })
        for name in result.keys {
            var parent = (name as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                guard !paths.contains(parent.lowercased()) else { throw self.invalid() }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return result
    }

    private func invalid() -> DGPluginError { return DGPluginError(code: "invalid_archive", message: "invalid or oversized plugin archive") }
}
