import Foundation
import DGPluginModel

#if canImport(Network)
import Network
import Security
import Darwin
#endif

public enum DGPluginPublicNetwork {
    public static var isAvailable: Bool {
        #if canImport(Network)
        return true
        #else
        return false
        #endif
    }

    public static func request(params: DGPluginJSON, allowedOrigins: [String], validity: @escaping () -> Bool, completion: @escaping (Result<DGPluginJSON, DGPluginError>) -> Void) -> () -> Void {
        #if canImport(Network)
        let operation = DGPluginNetworkOperation(params: params, allowedOrigins: allowedOrigins, validity: validity, completion: completion)
        operation.start()
        return { operation.cancel() }
        #else
        completion(.failure(DGPluginError(code: "feature_unavailable", message: "public networking requires the Apple native transport")))
        return {}
        #endif
    }
}

#if canImport(Network)
private final class DGPluginNetworkOperation {
    private let queue = DispatchQueue(label: "donutgram.plugins.public-network")
    private let lock = NSLock()
    private var cancelled = false
    private var finished = false
    private let params: DGPluginJSON
    private let origins: [String]
    private let validity: () -> Bool
    private let completion: (Result<DGPluginJSON, DGPluginError>) -> Void
    private var connection: NWConnection?
    private var response = Data()
    private var timer: DispatchSourceTimer?
    private var request: DGPluginPublicRequest?
    private var keepAlive: DGPluginNetworkOperation?

    init(params: DGPluginJSON, allowedOrigins: [String], validity: @escaping () -> Bool, completion: @escaping (Result<DGPluginJSON, DGPluginError>) -> Void) {
        self.params = params; self.origins = allowedOrigins; self.validity = validity; self.completion = completion
    }

