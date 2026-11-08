import Foundation
import DGPluginModel
import DGPluginInstaller
import DGPluginRuntime
import DGPluginNetwork

private struct DGPluginAccountRecord: Codable {
    var enabled = false
    var grants: [DGPluginPermission] = []
    var settings: [String: DGPluginJSON] = [:]
    var storage: [String: DGPluginJSON] = [:]
    var failures = 0
    var lastError: String?
    var diagnostics: [String]?
}

private struct DGPluginStoredRecord: Codable {
    let id: String
    var manifest: DGPluginManifest
    var digest: String
    var publisherIdentity: String
    var trust: String
    var fileName: String
    var removing = false
    var accounts: [String: DGPluginAccountRecord] = [:]
    var previous: DGPluginPreviousVersion?
}

private struct DGPluginPreviousVersion: Codable {
    let manifest: DGPluginManifest
    let digest: String
    let publisherIdentity: String
    let trust: String
    let fileName: String
    let accounts: [String: DGPluginAccountRecord]
}

private struct DGPluginDeviceState: Codable {
    var schemaVersion = 1
    var globallyEnabled = true
    var installations: [DGPluginStoredRecord] = []
    var revokedPublishers: [String]?
}

private final class DGPluginExecution {
    let generation = UUID()
    var runtime: DGPluginRuntime?
    var state: DGPluginState = .starting
    var requests = 0
    var windowStart = ProcessInfo.processInfo.systemUptime
    var gestureUntil = 0.0
    var commandEpoch = UUID()
    var commands: [DGPluginCommandDescriptor] = []
    var contributions: [String: DGPluginJSON] = [:]
    var subscriptions = Set<String>()
    var cleanup: [() -> Void] = []
    var busy = false
    var assets: [String: Data] = [:]
    var pageTokens: [String: UUID] = [:]
    var pageCleanup: [String: () -> Void] = [:]
    var pagesPending = Set<String>()
    var networkRequests: [UUID: () -> Void] = [:]
    var networkCount = 0
    var nativeCleanup: [UUID: () -> Void] = [:]
    var transforms: [String: DGPluginRegisteredTransform] = [:]
    var pendingTransforms: [String: DGPluginPendingTransform] = [:]
    var transformFailures = 0
    var events: [(String, DGPluginJSON)] = []
    var eventFailures = 0
    var themeTokens: DGPluginJSON = .object([:])
    /// Uptimes of the last minute's direct message actions (send, edit, delete), for their rate limit.
    var messageActionTimes: [TimeInterval] = []
    var noticeTimes: [TimeInterval] = []
    /// Running estimate of the account storage's encoded size, computed on first use.
    var storageBytes: Int?
}

private struct DGPluginRegisteredTransform {
    let id: String
    let slot: String
    let priority: Int
}

private final class DGPluginOutgoingOperation {
    var finished = false
    var activeInstallation: String?
}

private final class DGPluginPendingTransform {
    let registrationId: String
    let slot: String
    let input: DGPluginJSON
    var result: DGPluginJSON?
    init(registrationId: String, slot: String, input: DGPluginJSON) { self.registrationId = registrationId; self.slot = slot; self.input = input }
}

/// One plugin runtime that is executing for one account. The set of them is kept on disk while they run, so
/// a launch after a crash can tell which plugins were running and turn them off instead of starting them
/// again (a plugin that crashes the app in `activate` would otherwise crash every launch).
private struct DGPluginRunningMarker: Codable, Hashable {
    let account: String
    let installation: String
}

private final class DGPluginCoordinator {
    static let shared = DGPluginCoordinator()
    static let interruptedMessage = "the app closed unexpectedly while this plugin was running, so it was turned off"
    let queue = DispatchQueue(label: "donutgram.plugins.host")
    let root: URL
    var state = DGPluginDeviceState()
    var packages: [String: DGVerifiedPluginPackage] = [:]
    var runningMarkers = Set<DGPluginRunningMarker>()
    var activeAccountKey: String?
    var foreground = true
    var powerSaving = false
    var startupError: DGPluginError?
    var persistenceError: String?
    /// Set when a deferred save of plugin-written data failed; cleared by the next successful save.
    var deferredSaveError: String?
    private var savePending = false
    #if DG_PLUGIN_TESTS
    var testIOFailure: String?
    #endif

    private init() {
        #if DG_PLUGIN_TESTS
        guard let testRoot = ProcessInfo.processInfo.environment["DG_PLUGIN_TEST_ROOT"], !testRoot.isEmpty else { preconditionFailure("isolated plugin test root is required") }
        self.root = URL(fileURLWithPath: testRoot, isDirectory: true).standardizedFileURL
        #else
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        self.root = support.appendingPathComponent("DonutgramPlugins", isDirectory: true)
        #endif
        // The first use comes from the main thread at launch; reading and recovering the state (up to 32 MiB)
        // runs on the queue instead, and every later operation is queued behind it.
        queue.async { self.load() }
    }

    private func load() {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var excludedRoot = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excludedRoot.setResourceValues(values)
            let path = root.appendingPathComponent("state.json")
            if FileManager.default.fileExists(atPath: path.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
                guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 32 * 1024 * 1024 else {
                    throw DGPluginError(code: "quota_exceeded", message: "plugin state exceeds its limit")
                }
                state = try JSONDecoder().decode(DGPluginDeviceState.self, from: Data(contentsOf: path))
                guard state.schemaVersion == 1, state.installations.count <= 32 else {
                    throw DGPluginError(code: "incompatible", message: "unsupported plugin state")
                }
                guard Set(state.installations.map { $0.id }).count == state.installations.count else {
                    throw DGPluginError(code: "invalid_argument", message: "duplicate installation records")
                }
                for record in state.installations {
                    guard UUID(uuidString: record.id) != nil, record.digest.count == 64, record.digest.allSatisfy({ $0.isHexDigit }) else {
                        throw DGPluginError(code: "invalid_argument", message: "invalid installation identity")
                    }
                }
                var changed = false
                for record in state.installations where record.removing {
                    try cleanupFiles(record)
                    changed = true
                }
                state.installations.removeAll(where: { $0.removing })
                if recoverInterruptedRuns() { changed = true }
                if changed { try persist() }
            }
        } catch {
            startupError = DGPluginError(code: "storage_error", message: "plugin state requires recovery; execution is stopped")
            state.globallyEnabled = false
        }
    }

    /// Storage and settings that plugin code writes are saved together half a second later instead of once per
    /// call: every save writes the whole state file. Management operations keep saving at once, and leaving the
    /// foreground saves what is pending.
    func scheduleSave() {
        guard !savePending else { return }
        savePending = true
        queue.asyncAfter(deadline: .now() + 0.5) { self.saveIfPending() }
    }

    func saveIfPending() {
        guard savePending else { return }
        do {
            try persist()
        } catch {
            deferredSaveError = "unable to save plugin data; its latest changes may be lost after a restart"
            publishAll()
        }
    }

    func persist() throws {
        guard startupError == nil else { throw startupError! }
        try testFailure("persist")
        // This write contains everything a deferred save was waiting for.
        savePending = false
        let data = try JSONEncoder().encode(state)
        guard data.count <= 32 * 1024 * 1024 else { throw DGPluginError(code: "quota_exceeded", message: "plugin state exceeds its limit") }
        try data.write(to: root.appendingPathComponent("state.json"), options: .atomic)
        deferredSaveError = nil
    }

    var runningMarkersURL: URL { return root.appendingPathComponent("running.json") }

    /// Turns off every plugin that was executing when the previous process ended without stopping it.
    /// Returns whether a record changed.
    func recoverInterruptedRuns() -> Bool {
        let url = runningMarkersURL
        guard let data = try? Data(contentsOf: url) else { return false }
        try? FileManager.default.removeItem(at: url)
        guard data.count <= 65536, let markers = try? JSONDecoder().decode([DGPluginRunningMarker].self, from: data) else { return false }
        let entry = ISO8601DateFormatter().string(from: Date()) + " " + Self.interruptedMessage
        var changed = false
        for marker in markers {
            guard let index = state.installations.firstIndex(where: { $0.id == marker.installation }),
                  var account = state.installations[index].accounts[marker.account], account.enabled else { continue }
            account.enabled = false
            account.failures += 1
            account.lastError = Self.interruptedMessage
            account.diagnostics = Array(((account.diagnostics ?? []) + [entry]).suffix(20))
            state.installations[index].accounts[marker.account] = account
            changed = true
        }
        return changed
    }

    func markRunning(_ marker: DGPluginRunningMarker) {
        guard runningMarkers.insert(marker).inserted else { return }
        writeRunningMarkers()
    }

    func clearRunning(_ marker: DGPluginRunningMarker) {
        guard runningMarkers.remove(marker) != nil else { return }
        writeRunningMarkers()
    }

    private func writeRunningMarkers() {
        let url = runningMarkersURL
        guard !runningMarkers.isEmpty else { try? FileManager.default.removeItem(at: url); return }
        let markers = runningMarkers.sorted { ($0.account, $0.installation) < ($1.account, $1.installation) }
        if let data = try? JSONEncoder().encode(markers) { try? data.write(to: url, options: .atomic) }
    }

    func packageURL(_ record: DGPluginStoredRecord) -> URL {
        return root.appendingPathComponent(record.id, isDirectory: true).appendingPathComponent(record.digest + ".package")
    }

    func package(_ record: DGPluginStoredRecord) throws -> DGVerifiedPluginPackage {
        if let package = packages[record.digest] { return package }
        let url = packageURL(record)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 8 * 1024 * 1024 else {
            throw DGPluginError(code: "quota_exceeded", message: "stored package exceeds its limit")
        }
        let result = try DGPluginInstaller.preview(data: Data(contentsOf: url), fileName: record.fileName)
        guard result.digest == record.digest, result.manifest == record.manifest, result.publisherIdentity == record.publisherIdentity else {
            throw DGPluginError(code: "integrity_error", message: "installed package changed after verification")
        }
        packages[record.digest] = result
        return result
    }

    func cleanupFiles(_ record: DGPluginStoredRecord) throws {
        try testFailure("cleanup")
        let directory = root.appendingPathComponent(record.id, isDirectory: true).standardizedFileURL
        guard UUID(uuidString: record.id) != nil, directory.deletingLastPathComponent() == root.standardizedFileURL else {
            throw DGPluginError(code: "invalid_argument", message: "invalid package removal path")
        }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        packages.removeValue(forKey: record.digest)
        if let previous = record.previous { packages.removeValue(forKey: previous.digest) }
    }

    func pruneVersions(_ record: DGPluginStoredRecord) throws {
        let directory = packageURL(record).deletingLastPathComponent()
        let retained = Set([record.digest, record.previous?.digest].compactMap { $0 }.map { $0 + ".package" })
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            let name = url.lastPathComponent
            guard name.hasSuffix(".package"), name.count == 72, name.dropLast(8).allSatisfy({ $0.isHexDigit }), !retained.contains(name), url.deletingLastPathComponent() == directory else { continue }
            try FileManager.default.removeItem(at: url)
        }
    }

    func publishAll() {
        for manager in DGPluginManager.allManagers() { manager.publish() }
    }

    func testFailure(_ operation: String) throws {
        #if DG_PLUGIN_TESTS
        if testIOFailure == operation {
            testIOFailure = nil
            throw DGPluginError(code: "storage_error", message: "injected plugin storage failure")
        }
        #endif
    }

    func stopAll(id: String? = nil) {
        for manager in DGPluginManager.allManagers() {
            if let id = id { manager.stop(id: id) } else { manager.stopAll() }
        }
    }
}

