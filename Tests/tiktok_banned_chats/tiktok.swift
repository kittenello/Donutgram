struct DGHTTPResponse {
    let data: Data
    let url: URL?
}

final class DGMediaFetcher {
    var responses: [Result<DGHTTPResponse, DGLinkDownloadError>] = []
    var requests: [URLRequest] = []
    func fetchData(_ request: URLRequest, completion: @escaping (Result<DGHTTPResponse, DGLinkDownloadError>) -> Void) {
        requests.append(request)
        precondition(!responses.isEmpty, "unexpected extra request")
        completion(responses.removeFirst())
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

func response(_ object: [String: Any], url: URL? = nil) -> Result<DGHTTPResponse, DGLinkDownloadError> {
    return .success(DGHTTPResponse(data: try! JSONSerialization.data(withJSONObject: object), url: url))
}

let post = URL(string: "https://www.tiktok.com/@scout2015/video/6718335390845095173")!
let short = URL(string: "https://vm.tiktok.com/ABC123/?test=a&another=b")!
let video: [String: Any] = ["code": 0, "data": ["hdplay": "https://cdn.example/video.mp4", "hd_size": "12345", "play": "https://cdn.example/sd.mp4", "duration": 15]]
let fetcher = DGMediaFetcher()
let page = #"{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"statusCode":0,"itemInfo":{"itemStruct":{"video":{"playAddr":"https://cdn.example/direct.mp4","duration":5}}}}}}"#
let html = "<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\">" + page + "</script>"
fetcher.responses = [.success(DGHTTPResponse(data: Data(html.utf8), url: post))]
var direct: Result<DGTikTokItem, DGLinkDownloadError>?
DGTikTokExtractor.resolve(post, fetcher: fetcher) { direct = $0 }
if case let .success(.video(file, _)) = direct {
    check(file.url.absoluteString == "https://cdn.example/direct.mp4", "keep working direct extraction")
} else { fatalError("direct page") }
check(fetcher.requests.count == 1, "working direct pages never contact provider")
fetcher.requests.removeAll()
fetcher.responses = [.success(DGHTTPResponse(data: Data("challenge".utf8), url: URL(string: "https://www.tiktok.com/"))), response(video)]
var result: Result<DGTikTokItem, DGLinkDownloadError>?
DGTikTokExtractor.resolve(short, fetcher: fetcher) { result = $0 }
if case let .success(.video(file, duration)) = result {
    check(file.url.absoluteString == "https://cdn.example/video.mp4", "prefer HD")
    check(file.expectedSize == 12345 && duration == 15, "provider metadata")
} else { fatalError("a challenge redirect must use the provider") }
check(fetcher.requests.count == 2, "one fallback request")
let query = URLComponents(url: fetcher.requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
check(query.first { $0.name == "url" }?.value == short.absoluteString, "pass original short link without corrupting its query")

fetcher.responses = [.failure(.httpStatus(403)), response(video)]
DGTikTokExtractor.resolve(post, fetcher: fetcher) { result = $0 }
if case .success(.video) = result {} else { fatalError("page HTTP 403 must use fallback") }
let count = fetcher.requests.count
fetcher.responses = [.failure(.cancelled)]
DGTikTokExtractor.resolve(post, fetcher: fetcher) { result = $0 }
check(result == .failure(.cancelled), "cancellation propagates")
check(fetcher.requests.count == count + 1, "cancellation never contacts fallback")

let photos: [String: Any] = ["code": 0, "data": ["images": ["//cdn.example/1.jpg", "https://cdn.example/2.jpg"], "play": "https://cdn.example/cover.mp4"]]
let photosData = try! JSONSerialization.data(withJSONObject: photos)
if case let .success(.photos(files)) = DGTikTokExtractor.parseFallback(photosData) {
    check(files.count == 2 && files[0].url.absoluteString == "https://cdn.example/1.jpg", "preserve carousel order")
} else { fatalError("carousel must stay photos") }
for bad: [String: Any] in [["code": -1, "msg": "busy"], ["code": 0, "data": [:]], ["code": 0, "data": ["images": ["https://cdn.example/1.jpg", "file:///tmp/bad"]]]] {
    check(DGTikTokExtractor.parseFallback(try! JSONSerialization.data(withJSONObject: bad)) == .failure(.tiktokUnavailable), "no false expired-link error or partial carousel")
}
let sd = try! JSONSerialization.data(withJSONObject: ["code": 0, "data": ["play": "/video/media/play/test.mp4"]])
if case let .success(.video(file, _)) = DGTikTokExtractor.parseFallback(sd) {
    check(file.url.absoluteString == "https://www.tikwm.com/video/media/play/test.mp4", "relative provider URL")
} else { fatalError("SD fallback") }
check(DGLinkDownloadLink.parse(short.absoluteString) != nil, "short link accepted")
check(DGLinkDownloadLink.parse("https://www.youtube.com/shorts/abcdefghijk") != nil, "Shorts still accepted")
print("TikTok fallback checks passed")
