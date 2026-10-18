import CryptoKit
import Foundation

/// What a TikTok post contains: one video (file + duration in seconds) or a photo carousel.
enum DGTikTokItem: Equatable {
    case video(DGRemoteFile, Double)
    case photos([DGRemoteFile])
}

/// Tries TikTok first, then resolves the original link through TikWM if TikTok blocks access.
enum DGTikTokExtractor {
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    private static let rehydrationMarker = "<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\""
    /// TikTok's Akamai edge answers some requests with HTTP 200 and a "Site Maintenance" page carrying this line.
    private static let deniedMarker = "Please contact your administrator with the error code"

    static func itemId(fromPathSegments segments: [String]) -> String? {
        if segments.count >= 3 && segments[0].hasPrefix("@") && (segments[1] == "video" || segments[1] == "photo") && dgIsTikTokItemId(segments[2]) {
            return segments[2]
        }
        if segments.count == 2 && segments[0] == "v" && segments[1].hasSuffix(".html") {
            let candidate = String(segments[1].dropLast(5))
            if dgIsTikTokItemId(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Item id of a post link or of the page a short link redirected to; nil for the home page (expired link).
    static func itemId(from url: URL) -> String? {
        if let itemId = DGTikTokExtractor.itemId(fromPathSegments: dgPathSegments(url.path)) {
            return itemId
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let shared = components?.queryItems?.first(where: { $0.name == "share_item_id" })?.value, dgIsTikTokItemId(shared) {
            return shared
        }
        return nil
    }

    /// One page serves videos and photo posts; "/photo/<id>" has no data and the author name is not needed.
    static func pageURL(itemId: String) -> URL? {
        return URL(string: "https://www.tiktok.com/@/video/\(itemId)")
    }

    static func pageRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(DGTikTokExtractor.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// CDN requests need the page's cookies (same DGMediaFetcher) and a tiktok.com referer, otherwise 403.
    static func mediaRequest(_ url: URL) -> URLRequest {
        var request = DGTikTokExtractor.pageRequest(url)
        request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
        return request
    }

    static func parsePage(_ html: String) -> Result<DGTikTokItem, DGLinkDownloadError> {
        guard let marker = html.range(of: DGTikTokExtractor.rehydrationMarker),
              let openEnd = html[marker.upperBound...].firstIndex(of: ">") else {
            return .failure(html.contains(DGTikTokExtractor.deniedMarker) ? .tiktokPageDenied : .tiktokNoData)
        }
        let jsonStart = html.index(after: openEnd)
        guard let close = html.range(of: "</script>", range: jsonStart ..< html.endIndex),
              let data = String(html[jsonStart ..< close.lowerBound]).data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let scope = root["__DEFAULT_SCOPE__"] as? [String: Any],
              let detail = scope["webapp.video-detail"] as? [String: Any] else {
            return .failure(.tiktokNoData)
        }
        let status = dgIntValue(detail["statusCode"]) ?? 0
        if status == 10204 {
            return .failure(.tiktokNotFound)
        }
        if status == 10222 {
            return .failure(.tiktokPrivate)
        }
        if status != 0 {
            return .failure(.tiktokStatus(Int(status)))
        }
        guard let itemInfo = detail["itemInfo"] as? [String: Any], let item = itemInfo["itemStruct"] as? [String: Any] else {
            return .failure(.tiktokNoData)
        }
        if let imagePost = item["imagePost"] as? [String: Any] {
            var files: [DGRemoteFile] = []
            for entry in (imagePost["images"] as? [Any]) ?? [] {
                guard let image = entry as? [String: Any],
                      let imageURL = image["imageURL"] as? [String: Any],
                      let first = (imageURL["urlList"] as? [Any])?.first as? String,
                      let url = URL(string: first) else {
                    return .failure(.tiktokNoData)
                }
                files.append(DGRemoteFile(url: url, expectedSize: nil, width: Int(dgIntValue(image["imageWidth"]) ?? 0), height: Int(dgIntValue(image["imageHeight"]) ?? 0)))
            }
            if files.isEmpty {
                return .failure(.tiktokNoData)
            }
            return .success(.photos(files))
        }
        let video = (item["video"] as? [String: Any]) ?? [:]
        let duration = Double(dgIntValue(video["duration"]) ?? 0)
        let playAddr = DGTikTokExtractor.mediaURLs(video["playAddr"].map { [$0] } ?? [])
        var best: (bitrate: Int64, file: DGRemoteFile)?
        for entry in (video["bitrateInfo"] as? [Any]) ?? [] {
            guard let variant = entry as? [String: Any],
                  let codec = variant["CodecType"] as? String, codec.lowercased().hasPrefix("h264"),
                  let play = variant["PlayAddr"] as? [String: Any] else {
                continue
            }
            let urls = DGTikTokExtractor.mediaURLs((play["UrlList"] as? [Any]) ?? [])
            guard let first = urls.first else {
                continue
            }
            let bitrate = dgIntValue(variant["Bitrate"]) ?? 0
            if let current = best, current.bitrate >= bitrate {
                continue
            }
            // The other CDN copies of this variant, then the default stream, in case a CDN refuses this network.
            let alternates = Array(urls.dropFirst()) + playAddr.filter { !urls.contains($0) }
            best = (bitrate, DGRemoteFile(url: first, expectedSize: dgIntValue(play["DataSize"]), width: Int(dgIntValue(play["Width"]) ?? 0), height: Int(dgIntValue(play["Height"]) ?? 0), alternateURLs: alternates))
        }
        if let best {
            return .success(.video(best.file, duration))
        }
        if let first = playAddr.first {
            return .success(.video(DGRemoteFile(url: first, expectedSize: nil, width: Int(dgIntValue(video["width"]) ?? 0), height: Int(dgIntValue(video["height"]) ?? 0)), duration))
        }
        return .failure(.tiktokNoData)
    }

    /// Every https link of a file, in TikTok's order. Links on www.tiktok.com itself (/aweme/v1/play/) answer 403
    /// outside a browser session and yt-dlp drops them too; the others are separate CDN copies.
    static func mediaURLs(_ values: [Any]) -> [URL] {
        var urls: [URL] = []
        for value in values {
            guard let string = value as? String, let url = URL(string: string), url.scheme == "https",
                  let host = url.host, host.lowercased() != "www.tiktok.com", !urls.contains(url) else {
                continue
            }
            urls.append(url)
        }
        return urls
    }

    /// The "Please wait..." bot check instead of the page.
    static func isBotCheck(_ html: String) -> Bool {
        if html.contains(DGTikTokExtractor.rehydrationMarker) {
            return false
        }
        return DGTikTokExtractor.elementAttribute(html, id: "cs", attribute: "class") != nil || html.contains("Please wait...")
    }

    /// TikTok's bot check makes the browser find `n` with SHA-256(a + "n") = c, store the answer in a cookie and
    /// reload. Solved the way yt-dlp does it (`_solve_challenge_and_set_cookies`): the challenge is base64 JSON in the
    /// class of `#cs`, the cookie name is the class of `#wci`, and `#rci`/`#rs` may name a second cookie and its value.
    /// Nil when there is no challenge this code can answer.
    static func challengeCookies(_ html: String) -> [HTTPCookie]? {
        guard let encoded = DGTikTokExtractor.elementAttribute(html, id: "cs", attribute: "class"),
              let json = DGTikTokExtractor.decodeBase64(encoded),
              let challenge = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              challenge["d"] == nil,
              let values = challenge["v"] as? [String: Any],
              let prefix = (values["a"] as? String).flatMap(DGTikTokExtractor.decodeBase64),
              let expected = (values["c"] as? String).flatMap(DGTikTokExtractor.decodeBase64),
              let name = DGTikTokExtractor.elementAttribute(html, id: "wci", attribute: "class"), !name.isEmpty,
              let answer = DGTikTokExtractor.solveChallenge(prefix: prefix, expected: expected) else {
            return nil
        }
        // The challenge text with the answer added last, as yt-dlp writes it (json.dumps keeps the key order).
        var text = String(decoding: json, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasSuffix("}") else {
            return nil
        }
        text.removeLast()
        text += ",\"d\":\"\(Data(String(answer).utf8).base64EncodedString())\"}"
        guard let cookie = DGTikTokExtractor.challengeCookie(name: name, value: Data(text.utf8).base64EncodedString()) else {
            return nil
        }
        var cookies = [cookie]
        if let extraName = DGTikTokExtractor.elementAttribute(html, id: "rci", attribute: "class"), !extraName.isEmpty,
           let extraValue = DGTikTokExtractor.elementAttribute(html, id: "rs", attribute: "class"), !extraValue.isEmpty,
           let extra = DGTikTokExtractor.challengeCookie(name: extraName, value: extraValue) {
            cookies.append(extra)
        }
        return cookies
    }

    /// The number in 0...1,000,000 (yt-dlp's bound) whose decimal digits after `prefix` hash to `expected`.
    static func solveChallenge(prefix: Data, expected: Data) -> Int? {
        guard expected.count == SHA256.byteCount else {
            return nil
        }
        var base = SHA256()
        base.update(data: prefix)
        for number in 0 ... 1_000_000 {
            var hash = base
            var digits = String(number)
            digits.withUTF8 { hash.update(bufferPointer: UnsafeRawBufferPointer($0)) }
            if hash.finalize().elementsEqual(expected) {
                return number
            }
        }
        return nil
    }

    /// The page's script sets these for one reload; they are deleted right after it and expire soon anyway.
    private static func challengeCookie(name: String, value: String) -> HTTPCookie? {
        return HTTPCookie(properties: [
            .domain: ".tiktok.com",
            .path: "/",
            .name: name,
            .value: value,
            .expires: Date(timeIntervalSinceNow: 120.0)
        ])
    }

    /// `attribute` of the element whose id is `id`, as in `<p id="cs" class="...">`.
    private static func elementAttribute(_ html: String, id: String, attribute: String) -> String? {
        let tagPattern = "<[a-z][^>]*\\sid\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: id))[\"'][^>]*>"
        let valuePattern = "\\s\(NSRegularExpression.escapedPattern(for: attribute))\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let tagExpression = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]),
              let valueExpression = try? NSRegularExpression(pattern: valuePattern, options: [.caseInsensitive]),
              let tagMatch = tagExpression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let tagRange = Range(tagMatch.range, in: html) else {
            return nil
        }
        let tag = String(html[tagRange])
        guard let valueMatch = valueExpression.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else {
            return nil
        }
        for group in 1 ... 2 {
            if let range = Range(valueMatch.range(at: group), in: tag) {
                return String(tag[range])
            }
        }
        return nil
    }

    /// Base64 with or without its "=" padding (the challenge in the markup comes without it).
    private static func decodeBase64(_ value: String) -> Data? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(base64Encoded: trimmed + String(repeating: "=", count: (4 - trimmed.count % 4) % 4))
    }

    /// TikTok's own page first. When the page or one of its files fails, the original link goes to TikWM, once: a
    /// redirect to a login, challenge or home page does not prove that a share link expired. When TikWM fails too,
    /// the error names both answers. `download` fetches an item's files and calls its argument only on failure;
    /// `willUseFallback` runs before TikWM is asked.
    static func run(_ url: URL, fetcher: DGMediaFetcher, willUseFallback: @escaping () -> Void, download: @escaping (DGTikTokItem, @escaping (DGLinkDownloadError) -> Void) -> Void, failure: @escaping (DGLinkDownloadError) -> Void) {
        let fallback: (DGLinkDownloadError) -> Void = { directError in
            switch directError {
            case .cancelled, .tooLarge:
                // TikWM serves the same file, so it would be just as large.
                failure(directError)
            default:
                willUseFallback()
                DGTikTokExtractor.resolveFallback(url, fetcher: fetcher, completion: { result in
                    switch result {
                    case let .failure(error):
                        failure(DGTikTokExtractor.combine(directError, error))
                    case let .success(item):
                        download(item, { error in
                            failure(DGTikTokExtractor.combine(directError, error))
                        })
                    }
                })
            }
        }
        DGTikTokExtractor.resolveDirect(url, fetcher: fetcher, completion: { result in
            switch result {
            case let .failure(error):
                fallback(error)
            case let .success(item):
                download(item, { error in
                    if case let .httpStatus(code) = error {
                        fallback(.tiktokFileStatus(code))
                    } else {
                        fallback(error)
                    }
                })
            }
        })
    }

    private static func combine(_ directError: DGLinkDownloadError, _ fallbackError: DGLinkDownloadError) -> DGLinkDownloadError {
        switch fallbackError {
        case .cancelled, .tooLarge:
            return fallbackError
        default:
            return .tiktokFailed(directError, fallbackError)
        }
    }

    /// Short links (vm./vt./t/) are followed first: they redirect to "/@/video/<id>" or to the home page when expired.
    private static func resolveDirect(_ url: URL, fetcher: DGMediaFetcher, completion: @escaping (Result<DGTikTokItem, DGLinkDownloadError>) -> Void) {
        if let itemId = DGTikTokExtractor.itemId(from: url) {
            DGTikTokExtractor.fetchItem(itemId: itemId, fetcher: fetcher, completion: completion)
            return
        }
        fetcher.fetchData(DGTikTokExtractor.pageRequest(url), completion: { result in
            switch result {
            case let .failure(error):
                completion(.failure(DGTikTokExtractor.pageError(error)))
            case let .success(response):
                guard let finalURL = response.url, let itemId = DGTikTokExtractor.itemId(from: finalURL) else {
                    completion(.failure(.tiktokNoData))
                    return
                }
                DGTikTokExtractor.fetchItem(itemId: itemId, fetcher: fetcher, completion: completion)
            }
        })
    }

    static func resolveFallback(_ url: URL, fetcher: DGMediaFetcher, completion: @escaping (Result<DGTikTokItem, DGLinkDownloadError>) -> Void) {
        var components = URLComponents(string: "https://www.tikwm.com/api/")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "hd", value: "1")]
        guard let apiURL = components.url else {
            completion(.failure(.tiktokUnavailable))
            return
        }
        fetcher.fetchData(self.pageRequest(apiURL), completion: { result in
            switch result {
            case let .failure(.httpStatus(code)):
                completion(.failure(.tiktokDownloadServiceStatus(code)))
            case let .failure(error):
                completion(.failure(error))
            case let .success(response):
                completion(self.parseFallback(response.data))
            }
        })
    }

    static func parseFallback(_ data: Data) -> Result<DGTikTokItem, DGLinkDownloadError> {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              dgIntValue(root["code"]) == 0, let item = root["data"] as? [String: Any] else {
            return .failure(.tiktokUnavailable)
        }
        func file(_ value: Any?, size: Int64? = nil) -> DGRemoteFile? {
            guard let value = value as? String, !value.isEmpty,
                  let url = URL(string: value, relativeTo: URL(string: "https://www.tikwm.com/"))?.absoluteURL,
                  url.scheme == "https", url.host != nil else {
                return nil
            }
            return DGRemoteFile(url: url, expectedSize: size, width: 0, height: 0)
        }
        if let images = item["images"] as? [Any], !images.isEmpty {
            let files = images.compactMap { file($0) }
            guard files.count == images.count else {
                return .failure(.tiktokUnavailable)
            }
            return .success(.photos(files))
        }
        let duration = (item["duration"] as? NSNumber)?.doubleValue ?? 0
        let candidates = [file(item["hdplay"], size: dgIntValue(item["hd_size"])), file(item["play"], size: dgIntValue(item["size"]))].compactMap { $0 }
        if let video = candidates.first {
            return .success(.video(DGRemoteFile(url: video.url, expectedSize: video.expectedSize, width: video.width, height: video.height, alternateURLs: candidates.dropFirst().map { $0.url }), duration))
        }
        return .failure(.tiktokUnavailable)
    }

    private static func fetchItem(itemId: String, fetcher: DGMediaFetcher, completion: @escaping (Result<DGTikTokItem, DGLinkDownloadError>) -> Void) {
        guard let url = DGTikTokExtractor.pageURL(itemId: itemId) else {
            completion(.failure(.tiktokNoData))
            return
        }
        DGTikTokExtractor.fetchPage(url, fetcher: fetcher, completion: { result in
            guard case let .success(html) = result, DGTikTokExtractor.isBotCheck(html) else {
                completion(result.flatMap(DGTikTokExtractor.parsePage))
                return
            }
            guard let cookies = DGTikTokExtractor.challengeCookies(html) else {
                completion(.failure(.tiktokBotCheck))
                return
            }
            fetcher.setCookies(cookies)
            DGTikTokExtractor.fetchPage(url, fetcher: fetcher, completion: { result in
                fetcher.deleteCookies(cookies)
                if case let .success(html) = result, DGTikTokExtractor.isBotCheck(html) {
                    completion(.failure(.tiktokBotCheck))
                } else {
                    completion(result.flatMap(DGTikTokExtractor.parsePage))
                }
            })
        })
    }

    private static func fetchPage(_ url: URL, fetcher: DGMediaFetcher, completion: @escaping (Result<String, DGLinkDownloadError>) -> Void) {
        fetcher.fetchData(DGTikTokExtractor.pageRequest(url), completion: { result in
            completion(result.map { String(decoding: $0.data, as: UTF8.self) }.mapError(DGTikTokExtractor.pageError))
        })
    }

    /// An HTTP error on a page is TikTok refusing the page, not a file.
    private static func pageError(_ error: DGLinkDownloadError) -> DGLinkDownloadError {
        if case let .httpStatus(code) = error {
            return .tiktokPageStatus(code)
        }
        return error
    }
}