/// Whether any running plugin transforms a local view model, and the revision of the cached results.
/// Screens compare it to decide when they need to rebuild; it changes only when a transform appears,
/// disappears or its cached results are invalidated.
public struct DGPluginViewTransformState: Equatable {
    public let active: Bool
    public let revision: UInt64

    public init(active: Bool, revision: UInt64) {
        self.active = active
        self.revision = revision
    }

    /// True when a screen showing `previous` has to rebuild to show `self`.
    public func requiresUpdate(from previous: DGPluginViewTransformState?) -> Bool {
        guard let previous else { return self.active }
        return self.active != previous.active || (self.active && self.revision != previous.revision)
    }
}

public final class DGPluginManager {
    private static let registryLock = NSLock()
    private static var registry: [String: DGPluginManager] = [:]
    private let coordinator = DGPluginCoordinator.shared
    private let accountKey: String
    private let snapshotLock = NSLock()
    private var snapshotInstallations: [DGPluginInstallation] = []
    private var snapshotCommands: [DGPluginCommandDescriptor] = []
    private var snapshotIcons: [String: Data] = [:]
    private var snapshotEnabled = true
    private var snapshotRollbackIds = Set<String>()
    private var snapshotPersistenceError: String?
    private var snapshotTransformSlots = Set<String>()
    private var snapshotViewRevision: UInt64 = 0
    private var snapshotIntercepts = false
    private var snapshotPublishers: [String: String] = [:]
    private var snapshotDiagnostics: [String: [String]] = [:]
    private var viewModelCache: [String: DGPluginJSON] = [:]
    private var viewModelRevision: UInt64 = 0
    private var pendingViewModels = Set<String>()
    private var deferredViewUpdates: [String: () -> Void] = [:]
    private var observers: [UUID: () -> Void] = [:]
    private var executions: [String: DGPluginExecution] = [:]
    private var adapter: ((String, String, DGPluginJSON, @escaping () -> Bool, @escaping (Result<DGPluginJSON, DGPluginError>) -> Void) -> Void)?
    private var renderAdapter: ((String, DGPluginJSON, String, @escaping () -> Bool, @escaping (String) -> Data?, @escaping (String, DGPluginJSON) -> Void, @escaping () -> Void) -> Result<() -> Void, DGPluginError>)?
    private var environment: [String: DGPluginJSON] = ["clientVersion": .string(DGPluginClientVersion.current), "locale": .string("en"), "appearance": .string("light"), "lowPowerMode": .bool(false)]

    public var nativeRequest: ((String, String, DGPluginJSON, @escaping () -> Bool, @escaping (Result<DGPluginJSON, DGPluginError>) -> Void) -> Void)? {
        get { snapshotLock.lock(); defer { snapshotLock.unlock() }; return adapter }
        set { snapshotLock.lock(); adapter = newValue; snapshotLock.unlock() }
    }

    public var nativeRender: ((String, DGPluginJSON, String, @escaping () -> Bool, @escaping (String) -> Data?, @escaping (String, DGPluginJSON) -> Void, @escaping () -> Void) -> Result<() -> Void, DGPluginError>)? {
        get { snapshotLock.lock(); defer { snapshotLock.unlock() }; return renderAdapter }
        set { snapshotLock.lock(); renderAdapter = newValue; snapshotLock.unlock() }
    }

    public static var executionAvailable: Bool {
        #if DG_PLUGINS_SIDELOAD
        return true
        #else
        return false
        #endif
    }

    #if DG_PLUGIN_TESTS
    public static func setTestIOFailure(_ operation: String?, completion: @escaping () -> Void) {
        let coordinator = DGPluginCoordinator.shared
        coordinator.queue.async { coordinator.testIOFailure = operation; DispatchQueue.main.async(execute: completion) }
    }
    #endif

    public static func shared(accountKey: String) -> DGPluginManager {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let manager = registry[accountKey] { return manager }
        let manager = DGPluginManager(accountKey: accountKey)
        registry[accountKey] = manager
        manager.coordinator.queue.async { manager.publish() }
        return manager
    }

    fileprivate static func allManagers() -> [DGPluginManager] {
        registryLock.lock(); defer { registryLock.unlock() }
        return Array(registry.values)
    }

    private init(accountKey: String) {
        self.accountKey = accountKey
    }

    public static func activateAccount(key: String?) {
        let coordinator = DGPluginCoordinator.shared
        coordinator.queue.async {
            guard coordinator.activeAccountKey != key else { return }
            coordinator.stopAll()
            coordinator.activeAccountKey = key
            for manager in allManagers() where manager.accountKey == key { manager.reconcile() }
            coordinator.publishAll()
        }
    }

    public func setAccountActive(_ active: Bool) {
        if active { Self.activateAccount(key: accountKey) }
        else { coordinator.queue.async { if self.coordinator.activeAccountKey == self.accountKey { self.coordinator.stopAll(); self.coordinator.activeAccountKey = nil; self.coordinator.publishAll() } } }
    }

    public func setForegroundActive(_ active: Bool) {
        coordinator.queue.async {
            guard self.coordinator.foreground != active else { return }
            self.coordinator.foreground = active
            if !active { self.coordinator.stopAll(); self.coordinator.saveIfPending() } else { for manager in Self.allManagers() { manager.reconcile() } }
            self.coordinator.publishAll()
        }
    }

    public func setPowerSaving(_ enabled: Bool) {
        coordinator.queue.async {
            guard self.coordinator.powerSaving != enabled else { return }
            self.coordinator.powerSaving = enabled
            self.environment["lowPowerMode"] = .bool(enabled)
            self.coordinator.stopAll()
            if !enabled { for manager in Self.allManagers() { manager.reconcile() } }
            self.coordinator.publishAll()
        }
    }

    public func updateEnvironment(locale: String, appearance: String) {
        coordinator.queue.async {
            let previousLocale = self.environment["locale"]
            let previousAppearance = self.environment["appearance"]
            self.environment["locale"] = .string(String(locale.prefix(64)))
            self.environment["appearance"] = .string(appearance == "dark" ? "dark" : "light")
            if previousLocale != self.environment["locale"] { self.emitNativeEvent(name: "locale.changed", payload: .object(["locale": self.environment["locale"] ?? .string("en")])) }
            if previousAppearance != self.environment["appearance"] { self.emitNativeEvent(name: "theme.changed", payload: .object(["appearance": self.environment["appearance"] ?? .string("light")])) }
        }
    }

    public func emitNativeEvent(name: String, payload: DGPluginJSON, installationId: String? = nil) {
        let rules: [String: (String?, String?)] = [
            "plugin.activated": (nil, nil), "app.foreground": (nil, nil),
            "account.contextChanged": (nil, nil), "theme.changed": ("theme.read", "currentTheme"), "locale.changed": (nil, nil),
            "chat.opened": ("chats.metadata.read", "selectedChats"), "chat.closed": ("chats.metadata.read", "selectedChats"),
            "message.observed": ("messages.read", "selectedChats"),
            "composer.changed": ("composer.read", "activeComposer")
        ]
        guard let rule = rules[name], (try? payload.validateLimits(maximumDepth: 8, maximumNodes: 1024)) != nil, let encoded = try? JSONEncoder().encode(payload), encoded.count <= 16384 else { return }
        coordinator.queue.async {
            for (id, execution) in self.executions where installationId == nil || id == installationId {
                guard execution.state == .running, self.current(id, execution.generation), execution.subscriptions.contains(name), let record = self.coordinator.state.installations.first(where: { $0.id == id }) else { continue }
                if let capability = rule.0, !self.account(record).grants.contains(where: { $0.capability == capability && (rule.1 == nil || $0.scope == rule.1!) }) { continue }
                let event = DGPluginJSON.object(["id": .string(UUID().uuidString.lowercased()), "timestamp": .number(Date().timeIntervalSince1970), "version": .number(1), "data": payload])
                execution.events.removeAll { $0.0 == name }
                if execution.events.count < 16 { execution.events.append((name, event)) }
                self.drainEvents(id: id)
            }
        }
    }

