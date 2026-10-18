func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

let base = CommandLine.arguments[1]
let payload = Data(repeating: 65, count: 8192)

func download(_ path: String, alternatives: [String], limit: Int64 = 200 * 1024 * 1024, cancel: Bool = false) -> Result<URL, DGLinkDownloadError> {
    let fetcher = DGMediaFetcher()
    let lock = NSLock()
    var result: Result<URL, DGLinkDownloadError>?
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    if cancel { fetcher.cancel() }
    fetcher.download(URLRequest(url: URL(string: base + path)!), alternatives: alternatives.map { URLRequest(url: URL(string: base + $0)!) }, to: destination, maxBytes: limit, progress: { _, _ in }, completion: {
        lock.lock()
        result = $0
        lock.unlock()
    })
    let deadline = Date().addingTimeInterval(10)
    var completed: Result<URL, DGLinkDownloadError>?
    while Date() < deadline {
        lock.lock()
        completed = result
        lock.unlock()
        if completed != nil { break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    fetcher.invalidate()
    guard let completed else { fatalError("download timed out") }
    return completed
}

if case let .success(file) = download("/denied", alternatives: ["/media"]) {
    check((try? Data(contentsOf: file)) == payload, "HTTP 403 must try alternate CDN")
    try? FileManager.default.removeItem(at: file)
} else { fatalError("alternate CDN failed") }
if case let .failure(error) = download("/denied", alternatives: ["/missing", "/gone"]) {
    check(error == .httpStatus(410), "bounded retries return the last HTTP failure")
} else { fatalError("HTTP failure expected") }
if case let .failure(error) = download("/limited", alternatives: ["/unexpected"], limit: 1024) {
    check(error == .tooLarge, "size limit must not retry another CDN")
} else { fatalError("size limit expected") }
if case let .failure(error) = download("/cancelled", alternatives: ["/unexpected"], cancel: true) {
    check(error == .cancelled, "cancelled download must not retry")
} else { fatalError("cancellation expected") }
func fetch(_ fetcher: DGMediaFetcher, _ path: String) {
    let done = DispatchSemaphore(value: 0)
    fetcher.fetchData(URLRequest(url: URL(string: base + path)!), completion: { result in
        if case .failure = result { fatalError("request \(path) failed") }
        done.signal()
    })
    check(done.wait(timeout: .now() + 10) == .success, "request \(path) timed out")
}

// TikTok's bot check answer: set before the reload, joined with the page's own cookies, gone after it.
let cookieFetcher = DGMediaFetcher()
fetch(cookieFetcher, "/set-cookie")
let answer = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "answer=YWJj=; Path=/"], for: URL(string: base)!)
check(answer.count == 1, "test cookie")
cookieFetcher.setCookies(answer)
fetch(cookieFetcher, "/echo-cookie")
cookieFetcher.deleteCookies(answer)
fetch(cookieFetcher, "/echo-cookie")
cookieFetcher.invalidate()
print("HTTP download fallback checks passed")
