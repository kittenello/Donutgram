import Foundation

/// A remote file chosen by an extractor. Size and dimensions are what the service reported.
struct DGRemoteFile: Equatable {
    let url: URL
    let expectedSize: Int64?
    let width: Int
    let height: Int
    let alternateURLs: [URL]

    init(url: URL, expectedSize: Int64?, width: Int, height: Int, alternateURLs: [URL] = []) {
        self.url = url
        self.expectedSize = expectedSize
        self.width = width
        self.height = height
        self.alternateURLs = alternateURLs.filter { $0 != url }
    }
}

/// A small JPEG rendered on device (video preview).
public struct DGJPEGImage {
    public let data: Data
    public let width: Int
    public let height: Int
}

/// JSON numbers or numeric strings as Int64: TikTok and YouTube send sizes as strings ("5272191").
/// Mirrors `int_value` in the Python reference (booleans are not numbers).
func dgIntValue(_ value: Any?) -> Int64? {
    if let number = value as? NSNumber {
        if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
            return nil
        }
        return number.int64Value
    }
    if let string = value as? String {
        return Int64(string.trimmingCharacters(in: .whitespaces))
    }
    return nil
}

/// Non-empty path segments ("/@/video/1" -> ["@", "video", "1"]).
func dgPathSegments(_ path: String) -> [String] {
    return path.split(separator: "/").map(String.init)
}

private let dgShortCodeCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
private let dgYouTubeIdCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

/// Code of a vm./vt.tiktok.com or tiktok.com/t/ short link.
func dgIsShortCode(_ value: String) -> Bool {
    return !value.isEmpty && value.unicodeScalars.allSatisfy { dgShortCodeCharacters.contains($0) }
}

/// 11-character YouTube video id.
func dgIsYouTubeVideoId(_ value: String) -> Bool {
    return value.unicodeScalars.count == 11 && value.unicodeScalars.allSatisfy { dgYouTubeIdCharacters.contains($0) }
}

/// Numeric TikTok post id: 10-25 ASCII digits.
func dgIsTikTokItemId(_ value: String) -> Bool {
    let scalars = value.unicodeScalars
    return scalars.count >= 10 && scalars.count <= 25 && scalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
}