    private func drainEvents(id: String) {
        guard let execution = executions[id], execution.state == .running, !execution.busy, !execution.events.isEmpty, current(id, execution.generation) else { return }
        let (name, event) = execution.events.removeFirst()
        guard execution.subscriptions.contains(name) else { drainEvents(id: id); return }
        execution.busy = true
        execution.gestureUntil = 0
        let payload = DGPluginJSON.object(["name": .string(name), "payload": event])
        guard let bytes = try? JSONEncoder().encode(payload), let json = String(data: bytes, encoding: .utf8) else { execution.busy = false; return }
        execution.runtime?.dispatch(kind: "event", payloadJSON: json) { outcome in
            self.coordinator.queue.async {
                guard self.current(id, execution.generation) else { return }
                execution.busy = false
                switch outcome {
                case .success: execution.eventFailures = 0
                case let .failure(error):
                    if error.code == "runtime_busy" { execution.events.insert((name, event), at: 0); return }
                    if error.code == "plugin_rejected" {
                        // The handler's own error: the runtime keeps running, unless it keeps failing.
                        execution.eventFailures += 1
                        if execution.eventFailures >= 5 { self.fail(id: id, message: "plugin event handlers failed five times in a row"); return }
                    } else {
                        self.fail(id: id, message: "plugin event handler exceeded its budget or stopped")
                        return
                    }
                }
                self.refreshDeferredViewModels(); self.drainEvents(id: id)
            }
        }
    }

    public var installations: [DGPluginInstallation] { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotInstallations }
    public var commands: [DGPluginCommandDescriptor] { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotCommands }
    public var globallyEnabled: Bool { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotEnabled }
    public func iconData(id: String) -> Data? { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotIcons[id] }
    public func canRollback(id: String) -> Bool { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotRollbackIds.contains(id) }
    public var persistenceError: String? { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotPersistenceError }

    /// Read from any thread without waiting for the plugin queue.
    public func viewTransformState(slot: String) -> DGPluginViewTransformState {
        snapshotLock.lock(); defer { snapshotLock.unlock() }
        return DGPluginViewTransformState(active: snapshotTransformSlots.contains(slot), revision: snapshotViewRevision)
    }

    // Snapshot reads for the main thread: waiting for the plugin queue could block on a state write or a
    // package verification.
    public func publisherIdentity(id: String) -> String? { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotPublishers[id] }

    public func diagnostics(id: String) -> [String] { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotDiagnostics[id] ?? [] }

    public func nativeScope(installationId: String) -> String? {
        return coordinator.queue.sync {
            guard let execution = self.executions[installationId], self.current(installationId, execution.generation) else { return nil }
            return execution.generation.uuidString
        }
    }

    public func ownNativeResource(installationId: String, scope: String, cleanup: @escaping () -> Void) -> UUID? {
        return coordinator.queue.sync {
            guard let execution = self.executions[installationId], execution.generation.uuidString == scope, self.current(installationId, execution.generation), execution.nativeCleanup.count < 16 else { return nil }
            let id = UUID(); execution.nativeCleanup[id] = cleanup; return id
        }
    }

    public func releaseNativeResource(installationId: String, token: UUID) {
        coordinator.queue.async { self.executions[installationId]?.nativeCleanup.removeValue(forKey: token) }
    }

    /// Read on every send from the main thread, so it comes from the snapshot.
    public var interceptsOutgoingMessages: Bool { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotIntercepts }

    private func outgoingRegistrations() -> [(String, DGPluginExecution, DGPluginRegisteredTransform)] {
        return executions.flatMap { id, execution -> [(String, DGPluginExecution, DGPluginRegisteredTransform)] in
            guard execution.state == .running, current(id, execution.generation),
                  let record = coordinator.state.installations.first(where: { $0.id == id }),
                  account(record).grants.contains(where: { $0.capability == "messages.intercept" && $0.scope == "activeComposer" }) else { return [] }
            return execution.transforms.values.filter { $0.slot == "outgoing" }.map { (id, execution, $0) }
        }.sorted { ($0.2.priority, $0.0, $0.2.id) < ($1.2.priority, $1.0, $1.2.id) }
    }

    public func interceptOutgoingText(_ text: String, completion: @escaping (Result<String?, DGPluginError>) -> Void) {
        coordinator.queue.async {
            let operation = DGPluginOutgoingOperation()
            let finish: (Result<String?, DGPluginError>) -> Void = { result in
                guard !operation.finished else { return }
                operation.finished = true
                DispatchQueue.main.async { completion(result) }
            }
            do {
                let input = try DGPluginOutgoingMessage.input(text)
                self.applyOutgoingInterceptors(self.outgoingRegistrations(), index: 0, input: input, operation: operation) { result in
                    switch result {
                    case let .success(value): finish(.success(value.objectValue?["cancelled"] == .bool(true) ? nil : value.objectValue?["text"]?.stringValue))
                    case let .failure(error): finish(.failure(error))
                    }
                }
                self.coordinator.queue.asyncAfter(deadline: .now() + 3) {
                    guard !operation.finished else { return }
                    finish(.failure(DGPluginError(code: "timeout", message: "outgoing plugin processing timed out; the draft was kept")))
                    if let id = operation.activeInstallation { self.fail(id: id, message: "outgoing message handler timed out") }
                }
            } catch { finish(.failure(self.pluginError(error))) }
        }
    }

    private func applyOutgoingInterceptors(_ registrations: [(String, DGPluginExecution, DGPluginRegisteredTransform)], index: Int, input: DGPluginJSON, operation: DGPluginOutgoingOperation, completion: @escaping (Result<DGPluginJSON, DGPluginError>) -> Void) {
        guard !operation.finished else { return }
        guard index < registrations.count, input.objectValue?["cancelled"] != .bool(true) else { completion(.success(input)); return }
        let (id, execution, registration) = registrations[index]
        guard current(id, execution.generation), execution.transforms[registration.id]?.slot == "outgoing", !execution.busy else { completion(.failure(DGPluginError(code: "busy", message: "outgoing plugin is unavailable; retry sending the draft"))); return }
        operation.activeInstallation = id
        let requestId = UUID().uuidString.lowercased()
        let pending = DGPluginPendingTransform(registrationId: registration.id, slot: "outgoing", input: input)
        execution.pendingTransforms[requestId] = pending
        execution.busy = true
        let payload = DGPluginJSON.object(["id": .string(registration.id), "requestId": .string(requestId), "input": input])
        guard let bytes = try? JSONEncoder().encode(payload), let json = String(data: bytes, encoding: .utf8) else {
            execution.busy = false
            execution.pendingTransforms.removeValue(forKey: requestId)
            completion(.failure(DGPluginError(code: "invalid_argument", message: "outgoing message could not be encoded")))
            return
        }
        execution.runtime?.dispatch(kind: "transform", payloadJSON: json) { outcome in
            self.coordinator.queue.async {
                execution.busy = false
                execution.pendingTransforms.removeValue(forKey: requestId)
                guard !operation.finished else { return }
                guard self.current(id, execution.generation), execution.transforms[registration.id]?.slot == "outgoing" else { completion(.failure(DGPluginError(code: "cancelled", message: "outgoing plugin permission changed"))); return }
                switch outcome {
                case .success where pending.result != nil:
                    self.applyOutgoingInterceptors(registrations, index: index + 1, input: pending.result!, operation: operation, completion: completion)
                case let .failure(error) where error.code != "plugin_rejected" && error.code != "runtime_busy":
                    self.fail(id: id, message: "outgoing message handler exceeded its budget or stopped")
                    completion(.failure(DGPluginError(code: "runtime_error", message: "outgoing plugin stopped; the draft was kept")))
                    return
                default:
                    // The handler's own error (or a busy runtime): keep the plugin running and the draft unsent.
                    var code = "plugin_error"
                    if case let .failure(error) = outcome { code = error.code == "runtime_busy" ? "busy" : (error.detail ?? "plugin_error") }
                    completion(.failure(DGPluginError(code: code, message: "outgoing plugin reported an error; the draft was kept")))
                }
                self.refreshDeferredViewModels()
                self.drainEvents(id: id)
            }
        }
    }

    public func transformedViewModel(slot: String, input: DGPluginJSON, update: @escaping () -> Void) -> DGPluginJSON {
        guard (try? DGPluginViewTransform.validateInput(slot: slot, input: input)) != nil else { return input }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(input) else { return input }
        let key = slot + ":" + DGPluginInstaller.digest(encoded)
        snapshotLock.lock(); let cached = viewModelCache[key]; snapshotLock.unlock()
        if let cached { return cached }
        coordinator.queue.async {
            guard !self.pendingViewModels.contains(key), self.pendingViewModels.count < 8 else { return }
            self.pendingViewModels.insert(key)
            let revision = self.viewModelRevision
            let registrations = self.executions.flatMap { id, execution -> [(String, DGPluginExecution, DGPluginRegisteredTransform)] in
                guard execution.state == .running, self.current(id, execution.generation), let record = self.coordinator.state.installations.first(where: { $0.id == id }), record.manifest.profile == "localPrivate", self.account(record).grants.contains(where: { $0.capability == "ui.transform" && $0.scope == slot }) else { return [] }
                return execution.transforms.values.filter { $0.slot == slot }.map { (id, execution, $0) }
            }.sorted { lhs, rhs in
                if lhs.2.priority != rhs.2.priority { return lhs.2.priority < rhs.2.priority }
                return (lhs.0, lhs.2.id) < (rhs.0, rhs.2.id)
            }
            self.applyViewTransforms(registrations, index: 0, slot: slot, input: input, revision: revision) { result, deferred in
                self.pendingViewModels.remove(key)
                guard revision == self.viewModelRevision else { return }
                if deferred {
                    if self.deferredViewUpdates.count < 16 { self.deferredViewUpdates[key] = update }
                    return
                }
                self.snapshotLock.lock()
                if self.viewModelCache.count >= 32 { self.viewModelCache.removeAll() }
                self.viewModelCache[key] = result
                self.snapshotLock.unlock()
                if result != input { DispatchQueue.main.async(execute: update) }
            }
        }
        return input
    }