    func start() {
        queue.async {
            self.keepAlive = self
            do {
                guard self.current() else { throw DGPluginError(code: "cancelled", message: "public request was cancelled") }
                self.request = try DGPluginPublicRequest.validated(self.params, allowedOrigins: self.origins)
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(10))
                let deadline = ProcessInfo.processInfo.systemUptime + 10
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    if !self.current() { self.finish(.failure(DGPluginError(code: "cancelled", message: "public request was cancelled"))) }
                    else if ProcessInfo.processInfo.systemUptime >= deadline { self.finish(.failure(DGPluginError(code: "timeout", message: "public request exceeded its deadline"))) }
                }
                self.timer = timer
                timer.resume()
                guard let request = self.request else { return }
                DispatchQueue.global(qos: .utility).async {
                    let result = Self.resolve(request.host)
                    self.queue.async {
                        guard self.current() else { self.finish(.failure(DGPluginError(code: "cancelled", message: "public request was cancelled"))); return }
                        switch result {
                        case let .success(address): self.connect(address: address, request: request)
                        case let .failure(error): self.finish(.failure(error))
                        }
                    }
                }
            } catch let error as DGPluginError { self.finish(.failure(error)) }
            catch { self.finish(.failure(DGPluginError(code: "invalid_argument", message: "invalid public request"))) }
        }
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        queue.async { self.finish(.failure(DGPluginError(code: "cancelled", message: "public request was cancelled"))) }
    }

    private func current() -> Bool {
        lock.lock(); let cancelled = self.cancelled; lock.unlock()
        return !cancelled && !finished && validity()
    }

    private static func resolve(_ hostname: String) -> Result<String, DGPluginError> {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var entries: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, "443", &hints, &entries) == 0, let first = entries else { return .failure(DGPluginError(code: "network_error", message: "public hostname resolution failed")) }
        defer { freeaddrinfo(first) }
        var result: [String] = []
        var entry: UnsafeMutablePointer<addrinfo>? = first
        var count = 0
        while let item = entry {
            count += 1
            guard count <= 32, [AF_INET, AF_INET6].contains(item.pointee.ai_family), let address = item.pointee.ai_addr else { return .failure(DGPluginError(code: "scope_denied", message: "public hostname has unsupported addresses")) }
            if item.pointee.ai_family == AF_INET6 {
                let scoped = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in6.self)
                guard scoped.pointee.sin6_scope_id == 0 else { return .failure(DGPluginError(code: "scope_denied", message: "scoped addresses are not public destinations")) }
            }
            var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, item.pointee.ai_addrlen, &text, socklen_t(text.count), nil, 0, NI_NUMERICHOST) == 0 else { return .failure(DGPluginError(code: "network_error", message: "unable to validate resolved address")) }
            let numeric = String(cString: text)
            guard DGPluginPublicAddress.isAllowed(numeric) else { return .failure(DGPluginError(code: "scope_denied", message: "public hostname resolved to a restricted address")) }
            if !result.contains(numeric) { result.append(numeric) }
            entry = item.pointee.ai_next
        }
        guard let selected = result.first else { return .failure(DGPluginError(code: "network_error", message: "public hostname has no permitted address")) }
        return .success(selected)
    }

    private func connect(address: String, request: DGPluginPublicRequest) {
        guard current() else { finish(.failure(DGPluginError(code: "cancelled", message: "public request was cancelled"))); return }
        let endpoint: NWEndpoint.Host
        if let ipv4 = IPv4Address(address) { endpoint = .ipv4(ipv4) }
        else if let ipv6 = IPv6Address(address) { endpoint = .ipv6(ipv6) }
        else { finish(.failure(DGPluginError(code: "scope_denied", message: "resolved endpoint is not a numeric address"))); return }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, request.host)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { [weak self] _, peerTrust, complete in
            guard let self, self.current() else { complete(false); return }
            let trust = sec_trust_copy_ref(peerTrust).takeRetainedValue()
            let policy = SecPolicyCreateSSL(true, request.host as CFString)
            guard SecTrustSetPolicies(trust, policy) == errSecSuccess, SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else { complete(false); return }
            let trusted = SecTrustEvaluateWithError(trust, nil)
            complete(trusted && self.current())
        }, queue)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = false
        let connection = NWConnection(host: endpoint, port: 443, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            guard self.current() else { self.finish(.failure(DGPluginError(code: "cancelled", message: "public request was cancelled"))); return }
            switch state {
            case .ready: self.send(request)
            case .failed: self.finish(.failure(DGPluginError(code: "network_error", message: "public TLS connection failed")))
            case .cancelled: self.finish(.failure(DGPluginError(code: "cancelled", message: "public connection cancelled")))
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func send(_ request: DGPluginPublicRequest) {
        guard current(), let connection else { finish(.failure(DGPluginError(code: "cancelled", message: "public request was cancelled"))); return }
        connection.send(content: request.wireBytes, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            guard error == nil, self.current() else { self.finish(.failure(DGPluginError(code: "network_error", message: "public request could not be sent"))); return }
            self.receive(request)
        })
    }

    private func receive(_ request: DGPluginPublicRequest) {
        guard current(), let connection else { finish(.failure(DGPluginError(code: "cancelled", message: "public request was cancelled"))); return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self else { return }
            guard self.current() else { self.finish(.failure(DGPluginError(code: "cancelled", message: "public request was cancelled"))); return }
            do {
                guard error == nil else { throw DGPluginError(code: "network_error", message: "public response connection failed") }
                if let data {
                    guard data.count <= 96 * 1024 - self.response.count else { throw DGPluginError(code: "quota_exceeded", message: "public response exceeds wire quota") }
                    self.response.append(data)
                }
                if let parsed = try DGPluginHTTPResponse.parse(self.response, method: request.method, endOfStream: complete) {
                    let result = try parsed.json(url: request.url)
                    guard self.current() else { throw DGPluginError(code: "cancelled", message: "public request was cancelled") }
                    self.finish(.success(result))
                } else { self.receive(request) }
            } catch let error as DGPluginError { self.finish(.failure(error)) }
            catch { self.finish(.failure(DGPluginError(code: "invalid_response", message: "invalid public response"))) }
        }
    }

    private func finish(_ result: Result<DGPluginJSON, DGPluginError>) {
        guard !finished else { return }
        finished = true
        timer?.setEventHandler {}; timer?.cancel(); timer = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        response.removeAll(keepingCapacity: false)
        completion(result)
        keepAlive = nil
    }
}
#endif
