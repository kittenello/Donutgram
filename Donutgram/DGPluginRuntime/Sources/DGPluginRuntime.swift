import Foundation
import DGPluginCHost

public struct DGPluginRuntimeError: Error, LocalizedError {
    public let code: String
    public var errorDescription: String? { return self.code }
    public init(_ code: String) { self.code = code }
}

private final class DGPluginRequestContext: @unchecked Sendable {
    let request: (String, @escaping (String) -> Void) -> Void
    var reply: ((Int64, String) -> Void)?

    init(request: @escaping (String, @escaping (String) -> Void) -> Void) {
        self.request = request
    }

    func receive(_ json: String) {
        guard let data = json.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = value["id"] as? NSNumber else { return }
        self.request(json) { [weak self] response in self?.reply?(id.int64Value, response) }
    }
}

private final class DGPluginEngineHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var pointer: OpaquePointer?

    init(_ pointer: OpaquePointer) { self.pointer = pointer }

    func read() -> OpaquePointer? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.pointer
    }

    func stop() {
        self.lock.lock()
        if let pointer = self.pointer { dgjs_stop(pointer) }
        self.lock.unlock()
    }

    func destroy() {
        self.lock.lock()
        let pointer = self.pointer
        self.pointer = nil
        if let pointer { dgjs_stop(pointer) }
        self.lock.unlock()
        if let pointer { dgjs_destroy(pointer) }
    }
}

public final class DGPluginRuntime {
    private let queue = DispatchQueue(label: "donutgram.plugin.runtime", qos: .utility)
    private let lock = NSLock()
    private let context: DGPluginRequestContext
    private var host: DGPluginEngineHandle?
    private var halted = false
    private var started = false
    private var processing = false
    private var completion: ((Result<Void, DGPluginRuntimeError>) -> Void)?
    private var pumpGeneration: UInt64 = 0
    private let entry: String
    private let environmentJSON: String

    public init(files: [String: Data], entry: String, environmentJSON: String, request: @escaping (String, @escaping (String) -> Void) -> Void) throws {
        guard files.count <= 128, files[entry] != nil, !entry.utf8.contains(0), environmentJSON.utf8.count <= 65536,
              !environmentJSON.utf8.contains(0), let environment = environmentJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: environment)) != nil else { throw DGPluginRuntimeError("invalid_package") }
        self.context = DGPluginRequestContext(request: request)
        self.entry = entry
        self.environmentJSON = environmentJSON
        let callbackContext = self.context
        var created: OpaquePointer?
        self.queue.sync {
            created = dgjs_create({ opaque, json in
                guard let opaque, let json else { return }
                Unmanaged<DGPluginRequestContext>.fromOpaque(opaque).takeUnretainedValue().receive(String(cString: json))
            }, Unmanaged.passUnretained(callbackContext).toOpaque())
        }
        guard let created else { throw DGPluginRuntimeError("runtime_unavailable") }
        self.host = DGPluginEngineHandle(created)
        var valid = true
        self.queue.sync {
            for (path, data) in files {
                if path.utf8.contains(0) { valid = false; break }
                let result = data.withUnsafeBytes { bytes in
                    dgjs_add_file(created, path, bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
                }
                if result != 0 { valid = false; break }
            }
        }
        if !valid {
            self.host = nil
            self.queue.sync { dgjs_destroy(created) }
            throw DGPluginRuntimeError("invalid_package")
        }
        self.context.reply = { [weak self] id, json in
            guard let self else { return }
            self.queue.async { [weak self] in
                guard let self, let host = self.availableHost(), json.utf8.count <= 65536, !json.utf8.contains(0) else { return }
                if dgjs_reply(host, id, json) < 0 { self.finish(.failure(self.failure(host))) }
                else { self.evaluate(dgjs_pump(host), host: host) }
            }
        }
    }

    deinit {
        self.lock.lock()
        let host = self.host
        self.host = nil
        host?.stop()
        self.lock.unlock()
        let context = self.context
        self.queue.async {
            host?.destroy()
            withExtendedLifetime(context) {}
        }
    }

    public func start(completion: @escaping (Result<Void, DGPluginRuntimeError>) -> Void) {
        self.queue.async {
            guard !self.started, self.completion == nil, let host = self.availableHost() else {
                completion(.failure(DGPluginRuntimeError("invalid_lifecycle"))); return
            }
            self.started = true
            self.processing = true
            self.completion = completion
            let status = dgjs_start(host, self.entry, DGPluginBootstrap.source, self.environmentJSON)
            self.evaluate(status, host: host)
        }
    }

    public func dispatch(kind: String, payloadJSON: String, completion: @escaping (Result<Void, DGPluginRuntimeError>) -> Void) {
        self.queue.async {
            guard self.started, self.completion == nil, let host = self.availableHost(), kind.utf8.count < 32,
                  !kind.utf8.contains(0), payloadJSON.utf8.count <= 65536, !payloadJSON.utf8.contains(0) else {
                completion(.failure(DGPluginRuntimeError("runtime_unavailable"))); return
            }
            guard !self.processing else { completion(.failure(DGPluginRuntimeError("runtime_busy"))); return }
            self.processing = true
            self.completion = completion
            self.evaluate(dgjs_dispatch(host, kind, payloadJSON), host: host)
        }
    }

    public func stop() {
        self.lock.lock()
        self.halted = true
        self.host?.stop()
        self.lock.unlock()
        self.queue.async { self.finish(.failure(DGPluginRuntimeError("cancelled"))) }
    }

    private func availableHost() -> OpaquePointer? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.halted ? nil : self.host?.read()
    }

    private func failure(_ host: OpaquePointer) -> DGPluginRuntimeError {
        return DGPluginRuntimeError(String(cString: dgjs_error(host)))
    }

    private func evaluate(_ status: Int32, host: OpaquePointer) {
        self.processing = status > 0
        if status <= 0 {
            self.finish(status == 0 ? .success(()) : .failure(self.failure(host)))
        } else {
            self.pumpGeneration &+= 1
            let generation = self.pumpGeneration
            self.queue.asyncAfter(deadline: .now() + .milliseconds(status == 2 ? 100 : 5)) { [weak self] in
                guard let self, self.pumpGeneration == generation, let host = self.availableHost() else { return }
                self.evaluate(dgjs_pump(host), host: host)
            }
        }
    }

    private func finish(_ result: Result<Void, DGPluginRuntimeError>) {
        self.processing = false
        self.pumpGeneration &+= 1
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }
}