    private func applyViewTransforms(_ registrations: [(String, DGPluginExecution, DGPluginRegisteredTransform)], index: Int, slot: String, input: DGPluginJSON, revision: UInt64, completion: @escaping (DGPluginJSON, Bool) -> Void) {
        guard revision == viewModelRevision, index < registrations.count else { completion(input, false); return }
        let (id, execution, registration) = registrations[index]
        guard current(id, execution.generation), execution.transforms[registration.id] != nil else { applyViewTransforms(registrations, index: index + 1, slot: slot, input: input, revision: revision, completion: completion); return }
        guard !execution.busy else { completion(input, true); return }
        let requestId = UUID().uuidString.lowercased()
        let pending = DGPluginPendingTransform(registrationId: registration.id, slot: slot, input: input)
        execution.pendingTransforms[requestId] = pending
        execution.busy = true
        let payload = DGPluginJSON.object(["id": .string(registration.id), "requestId": .string(requestId), "input": input])
        guard let bytes = try? JSONEncoder().encode(payload), let json = String(data: bytes, encoding: .utf8) else { execution.busy = false; execution.pendingTransforms.removeValue(forKey: requestId); completion(input, false); return }
        execution.runtime?.dispatch(kind: "transform", payloadJSON: json) { outcome in
            self.coordinator.queue.async {
                execution.busy = false
                execution.pendingTransforms.removeValue(forKey: requestId)
                guard revision == self.viewModelRevision, self.current(id, execution.generation), execution.transforms[registration.id] != nil else { completion(input, false); return }
                let output: DGPluginJSON
                if case .success = outcome, let result = pending.result {
                    execution.transformFailures = 0; output = result
                } else if case let .failure(error) = outcome, error.code != "plugin_rejected" {
                    if error.code == "runtime_busy" { completion(input, true); return }
                    self.fail(id: id, message: "plugin view-model transform exceeded its budget or stopped")
                    completion(input, false)
                    return
                } else {
                    // A rejected handler or a missing result keeps the native order; three in a row stop the plugin.
                    execution.transformFailures += 1; output = input
                    if execution.transformFailures >= 3 { self.fail(id: id, message: "plugin view-model transforms repeatedly failed") }
                }
                self.refreshDeferredViewModels()
                self.applyViewTransforms(registrations, index: index + 1, slot: slot, input: output, revision: revision, completion: completion)
                self.drainEvents(id: id)
            }
        }
    }

    private func invalidateViewModels() {
        viewModelRevision &+= 1
        snapshotLock.lock(); viewModelCache.removeAll(); snapshotLock.unlock()
        refreshDeferredViewModels()
    }

    private func refreshDeferredViewModels() {
        let callbacks = Array(deferredViewUpdates.values); deferredViewUpdates.removeAll()
        if !callbacks.isEmpty { DispatchQueue.main.async { callbacks.forEach { $0() } } }
    }

    @discardableResult public func observe(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID()
        snapshotLock.lock(); observers[id] = callback; snapshotLock.unlock()
        DispatchQueue.main.async(execute: callback)
        return id
    }

    public func removeObserver(_ id: UUID) { snapshotLock.lock(); observers.removeValue(forKey: id); snapshotLock.unlock() }

    private func account(_ record: DGPluginStoredRecord) -> DGPluginAccountRecord {
        return record.accounts[accountKey] ?? DGPluginAccountRecord(settings: DGPluginPolicy.settingsDefaults(record.manifest))
    }

    fileprivate func publish() {
        var icons: [String: Data] = [:]
        let values = coordinator.state.installations.map { record -> DGPluginInstallation in
            let account = self.account(record)
            let state: DGPluginState
            if record.removing { state = .removing }
            else if account.failures >= 3 { state = .quarantined }
            else if let execution = executions[record.id] { state = execution.state }
            else if !requiredGranted(record, account) && account.enabled { state = .permissionRequired }
            else if account.lastError != nil { state = .failed }
            else { state = .installedDisabled }
            if let package = try? coordinator.package(record), let data = package.iconData, data.count <= 262144 { icons[record.id] = data }
            let trust = (coordinator.state.revokedPublishers ?? []).contains(record.publisherIdentity) ? "revoked" : record.trust
            return DGPluginInstallation(id: record.id, manifest: record.manifest, digest: record.digest, trust: trust, enabled: account.enabled, state: state, grants: account.grants, settings: account.settings, lastError: account.lastError ?? coordinator.startupError?.message)
        }
        let commands = executions.values.filter { $0.state == .running }.flatMap { $0.commands }.sorted { ($0.installationId, $0.id) < ($1.installationId, $1.id) }
        var transformSlots = Set<String>()
        for (id, execution) in executions where execution.state == .running && current(id, execution.generation) {
            guard let record = coordinator.state.installations.first(where: { $0.id == id }), record.manifest.profile == "localPrivate" else { continue }
            let grants = account(record).grants
            for transform in execution.transforms.values where transform.slot != "outgoing" && grants.contains(where: { $0.capability == "ui.transform" && $0.scope == transform.slot }) {
                transformSlots.insert(transform.slot)
            }
        }
        let intercepts = !outgoingRegistrations().isEmpty
        let publishers = Dictionary(coordinator.state.installations.map { ($0.id, $0.publisherIdentity) }, uniquingKeysWith: { first, _ in first })
        let diagnostics = Dictionary(coordinator.state.installations.map { ($0.id, self.account($0).diagnostics ?? []) }, uniquingKeysWith: { first, _ in first })
        snapshotLock.lock()
        snapshotTransformSlots = transformSlots; snapshotViewRevision = viewModelRevision
        snapshotIntercepts = intercepts; snapshotPublishers = publishers; snapshotDiagnostics = diagnostics
        snapshotInstallations = values; snapshotCommands = commands; snapshotIcons = icons; snapshotEnabled = coordinator.state.globallyEnabled
        snapshotRollbackIds = Set(coordinator.state.installations.filter { $0.previous != nil && !$0.removing }.map { $0.id })
        snapshotPersistenceError = coordinator.persistenceError ?? coordinator.deferredSaveError
        let callbacks = Array(observers.values)
        snapshotLock.unlock()
        DispatchQueue.main.async { for callback in callbacks { callback() } }
    }

    private func requiredGranted(_ record: DGPluginStoredRecord, _ account: DGPluginAccountRecord) -> Bool {
        let keys = Set(account.grants.map(DGPluginPolicy.permissionKey))
        return record.manifest.permissions.allSatisfy { keys.contains(DGPluginPolicy.permissionKey($0)) }
    }

    public func install(_ package: DGVerifiedPluginPackage, completion: @escaping (Result<String, DGPluginError>) -> Void) {
        coordinator.queue.async {
            do {
                guard Self.executionAvailable else { throw DGPluginError(code: "feature_unavailable", message: "external plugins are disabled in this distribution") }
                try DGPluginPolicy.validateProfile(package.manifest)
                guard !(self.coordinator.state.revokedPublishers ?? []).contains(package.publisherIdentity) else { throw DGPluginError(code: "source_revoked", message: "this publisher key has been revoked on this device") }
                let verified = try DGPluginInstaller.preview(data: package.originalData, fileName: package.fileName)
                guard verified.digest == package.digest else { throw DGPluginError(code: "integrity_error", message: "package changed since preview") }
                let previousState = self.coordinator.state
                var record: DGPluginStoredRecord
                if let existing = self.coordinator.state.installations.first(where: { $0.manifest.id == package.manifest.id }) {
                    guard !existing.removing else { throw DGPluginError(code: "conflict", message: "finish removing the previous installation first") }
                    guard existing.manifest.profile == package.manifest.profile else { throw DGPluginError(code: "permission_denied", message: "changing execution profile requires removing the old installation and its data") }
                    guard self.version(package.manifest.version, isNewerThan: existing.manifest.version) else { throw DGPluginError(code: "conflict", message: "only a newer reviewed version can replace this installation") }
                    guard existing.publisherIdentity == package.publisherIdentity else { throw DGPluginError(code: "publisher_changed", message: "remove the old installation before changing publisher") }
                    self.coordinator.stopAll(id: existing.id)
                    record = existing
                    record.previous = DGPluginPreviousVersion(manifest: existing.manifest, digest: existing.digest, publisherIdentity: existing.publisherIdentity, trust: existing.trust, fileName: existing.fileName, accounts: existing.accounts)
                    let allowed = Set((package.manifest.permissions + package.manifest.optionalPermissions).map(DGPluginPolicy.permissionKey))
                    for key in record.accounts.keys {
                        record.accounts[key]?.enabled = false
                        record.accounts[key]?.grants.removeAll { !allowed.contains(DGPluginPolicy.permissionKey($0)) }
                        record.accounts[key]?.lastError = nil
                        record.accounts[key]?.failures = 0
                        if let settings = record.accounts[key]?.settings, (try? DGPluginPolicy.validateSettings(settings, manifest: package.manifest)) == nil { record.accounts[key]?.settings = DGPluginPolicy.settingsDefaults(package.manifest) }
                    }
                    record.manifest = package.manifest; record.digest = package.digest; record.trust = package.trust; record.fileName = package.fileName
                } else {
                    guard self.coordinator.state.installations.count < 32 else { throw DGPluginError(code: "quota_exceeded", message: "installation limit reached") }
                    record = DGPluginStoredRecord(id: UUID().uuidString.lowercased(), manifest: package.manifest, digest: package.digest, publisherIdentity: package.publisherIdentity, trust: package.trust, fileName: package.fileName)
                    record.accounts[self.accountKey] = DGPluginAccountRecord(settings: DGPluginPolicy.settingsDefaults(package.manifest))
                }
                let destination = self.coordinator.packageURL(record)
                try self.coordinator.testFailure("packageWrite")
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try package.originalData.write(to: destination, options: .atomic)
                self.coordinator.state.installations.removeAll { $0.id == record.id }
                self.coordinator.state.installations.append(record)
                do { try self.coordinator.persist() } catch { self.coordinator.state = previousState; throw error }
                self.coordinator.packages[package.digest] = package
                try? self.coordinator.pruneVersions(record)
                self.coordinator.publishAll()
                let installationId = record.id
                DispatchQueue.main.async { completion(.success(installationId)) }
            } catch { self.reconcile(); self.coordinator.publishAll(); self.complete(completion, error: error) }
        }
    }

    private func version(_ value: String, isNewerThan previous: String) -> Bool {
        guard let left = DGPluginSemanticVersion(value), let right = DGPluginSemanticVersion(previous) else { return false }
        return left > right
    }

    public func setEnabled(id: String, enabled: Bool, completion: @escaping (Result<Void, DGPluginError>) -> Void) {
        coordinator.queue.async {
            do {
                guard let index = self.coordinator.state.installations.firstIndex(where: { $0.id == id && !$0.removing }) else { throw DGPluginError(code: "stale_handle", message: "installation is no longer available") }
                let record = self.coordinator.state.installations[index]
                var account = self.account(record)
                if enabled {
                    guard Self.executionAvailable else { throw DGPluginError(code: "feature_unavailable", message: "external execution is unavailable") }
                    guard self.executions[id] != nil || self.executions.count < 4 else { throw DGPluginError(code: "quota_exceeded", message: "at most four plugin runtimes may run for one account") }
                    guard self.requiredGranted(record, account) else { throw DGPluginError(code: "permission_denied", message: "grant required permissions before enabling this plugin") }
                    try DGPluginPolicy.validateProfile(record.manifest)
                    if account.failures >= 3 { account.failures = 0 }
                    account.lastError = nil
                }
                account.enabled = enabled
                if !enabled { self.stop(id: id) }
                self.coordinator.state.installations[index].accounts[self.accountKey] = account
                do { try self.coordinator.persist() } catch {
                    if enabled { self.coordinator.state.installations[index] = record }
                    self.coordinator.publishAll()
                    throw DGPluginError(code: "storage_error", message: "unable to save plugin state; execution has stopped")
                }
                if !enabled { self.stop(id: id); self.coordinator.publishAll(); DispatchQueue.main.async { completion(.success(())) } }
                else { self.start(id: id, completion: completion) }
            } catch { self.complete(completion, error: error) }
        }
    }

    public func setGloballyEnabled(_ enabled: Bool) {
        coordinator.queue.async {
            let previous = self.coordinator.state.globallyEnabled
            self.coordinator.state.globallyEnabled = enabled
            if !enabled { self.coordinator.stopAll() }
            do { try self.coordinator.persist(); self.coordinator.persistenceError = nil } catch {
                if enabled { self.coordinator.state.globallyEnabled = previous }
                self.coordinator.persistenceError = "unable to save the global switch; execution remains stopped for this session"
                self.coordinator.publishAll()
                return
            }
            if enabled { for manager in Self.allManagers() { manager.reconcile() } } else { self.coordinator.stopAll() }
            self.coordinator.publishAll()
        }
    }

    public func setGrants(id: String, permissions: [DGPluginPermission], completion: @escaping (Result<Void, DGPluginError>) -> Void) {
        mutate(id: id, completion: completion) { record, account in
            let declared = Set((record.manifest.permissions + record.manifest.optionalPermissions).map(DGPluginPolicy.permissionKey))
            guard permissions.allSatisfy({ declared.contains(DGPluginPolicy.permissionKey($0)) }) else { throw DGPluginError(code: "permission_denied", message: "permission was not declared by this package") }
            account.grants = permissions
            account.enabled = false
            account.lastError = nil
        }
    }

    public func updateSettings(id: String, values: [String: DGPluginJSON], completion: @escaping (Result<Void, DGPluginError>) -> Void) {
        mutate(id: id, stop: false, completion: completion) { record, account in
            try DGPluginPolicy.validateSettings(values, manifest: record.manifest)
            account.settings = values
        }
    }

    public func resetData(id: String, completion: @escaping (Result<Void, DGPluginError>) -> Void) {
        mutate(id: id, clearPrevious: true, completion: completion) { record, account in
            account.storage = [:]; account.settings = DGPluginPolicy.settingsDefaults(record.manifest); account.enabled = false; account.diagnostics = nil
        }
    }

    public func rollback(id: String, completion: @escaping (Result<Void, DGPluginError>) -> Void) {
        coordinator.queue.async {
            do { try self.restorePrevious(id: id); self.coordinator.publishAll(); DispatchQueue.main.async { completion(.success(())) } }
            catch { self.complete(completion, error: error) }
        }
    }

    private func restorePrevious(id: String) throws {
        guard let index = coordinator.state.installations.firstIndex(where: { $0.id == id && !$0.removing }), let previous = coordinator.state.installations[index].previous else { throw DGPluginError(code: "feature_unavailable", message: "no previous installed version is available") }
        let current = coordinator.state.installations[index]
        guard previous.publisherIdentity == current.publisherIdentity, previous.manifest.profile == current.manifest.profile, !(coordinator.state.revokedPublishers ?? []).contains(previous.publisherIdentity) else { throw DGPluginError(code: "permission_denied", message: "previous version is not eligible for rollback") }
        var restored = current
        restored.manifest = previous.manifest; restored.digest = previous.digest; restored.publisherIdentity = previous.publisherIdentity; restored.trust = previous.trust; restored.fileName = previous.fileName; restored.previous = nil
        restored.accounts = previous.accounts
        for key in restored.accounts.keys {
            let retained = Set((current.accounts[key]?.grants ?? []).map(DGPluginPolicy.permissionKey))
            restored.accounts[key]?.enabled = false
            restored.accounts[key]?.grants.removeAll { !retained.contains(DGPluginPolicy.permissionKey($0)) }
            restored.accounts[key]?.lastError = nil
        }
        _ = try coordinator.package(restored)
        coordinator.stopAll(id: id)
        coordinator.state.installations[index] = restored
        do { try coordinator.persist() } catch { coordinator.state.installations[index] = current; throw error }
        try? coordinator.pruneVersions(restored)
    }

    public func setPublisherRevoked(_ identity: String, revoked: Bool, completion: @escaping (Result<Void, DGPluginError>) -> Void) {
        coordinator.queue.async {
            do {
                guard identity.hasPrefix("ed25519:"), identity.count == 72, identity.dropFirst(8).allSatisfy({ $0.isHexDigit }) else { throw DGPluginError(code: "invalid_argument", message: "invalid publisher fingerprint") }
                var identities = Set(self.coordinator.state.revokedPublishers ?? [])
                if revoked { identities.insert(identity) } else { identities.remove(identity) }
                guard identities.count <= 256 else { throw DGPluginError(code: "quota_exceeded", message: "publisher revocation limit reached") }
                self.coordinator.state.revokedPublishers = identities.sorted()
                if revoked {
                    for index in self.coordinator.state.installations.indices where self.coordinator.state.installations[index].publisherIdentity == identity {
                        let id = self.coordinator.state.installations[index].id
                        self.coordinator.stopAll(id: id)
                        for key in self.coordinator.state.installations[index].accounts.keys {
                            self.coordinator.state.installations[index].accounts[key]?.enabled = false
                            self.coordinator.state.installations[index].accounts[key]?.grants = []
                        }
                    }
                }
                do { try self.coordinator.persist() } catch { self.coordinator.publishAll(); throw DGPluginError(code: "storage_error", message: "publisher execution stopped but revocation could not be saved") }
                self.coordinator.publishAll()
                DispatchQueue.main.async { completion(.success(())) }
            } catch { self.complete(completion, error: error) }
        }
    }

    private func mutate(id: String, stop: Bool = true, clearPrevious: Bool = false, completion: @escaping (Result<Void, DGPluginError>) -> Void, action: @escaping (DGPluginStoredRecord, inout DGPluginAccountRecord) throws -> Void) {
        coordinator.queue.async {
            do {
                guard let index = self.coordinator.state.installations.firstIndex(where: { $0.id == id && !$0.removing }) else { throw DGPluginError(code: "stale_handle", message: "installation is unavailable") }
                let record = self.coordinator.state.installations[index]
                var account = self.account(record)
                try action(record, &account)
                if stop { self.stop(id: id) }
                self.coordinator.state.installations[index].accounts[self.accountKey] = account
                if clearPrevious { self.coordinator.state.installations[index].previous = nil }
                do { try self.coordinator.persist() } catch {
                    if !stop { self.coordinator.state.installations[index] = record }
                    self.coordinator.publishAll()
                    throw DGPluginError(code: "storage_error", message: "unable to save plugin state; changes may not survive restart")
                }
                self.coordinator.publishAll()
                DispatchQueue.main.async { completion(.success(())) }
            } catch { self.complete(completion, error: error) }
        }
    }

    public func remove(id: String, completion: @escaping (Result<Void, DGPluginError>) -> Void) {
        coordinator.queue.async {
            do {
                guard let index = self.coordinator.state.installations.firstIndex(where: { $0.id == id }) else { throw DGPluginError(code: "stale_handle", message: "installation is already removed") }
                self.coordinator.state.installations[index].removing = true
                do { try self.coordinator.persist() } catch {
                    self.coordinator.stopAll(id: id)
                    throw DGPluginError(code: "storage_error", message: "execution stopped; removal could not be saved and needs retry")
                }
                self.coordinator.stopAll(id: id)
                self.coordinator.publishAll()
                try self.coordinator.cleanupFiles(self.coordinator.state.installations[index])
                self.coordinator.state.installations.remove(at: index)
                try self.coordinator.persist()
                self.coordinator.publishAll()
                DispatchQueue.main.async { completion(.success(())) }
            } catch { self.coordinator.publishAll(); self.complete(completion, error: error) }
        }
    }

    fileprivate func stop(id: String) {
        guard let execution = executions.removeValue(forKey: id) else { return }
        coordinator.clearRunning(DGPluginRunningMarker(account: accountKey, installation: id))
        invalidateViewModels()
        execution.state = .stopping
        execution.commands.removeAll(); execution.contributions.removeAll(); execution.subscriptions.removeAll()
        execution.runtime?.stop()
        let cleanup = execution.cleanup + Array(execution.pageCleanup.values) + Array(execution.nativeCleanup.values)
        execution.nativeCleanup = [:]
        for cancel in execution.networkRequests.values { cancel() }
        execution.networkRequests = [:]
        execution.cleanup = []
        execution.pageCleanup = [:]; execution.pageTokens = [:]; execution.assets = [:]
        DispatchQueue.main.async { cleanup.forEach { $0() } }
    }

    fileprivate func stopAll() { for id in Array(executions.keys) { stop(id: id) } }

    fileprivate func reconcile() {
        guard coordinator.activeAccountKey == accountKey else { return }
        for record in coordinator.state.installations where !record.removing {
            let account = self.account(record)
            if account.enabled && account.failures < 3 && account.lastError == nil && executions[record.id] == nil { start(id: record.id, completion: { _ in }) }
        }
    }

    private func current(_ id: String, _ generation: UUID) -> Bool {
        guard Self.executionAvailable, coordinator.startupError == nil, coordinator.state.globallyEnabled, coordinator.foreground, !coordinator.powerSaving, coordinator.activeAccountKey == accountKey, executions[id]?.generation == generation, let record = coordinator.state.installations.first(where: { $0.id == id && !$0.removing }), !(coordinator.state.revokedPublishers ?? []).contains(record.publisherIdentity), account(record).enabled else { return false }
        return true
    }

    private func start(id: String, completion: @escaping (Result<Void, DGPluginError>) -> Void) {
        do {
            guard let record = coordinator.state.installations.first(where: { $0.id == id && !$0.removing }) else { throw DGPluginError(code: "stale_handle", message: "installation is unavailable") }
            stop(id: id)
            guard coordinator.activeAccountKey == accountKey, coordinator.foreground, !coordinator.powerSaving, coordinator.state.globallyEnabled else {
                coordinator.publishAll(); DispatchQueue.main.async { completion(.success(())) }; return
            }
            guard requiredGranted(record, account(record)) else { throw DGPluginError(code: "permission_denied", message: "required permissions were revoked") }
            guard executions.count < 4 else { throw DGPluginError(code: "quota_exceeded", message: "active plugin runtime limit reached") }
            let package = try coordinator.package(record)
            let execution = DGPluginExecution()
            executions[id] = execution
            coordinator.markRunning(DGPluginRunningMarker(account: accountKey, installation: id))
            let environmentJSON = String(data: try JSONEncoder().encode(DGPluginJSON.object(environment)), encoding: .utf8) ?? "{}"
            let runtime = try DGPluginRuntime(files: package.files, entry: package.manifest.entry, environmentJSON: environmentJSON, request: { [weak self, weak execution] request, reply in
                guard let self = self, let execution = execution else { reply("{\"error\":{\"code\":\"plugin_disabled\",\"message\":\"plugin stopped\"}}"); return }
                self.coordinator.queue.async { self.handle(request, installationId: id, generation: execution.generation, reply: reply) }
            })
            execution.runtime = runtime
            runtime.start { [weak self, weak execution] result in
                guard let self = self, let execution = execution else { return }
                self.coordinator.queue.async {
                    guard self.current(id, execution.generation) else { DispatchQueue.main.async { completion(.failure(DGPluginError(code: "cancelled", message: "activation was cancelled"))) }; return }
                    switch result {
                    case .success:
                        execution.state = .running
                        self.invalidateViewModels()
                        self.emitNativeEvent(name: "plugin.activated", payload: .object([:]), installationId: id)
                        self.emitNativeEvent(name: "account.contextChanged", payload: .object(["active": .bool(true)]), installationId: id)
                        self.emitNativeEvent(name: "app.foreground", payload: .object(["active": .bool(true)]), installationId: id)
                        self.coordinator.publishAll()
                        DispatchQueue.main.async { completion(.success(())) }
                    case .failure:
                        self.fail(id: id, message: "plugin activation failed or exceeded its budget")
                        DispatchQueue.main.async { completion(.failure(DGPluginError(code: "runtime_error", message: "plugin activation failed"))) }
                    }
                }
            }
            coordinator.publishAll()
        } catch { fail(id: id, message: "plugin could not start"); complete(completion, error: error) }
    }

    private func fail(id: String, message: String) {
        let activationFailed = executions[id]?.state == .starting
        stop(id: id)
        if activationFailed, let record = coordinator.state.installations.first(where: { $0.id == id }), record.previous != nil { try? restorePrevious(id: id) }
        if let index = coordinator.state.installations.firstIndex(where: { $0.id == id }) {
            var account = self.account(coordinator.state.installations[index])
            account.failures += 1; account.lastError = message; account.enabled = false
            let entry = ISO8601DateFormatter().string(from: Date()) + " " + message
            account.diagnostics = Array(((account.diagnostics ?? []) + [entry]).suffix(20))
            coordinator.state.installations[index].accounts[accountKey] = account
            try? coordinator.persist()
        }
        coordinator.publishAll()
    }

    public func runCommand(installationId: String, commandId: String, input: DGPluginJSON = .null, completion: @escaping (Result<Void, DGPluginError>) -> Void) {
        coordinator.queue.async {
            guard let execution = self.executions[installationId], execution.state == .running, !execution.busy, self.current(installationId, execution.generation), execution.commands.contains(where: { $0.id == commandId }) else { self.complete(completion, error: DGPluginError(code: "plugin_disabled", message: "command is no longer available or is already running")); return }
            execution.busy = true
            execution.commandEpoch = UUID()
            execution.gestureUntil = ProcessInfo.processInfo.systemUptime + 5
            let epoch = execution.commandEpoch
            do {
                let payload = DGPluginJSON.object(["id": .string(commandId), "input": input])
                let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8) ?? "{}"
                execution.runtime?.dispatch(kind: "command", payloadJSON: json) { result in
                    self.coordinator.queue.async {
                        guard self.current(installationId, execution.generation), execution.commandEpoch == epoch else { self.complete(completion, error: DGPluginError(code: "cancelled", message: "command was cancelled")); return }
                        execution.gestureUntil = 0
                        execution.busy = false
                        self.refreshDeferredViewModels()
                        self.drainEvents(id: installationId)
                        switch result {
                        case .success: DispatchQueue.main.async { completion(.success(())) }
                        case let .failure(error):
                            if error.code == "runtime_busy" { self.complete(completion, error: DGPluginError(code: "busy", message: "a plugin callback is still running; retry the command")) }
                            else if error.code == "plugin_rejected" {
                                // The command's own error (often a native refusal it did not catch): report it, keep the plugin on.
                                self.complete(completion, error: DGPluginError(code: error.detail ?? "plugin_error", message: "the plugin command reported an error"))
                            }
                            else { self.fail(id: installationId, message: "plugin command exceeded its budget or stopped"); self.complete(completion, error: DGPluginError(code: "runtime_error", message: "command failed")) }
                        }
                    }
                }
            } catch { execution.busy = false; execution.gestureUntil = 0; self.complete(completion, error: error) }
        }
    }

    private func handle(_ request: String, installationId: String, generation: UUID, reply: @escaping (String) -> Void) {
        do {
            guard request.utf8.count <= 262144, let data = request.data(using: .utf8), case let .object(envelope) = try JSONDecoder().decode(DGPluginJSON.self, from: data), let method = envelope["method"]?.dgString, let rule = DGPluginPolicy.methods[method] else { throw DGPluginError(code: "feature_unavailable", message: "unknown plugin method") }
            let params = envelope["params"] ?? .object([:])
            guard case .object = params else { throw DGPluginError(code: "invalid_argument", message: "method parameters must be an object") }
            guard current(installationId, generation), let execution = executions[installationId], let index = coordinator.state.installations.firstIndex(where: { $0.id == installationId }) else { throw DGPluginError(code: "plugin_disabled", message: "plugin execution is no longer current") }
            let now = ProcessInfo.processInfo.systemUptime
            if now - execution.windowStart >= 60 { execution.windowStart = now; execution.requests = 0; execution.networkCount = 0 }
            execution.requests += 1
            guard execution.requests <= 600 else { throw DGPluginError(code: "quota_exceeded", message: "plugin request budget exceeded") }
            let record = coordinator.state.installations[index]
            let account = self.account(record)
            try authorize(rule, record: record, account: account, execution: execution)
            guard rule.available else { throw DGPluginError(code: "feature_unavailable", message: "this adapter is not available in this client") }
            if ["messages.send", "messages.edit", "messages.delete"].contains(method) {
                // They need no per-message gesture, so a loop or a buggy handler could flood the open chat and get the
                // account limited: at most five in ten seconds and twenty a minute, whatever the adapter answers.
                execution.messageActionTimes.removeAll { now - $0 >= 60 }
                guard execution.messageActionTimes.count < 20, execution.messageActionTimes.filter({ now - $0 < 10 }).count < 5 else {
                    throw DGPluginError(code: "rate_limited", message: "plugins may send, edit or delete at most five messages in ten seconds and twenty a minute")
                }
                execution.messageActionTimes.append(now)
            } else if method == "ui.toast" {
                execution.noticeTimes.removeAll { now - $0 >= 10 }
                guard execution.noticeTimes.count < 5 else { throw DGPluginError(code: "rate_limited", message: "plugins may show at most five notices in ten seconds") }
                execution.noticeTimes.append(now)
            }
            if let result = try local(method: method, params: params, index: index, execution: execution) { respond(.success(result), reply); return }
            let epoch = execution.commandEpoch
            let waitsForUser = ["messages.sendInteractive", "messages.compose", "translation.request", "files.pick", "notifications.local"].contains(method)
            let validity = { [weak self] () -> Bool in
                guard let self = self else { return false }
                return self.coordinator.queue.sync { self.current(installationId, generation) && (!rule.requiresGesture || (self.executions[installationId]?.commandEpoch == epoch && (waitsForUser || ProcessInfo.processInfo.systemUptime <= (self.executions[installationId]?.gestureUntil ?? 0)))) }
            }
            if method == "network.request" {
                guard record.manifest.profile == "publicNetwork", execution.networkRequests.count < 4, execution.networkCount < 30 else { throw DGPluginError(code: "quota_exceeded", message: "public request quota exceeded") }
                let origins = account.grants.filter { $0.capability == "network.public" && $0.scope == "declaredOrigins" }.flatMap { $0.origins }
                let token = UUID()
                execution.networkCount += 1
                let cancel = DGPluginPublicNetwork.request(params: params, allowedOrigins: origins, validity: validity) { result in
                    self.coordinator.queue.async {
                        execution.networkRequests.removeValue(forKey: token)
                        guard self.current(installationId, generation) else { self.respond(.failure(DGPluginError(code: "cancelled", message: "public request cancelled")), reply); return }
                        self.respond(result, reply)
                    }
                }
                execution.networkRequests[token] = cancel
                return
            }
            if method == "ui.render" {
                guard let renderer = nativeRender, case let .object(page) = params, let pageId = page["id"]?.dgString, !pageId.isEmpty, pageId.utf8.count <= 64, !execution.pagesPending.contains(pageId), execution.contributions.isEmpty || execution.contributions[pageId] != nil else { throw DGPluginError(code: "feature_unavailable", message: "one plugin page may be open at a time") }
                let pageToken = UUID()
                let previousToken = execution.pageTokens[pageId]
                execution.pageTokens[pageId] = pageToken
                execution.pagesPending.insert(pageId)
                execution.contributions[pageId] = .null
                let pluginName = record.manifest.name
                var renderedPage = page
                renderedPage["__dgThemeTokens"] = execution.themeTokens
                let nativePage = DGPluginJSON.object(renderedPage)
                let assetProvider = { [weak self] (handle: String) -> Data? in
                    guard let self = self else { return nil }
                    return self.coordinator.queue.sync {
                        guard self.current(installationId, generation) else { return nil }
                        return self.executions[installationId]?.assets[handle]
                    }
                }
                let closed = { [weak self] in
                    guard let self = self else { return }
                    self.coordinator.queue.async {
                        guard self.current(installationId, generation), execution.pageTokens[pageId] == pageToken else { return }
                        execution.pageTokens.removeValue(forKey: pageId)
                        execution.pageCleanup.removeValue(forKey: pageId)
                        execution.contributions.removeValue(forKey: pageId)
                    }
                }
                DispatchQueue.main.async {
                    guard validity() else { self.respond(.failure(DGPluginError(code: "cancelled", message: "page cancelled")), reply); return }
                    let result = renderer(installationId, nativePage, pluginName, validity, assetProvider, { [weak self] callbackId, value in
                        self?.dispatchUICallback(installationId: installationId, generation: generation, callbackId: callbackId, value: value)
                    }, closed)
                    self.coordinator.queue.async {
                        execution.pagesPending.remove(pageId)
                        switch result {
                        case let .success(cleanup):
                            guard self.current(installationId, generation) else { DispatchQueue.main.async(execute: cleanup); self.respond(.failure(DGPluginError(code: "cancelled", message: "plugin stopped")), reply); return }
                            execution.pageCleanup[pageId] = cleanup
                            execution.contributions[pageId] = .null
                            self.respond(.success(.string(pageId)), reply)
                        case let .failure(error):
                            if let previousToken { execution.pageTokens[pageId] = previousToken }
                            else { execution.pageTokens.removeValue(forKey: pageId); execution.contributions.removeValue(forKey: pageId) }
                            self.respond(.failure(error), reply)
                        }
                    }
                }
                return
            }
            guard let adapter = nativeRequest else { throw DGPluginError(code: "feature_unavailable", message: "no native adapter is attached to this screen") }
            DispatchQueue.main.async {
                guard validity() else { self.respond(.failure(DGPluginError(code: "cancelled", message: "native operation cancelled")), reply); return }
                adapter(installationId, method, params, validity) { result in
                    self.coordinator.queue.async {
                        guard self.current(installationId, generation) else { self.respond(.failure(DGPluginError(code: "cancelled", message: "permission or account context changed")), reply); return }
                        do {
                            guard let currentRecord = self.coordinator.state.installations.first(where: { $0.id == installationId }) else { throw DGPluginError(code: "stale_handle", message: "installation removed") }
                            guard !rule.requiresGesture || execution.commandEpoch == epoch else { throw DGPluginError(code: "cancelled", message: "native action no longer belongs to this gesture") }
                            try self.authorize(rule, record: currentRecord, account: self.account(currentRecord), execution: execution, allowNativeWait: waitsForUser)
                            self.respond(result, reply)
                        } catch { self.respond(.failure(self.pluginError(error)), reply) }
                    }
                }
            }
        } catch { respond(.failure(pluginError(error)), reply) }
    }

    private func authorize(_ rule: DGPluginMethodRule, record: DGPluginStoredRecord, account: DGPluginAccountRecord, execution: DGPluginExecution, allowNativeWait: Bool = false) throws {
        try DGPluginPolicy.validateProfile(record.manifest)
        if let capability = rule.capability {
            let declared = Set((record.manifest.permissions + record.manifest.optionalPermissions).map(DGPluginPolicy.permissionKey))
            guard account.grants.contains(where: { $0.capability == capability && (rule.scope == nil || $0.scope == rule.scope!) && declared.contains(DGPluginPolicy.permissionKey($0)) }) else {
                throw DGPluginError(code: "permission_denied", message: "required capability or scope was not granted")
            }
        }
        if rule.requiresGesture && !allowNativeWait && ProcessInfo.processInfo.systemUptime > execution.gestureUntil { throw DGPluginError(code: "permission_denied", message: "this operation requires a current native user action") }
    }

    private func local(method: String, params: DGPluginJSON, index: Int, execution: DGPluginExecution) throws -> DGPluginJSON? {
        let arguments = params.dgObject ?? [:]
        let record = coordinator.state.installations[index]
        var account = self.account(record)
        switch method {
        case "environment.get": return .object(environment)
        case "settings.get": return .object(account.settings)
        case "settings.set":
            guard let values = arguments["values"]?.dgObject else { throw DGPluginError(code: "invalid_argument", message: "expected settings values") }
            try DGPluginPolicy.validateSettings(values, manifest: record.manifest)
            account.settings = values
        case "capabilities.has":
            guard let name = arguments["capability"]?.dgString else { throw DGPluginError(code: "invalid_argument", message: "expected capability") }
            return .bool(account.grants.contains { $0.capability == name && (name != "ui.transform" || ["profile", "chatList"].contains($0.scope)) } && DGPluginPolicy.methods.values.contains { $0.capability == name && $0.available })
        case "capabilities.list":
            return .object(Dictionary(uniqueKeysWithValues: DGPluginPolicy.methods.map { name, rule in
                (name, .bool(rule.available && (rule.capability == nil || account.grants.contains { $0.capability == rule.capability && (rule.capability != "ui.transform" || ["profile", "chatList"].contains($0.scope)) })))
            }))
        case "storage.keys": return .array(account.storage.keys.sorted().map(DGPluginJSON.string))
        case "storage.get", "storage.set", "storage.remove":
            guard let key = arguments["key"]?.dgString, !key.isEmpty, key.utf8.count <= 128, !["__proto__", "prototype", "constructor"].contains(key) else { throw DGPluginError(code: "invalid_argument", message: "invalid storage key") }
            if method == "storage.get" { return account.storage[key] ?? .null }
            // The quota is kept as a running estimate per execution, so a write no longer encodes the whole storage.
            var bytes = try execution.storageBytes ?? account.storage.reduce(0) { $0 + (try Self.storageEntryBytes(key: $1.key, value: $1.value)) }
            if let old = account.storage[key] { bytes -= try Self.storageEntryBytes(key: key, value: old) }
            if method == "storage.remove" { account.storage.removeValue(forKey: key) }
            else {
                guard let value = arguments["value"], try JSONEncoder().encode(value).count <= 262144, account.storage.count < 1024 || account.storage[key] != nil else { throw DGPluginError(code: "quota_exceeded", message: "storage item exceeds its quota") }
                try value.validateLimits()
                bytes += try Self.storageEntryBytes(key: key, value: value)
                guard bytes <= 5 * 1024 * 1024 else { throw DGPluginError(code: "quota_exceeded", message: "plugin storage quota exceeded") }
                account.storage[key] = value
            }
            execution.storageBytes = bytes
        case "ui.command.register":
            guard let id = arguments["id"]?.dgString, id.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$", options: .regularExpression) != nil, let title = arguments["title"]?.dgString, !title.isEmpty, title.utf16.count <= 100, let placement = arguments["placement"]?.dgString, ["composer", "selection", "messageMenu", "chatToolbar", "settings"].contains(placement), execution.commands.count < 32 || execution.commands.contains(where: { $0.id == id }) else { throw DGPluginError(code: "invalid_argument", message: "invalid command descriptor") }
            guard account.grants.contains(where: { $0.capability == "ui.contribute" && ($0.scope == placement || $0.scope == "supportedSlots") }) else { throw DGPluginError(code: "scope_denied", message: "command placement was not granted") }
            execution.commands.removeAll { $0.id == id }
            execution.commands.append(DGPluginCommandDescriptor(installationId: record.id, id: id, title: title, placement: placement))
            coordinator.publishAll()
            return .string(id)
        case "ui.command.unregister":
            guard let id = arguments["id"]?.dgString else { throw DGPluginError(code: "invalid_argument", message: "expected command id") }
            execution.commands.removeAll { $0.id == id }; coordinator.publishAll(); return .null
        case "ui.transform.register", "messages.interceptor.register":
            let outgoing = method == "messages.interceptor.register"
            let allowedSlots = outgoing ? ["outgoing"] : ["profile", "chatList", "displayLinks"]
            let transformCapability = outgoing ? "messages.intercept" : "ui.transform"
            guard Set(arguments.keys).isSubset(of: ["id", "slot", "priority"]), let id = arguments["id"]?.dgString, id.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$", options: .regularExpression) != nil, let slot = arguments["slot"]?.dgString, allowedSlots.contains(slot), account.grants.contains(where: { $0.capability == transformCapability && $0.scope == (outgoing ? "activeComposer" : slot) }), execution.transforms.count < 8 || execution.transforms[id] != nil else { throw DGPluginError(code: "scope_denied", message: "invalid or ungranted local transform slot") }
            guard slot != "displayLinks" else { throw DGPluginError(code: "feature_unavailable", message: "displayed-link transforms have no native screen adapter in this client") }
            let priority = arguments["priority"]?.dgNumber ?? 0
            guard priority.isFinite, priority.rounded() == priority, abs(priority) <= 100, arguments["priority"] == nil || arguments["priority"]?.dgNumber != nil else { throw DGPluginError(code: "invalid_argument", message: "invalid transform priority") }
            execution.transforms[id] = DGPluginRegisteredTransform(id: id, slot: slot, priority: Int(priority))
            invalidateViewModels(); coordinator.publishAll(); return .string(id)
        case "ui.transform.unregister", "messages.interceptor.unregister":
            guard Set(arguments.keys) == ["id"], let id = arguments["id"]?.dgString else { throw DGPluginError(code: "invalid_argument", message: "expected transform id") }
            execution.transforms.removeValue(forKey: id)
            invalidateViewModels(); coordinator.publishAll(); return .null
        case "ui.transform.result", "messages.interceptor.result":
            guard Set(arguments.keys) == ["requestId", "value"], let id = arguments["requestId"]?.dgString, let pending = execution.pendingTransforms[id], pending.result == nil, execution.transforms[pending.registrationId] != nil, ((method == "messages.interceptor.result" && pending.slot == "outgoing" && account.grants.contains(where: { $0.capability == "messages.intercept" && $0.scope == "activeComposer" })) || (method == "ui.transform.result" && pending.slot != "outgoing" && account.grants.contains(where: { $0.capability == "ui.transform" && $0.scope == pending.slot }))), let patch = arguments["value"] else { throw DGPluginError(code: "stale_handle", message: "transform request is no longer current") }
            pending.result = try pending.slot == "outgoing" ? DGPluginOutgoingMessage.apply(input: pending.input, patch: patch) : DGPluginViewTransform.apply(slot: pending.slot, input: pending.input, patch: patch)
            return .null
        case "events.subscribe":
            guard let name = arguments["name"]?.dgString, ["plugin.activated", "app.foreground", "account.contextChanged", "theme.changed", "locale.changed", "chat.opened", "chat.closed", "message.observed", "composer.changed"].contains(name), execution.subscriptions.count < 16 else { throw DGPluginError(code: "feature_unavailable", message: "event is not available") }
            execution.subscriptions.insert(name); return .null
        case "events.unsubscribe":
            if let name = arguments["name"]?.dgString { execution.subscriptions.remove(name); execution.events.removeAll { $0.0 == name } }; return .null
        case "theme.get": return .object(["appearance": environment["appearance"] ?? .string("light")])
        case "theme.contribute":
            guard Set(arguments.keys) == ["accent"], let accent = arguments["accent"]?.dgString, ["blue", "green", "purple", "orange"].contains(accent) else { throw DGPluginError(code: "invalid_argument", message: "unknown native plugin-page accent") }
            execution.themeTokens = .object(["accent": .string(accent)])
            return execution.themeTokens
        case "theme.clear": execution.themeTokens = .object([:]); return .null
        case "assets.image":
            guard let path = arguments["path"]?.dgString, path.hasPrefix("assets/"), execution.assets.count < 16, let data = try coordinator.package(record).files[path], let raster = DGPluginInstaller.rasterAsset(data), raster.count <= 262144 else { throw DGPluginError(code: "invalid_argument", message: "invalid or excessive installed raster asset") }
            let handle = UUID().uuidString.lowercased()
            execution.assets[handle] = raster
            return .string(handle)
        case "ui.dispose":
            if let id = arguments["id"]?.dgString, execution.contributions.removeValue(forKey: id) != nil {
                execution.pageTokens.removeValue(forKey: id)
                if let cleanup = execution.pageCleanup.removeValue(forKey: id) { DispatchQueue.main.async(execute: cleanup) }
            }
            return .null
        default: return nil
        }
        coordinator.state.installations[index].accounts[accountKey] = account
        coordinator.scheduleSave()
        // Storage is not part of the published snapshot; settings are.
        if method == "settings.set" { coordinator.publishAll() }
        return .null
    }

    /// An estimate of one entry's share of the encoded storage object: its quoted key, colon, comma and value.
    private static func storageEntryBytes(key: String, value: DGPluginJSON) throws -> Int {
        return key.utf8.count + 4 + (try JSONEncoder().encode(value).count)
    }

    private func respond(_ result: Result<DGPluginJSON, DGPluginError>, _ reply: @escaping (String) -> Void) {
        let envelope: DGPluginJSON
        switch result {
        case let .success(value): envelope = .object(["result": value])
        case let .failure(error): envelope = .object(["error": .object(["code": .string(error.code), "message": .string(error.message)])])
        }
        guard let data = try? JSONEncoder().encode(envelope), data.count <= 65536, let value = String(data: data, encoding: .utf8) else { reply("{\"error\":{\"code\":\"quota_exceeded\",\"message\":\"reply exceeds quota\"}}"); return }
        reply(value)
    }

    private func dispatchUICallback(installationId: String, generation: UUID, callbackId: String, value: DGPluginJSON) {
        coordinator.queue.async {
            guard self.current(installationId, generation), let execution = self.executions[installationId], !execution.busy, !execution.contributions.isEmpty, callbackId.utf8.count <= 64 else { return }
            execution.busy = true
            execution.commandEpoch = UUID()
            execution.gestureUntil = ProcessInfo.processInfo.systemUptime + 5
            let payload = DGPluginJSON.object(["id": .string(callbackId), "value": value])
            guard let data = try? JSONEncoder().encode(payload), data.count <= 65536, let json = String(data: data, encoding: .utf8) else { execution.busy = false; execution.gestureUntil = 0; return }
            execution.runtime?.dispatch(kind: "ui", payloadJSON: json) { result in
                self.coordinator.queue.async {
                    guard self.current(installationId, generation) else { return }
                    execution.busy = false; execution.gestureUntil = 0
                    self.refreshDeferredViewModels()
                    self.drainEvents(id: installationId)
                    if case let .failure(error) = result, error.code != "runtime_busy", error.code != "plugin_rejected" { self.fail(id: installationId, message: "plugin interface callback exceeded its budget or stopped") }
                }
            }
        }
    }

    private func pluginError(_ error: Error) -> DGPluginError { return (error as? DGPluginError) ?? DGPluginError(code: "storage_error", message: "plugin operation failed") }
    private func complete<T>(_ completion: @escaping (Result<T, DGPluginError>) -> Void, error: Error) { let value = pluginError(error); DispatchQueue.main.async { completion(.failure(value)) } }
}
