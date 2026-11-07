import Foundation
import DGPluginModel
import DGPluginInstaller
import DGPluginRuntime

private struct DGPluginAccountRecord: Codable {
    var enabled = false
    var grants: [DGPluginPermission] = []
    var settings: [String: DGPluginJSON] = [:]
    var storage: [String: DGPluginJSON] = [:]
    var failures = 0
    var lastError: String?
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
}

private struct DGPluginDeviceState: Codable {
    var schemaVersion = 1
    var globallyEnabled = true
    var installations: [DGPluginStoredRecord] = []
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
}

private final class DGPluginCoordinator {
    static let shared = DGPluginCoordinator()
    let queue = DispatchQueue(label: "donutgram.plugins.host")
    let root: URL
    var state = DGPluginDeviceState()
    var packages: [String: DGVerifiedPluginPackage] = [:]
    var activeAccountKey: String?
    var foreground = true
    var powerSaving = false
    var startupError: DGPluginError?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        self.root = support.appendingPathComponent("DonutgramPlugins", isDirectory: true)
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
                for record in state.installations where record.removing {
                    try cleanupFiles(record)
                }
                state.installations.removeAll(where: { $0.removing })
                try persist()
            }
        } catch {
            startupError = DGPluginError(code: "storage_error", message: "plugin state requires recovery; execution is stopped")
            state.globallyEnabled = false
        }
    }

    func persist() throws {
        guard startupError == nil else { throw startupError! }
        let data = try JSONEncoder().encode(state)
        guard data.count <= 32 * 1024 * 1024 else { throw DGPluginError(code: "quota_exceeded", message: "plugin state exceeds its limit") }
        try data.write(to: root.appendingPathComponent("state.json"), options: .atomic)
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
        let directory = root.appendingPathComponent(record.id, isDirectory: true).standardizedFileURL
        guard UUID(uuidString: record.id) != nil, directory.deletingLastPathComponent() == root.standardizedFileURL else {
            throw DGPluginError(code: "invalid_argument", message: "invalid package removal path")
        }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        packages.removeValue(forKey: record.digest)
    }

    func publishAll() {
        for manager in DGPluginManager.allManagers() { manager.publish() }
    }

    func stopAll(id: String? = nil) {
        for manager in DGPluginManager.allManagers() {
            if let id = id { manager.stop(id: id) } else { manager.stopAll() }
        }
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
    private var observers: [UUID: () -> Void] = [:]
    private var executions: [String: DGPluginExecution] = [:]
    private var adapter: ((String, String, DGPluginJSON, @escaping () -> Bool, @escaping (Result<DGPluginJSON, DGPluginError>) -> Void) -> Void)?
    private var renderAdapter: ((DGPluginJSON, String, @escaping () -> Bool, @escaping (String, DGPluginJSON) -> Void) -> Result<() -> Void, DGPluginError>)?
    private var environment: [String: DGPluginJSON] = ["clientVersion": .string("13.2"), "locale": .string("en"), "appearance": .string("light"), "lowPowerMode": .bool(false)]

    public var nativeRequest: ((String, String, DGPluginJSON, @escaping () -> Bool, @escaping (Result<DGPluginJSON, DGPluginError>) -> Void) -> Void)? {
        get { snapshotLock.lock(); defer { snapshotLock.unlock() }; return adapter }
        set { snapshotLock.lock(); adapter = newValue; snapshotLock.unlock() }
    }

    public var nativeRender: ((DGPluginJSON, String, @escaping () -> Bool, @escaping (String, DGPluginJSON) -> Void) -> Result<() -> Void, DGPluginError>)? {
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
            if !active { self.coordinator.stopAll() } else { for manager in Self.allManagers() { manager.reconcile() } }
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
            self.environment["locale"] = .string(String(locale.prefix(64)))
            self.environment["appearance"] = .string(appearance == "dark" ? "dark" : "light")
        }
    }

    public var installations: [DGPluginInstallation] { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotInstallations }
    public var commands: [DGPluginCommandDescriptor] { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotCommands }
    public var globallyEnabled: Bool { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotEnabled }
    public func iconData(id: String) -> Data? { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotIcons[id] }

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
            return DGPluginInstallation(id: record.id, manifest: record.manifest, digest: record.digest, trust: record.trust, enabled: account.enabled, state: state, grants: account.grants, settings: account.settings, lastError: account.lastError ?? coordinator.startupError?.message)
        }
        let commands = executions.values.filter { $0.state == .running }.flatMap { $0.commands }.sorted { ($0.installationId, $0.id) < ($1.installationId, $1.id) }
        snapshotLock.lock()
        snapshotInstallations = values; snapshotCommands = commands; snapshotIcons = icons; snapshotEnabled = coordinator.state.globallyEnabled
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
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try package.originalData.write(to: destination, options: .atomic)
                self.coordinator.state.installations.removeAll { $0.id == record.id }
                self.coordinator.state.installations.append(record)
                do { try self.coordinator.persist() } catch { self.coordinator.state = previousState; throw error }
                self.coordinator.packages[package.digest] = package
                self.coordinator.publishAll()
                let installationId = record.id
                DispatchQueue.main.async { completion(.success(installationId)) }
            } catch { self.complete(completion, error: error) }
        }
    }

    private func version(_ value: String, isNewerThan previous: String) -> Bool {
        let left = value.split(separator: ".").prefix(3).map { Int($0.split(separator: "-")[0]) ?? -1 }
        let right = previous.split(separator: ".").prefix(3).map { Int($0.split(separator: "-")[0]) ?? -1 }
        if left != right { return right.lexicographicallyPrecedes(left) }
        return previous.contains("-") && !value.contains("-")
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
            do { try self.coordinator.persist() } catch { self.coordinator.state.globallyEnabled = previous; return }
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
        mutate(id: id, completion: completion) { record, account in
            account.storage = [:]; account.settings = DGPluginPolicy.settingsDefaults(record.manifest); account.enabled = false
        }
    }

    private func mutate(id: String, stop: Bool = true, completion: @escaping (Result<Void, DGPluginError>) -> Void, action: @escaping (DGPluginStoredRecord, inout DGPluginAccountRecord) throws -> Void) {
        coordinator.queue.async {
            do {
                guard let index = self.coordinator.state.installations.firstIndex(where: { $0.id == id && !$0.removing }) else { throw DGPluginError(code: "stale_handle", message: "installation is unavailable") }
                let record = self.coordinator.state.installations[index]
                var account = self.account(record)
                try action(record, &account)
                if stop { self.stop(id: id) }
                self.coordinator.state.installations[index].accounts[self.accountKey] = account
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
        execution.state = .stopping
        execution.commands.removeAll(); execution.contributions.removeAll(); execution.subscriptions.removeAll()
        execution.runtime?.stop()
        let cleanup = execution.cleanup
        execution.cleanup = []
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
        guard Self.executionAvailable, coordinator.startupError == nil, coordinator.state.globallyEnabled, coordinator.foreground, !coordinator.powerSaving, coordinator.activeAccountKey == accountKey, executions[id]?.generation == generation, let record = coordinator.state.installations.first(where: { $0.id == id && !$0.removing }), account(record).enabled else { return false }
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
        stop(id: id)
        if let index = coordinator.state.installations.firstIndex(where: { $0.id == id }) {
            var account = self.account(coordinator.state.installations[index])
            account.failures += 1; account.lastError = message; account.enabled = false
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
                        switch result {
                        case .success: DispatchQueue.main.async { completion(.success(())) }
                        case .failure: self.fail(id: installationId, message: "plugin command failed or exceeded its budget"); self.complete(completion, error: DGPluginError(code: "runtime_error", message: "command failed"))
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
            if now - execution.windowStart >= 60 { execution.windowStart = now; execution.requests = 0 }
            execution.requests += 1
            guard execution.requests <= 600 else { throw DGPluginError(code: "quota_exceeded", message: "plugin request budget exceeded") }
            let record = coordinator.state.installations[index]
            let account = self.account(record)
            try authorize(rule, record: record, account: account, execution: execution)
            guard rule.available else { throw DGPluginError(code: "feature_unavailable", message: "this adapter is not available in this client") }
            if let result = try local(method: method, params: params, index: index, execution: execution) { respond(.success(result), reply); return }
            let epoch = execution.commandEpoch
            let validity = { [weak self] () -> Bool in
                guard let self = self else { return false }
                return self.coordinator.queue.sync { self.current(installationId, generation) && (!rule.requiresGesture || (self.executions[installationId]?.commandEpoch == epoch && ProcessInfo.processInfo.systemUptime <= (self.executions[installationId]?.gestureUntil ?? 0))) }
            }
            if method == "ui.render" {
                guard let renderer = nativeRender, execution.contributions.isEmpty, case let .object(page) = params, let pageId = page["id"]?.dgString, !pageId.isEmpty, pageId.utf8.count <= 64 else { throw DGPluginError(code: "feature_unavailable", message: "one plugin page may be open at a time") }
                execution.contributions[pageId] = .null
                let pluginName = record.manifest.name
                DispatchQueue.main.async {
                    guard validity() else { self.respond(.failure(DGPluginError(code: "cancelled", message: "page cancelled")), reply); return }
                    let result = renderer(params, pluginName, validity, { [weak self] callbackId, value in
                        self?.dispatchUICallback(installationId: installationId, generation: generation, callbackId: callbackId, value: value)
                    })
                    self.coordinator.queue.async {
                        switch result {
                        case let .success(cleanup):
                            guard self.current(installationId, generation) else { DispatchQueue.main.async(execute: cleanup); self.respond(.failure(DGPluginError(code: "cancelled", message: "plugin stopped")), reply); return }
                            execution.cleanup.append(cleanup)
                            execution.contributions[pageId] = .null
                            self.respond(.success(.string(pageId)), reply)
                        case let .failure(error): execution.contributions.removeValue(forKey: pageId); self.respond(.failure(error), reply)
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
                            try self.authorize(rule, record: currentRecord, account: self.account(currentRecord), execution: execution)
                            self.respond(result, reply)
                        } catch { self.respond(.failure(self.pluginError(error)), reply) }
                    }
                }
            }
        } catch { respond(.failure(pluginError(error)), reply) }
    }

    private func authorize(_ rule: DGPluginMethodRule, record: DGPluginStoredRecord, account: DGPluginAccountRecord, execution: DGPluginExecution) throws {
        try DGPluginPolicy.validateProfile(record.manifest)
        if let capability = rule.capability {
            let declared = Set((record.manifest.permissions + record.manifest.optionalPermissions).map(DGPluginPolicy.permissionKey))
            guard account.grants.contains(where: { $0.capability == capability && (rule.scope == nil || $0.scope == rule.scope!) && declared.contains(DGPluginPolicy.permissionKey($0)) }) else {
                throw DGPluginError(code: "permission_denied", message: "required capability or scope was not granted")
            }
        }
        if rule.requiresGesture && ProcessInfo.processInfo.systemUptime > execution.gestureUntil { throw DGPluginError(code: "permission_denied", message: "this operation requires a current native user action") }
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
            return .bool(account.grants.contains { $0.capability == name } && DGPluginPolicy.methods.values.contains { $0.capability == name && $0.available })
        case "capabilities.list":
            return .object(Dictionary(uniqueKeysWithValues: DGPluginPolicy.methods.map { name, rule in
                (name, .bool(rule.available && (rule.capability == nil || account.grants.contains { $0.capability == rule.capability })))
            }))
        case "storage.keys": return .array(account.storage.keys.sorted().map(DGPluginJSON.string))
        case "storage.get", "storage.set", "storage.remove":
            guard let key = arguments["key"]?.dgString, !key.isEmpty, key.utf8.count <= 128, !["__proto__", "prototype", "constructor"].contains(key) else { throw DGPluginError(code: "invalid_argument", message: "invalid storage key") }
            if method == "storage.get" { return account.storage[key] ?? .null }
            if method == "storage.remove" { account.storage.removeValue(forKey: key) }
            else {
                guard let value = arguments["value"], try JSONEncoder().encode(value).count <= 262144, account.storage.count < 1024 || account.storage[key] != nil else { throw DGPluginError(code: "quota_exceeded", message: "storage item exceeds its quota") }
                try value.validateLimits()
                account.storage[key] = value
            }
            guard try JSONEncoder().encode(account.storage).count <= 5 * 1024 * 1024 else { throw DGPluginError(code: "quota_exceeded", message: "plugin storage quota exceeded") }
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
        case "events.subscribe":
            guard let name = arguments["name"]?.dgString, ["plugin.activated", "plugin.deactivating", "app.foreground", "app.background", "theme.changed", "locale.changed", "powerSaving.changed"].contains(name), execution.subscriptions.count < 16 else { throw DGPluginError(code: "feature_unavailable", message: "event is not available") }
            execution.subscriptions.insert(name); return .null
        case "events.unsubscribe":
            if let name = arguments["name"]?.dgString { execution.subscriptions.remove(name) }; return .null
        case "theme.get": return .object(["appearance": environment["appearance"] ?? .string("light")])
        case "ui.dispose":
            if let id = arguments["id"]?.dgString, execution.contributions.removeValue(forKey: id) != nil {
                let cleanup = execution.cleanup; execution.cleanup = []; DispatchQueue.main.async { cleanup.forEach { $0() } }
            }
            return .null
        default: return nil
        }
        coordinator.state.installations[index].accounts[accountKey] = account
        do { try coordinator.persist() } catch { coordinator.state.installations[index] = record; throw error }
        coordinator.publishAll()
        return .null
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
                    if case .failure = result { self.fail(id: installationId, message: "plugin interface callback failed") }
                }
            }
        }
    }

    private func pluginError(_ error: Error) -> DGPluginError { return (error as? DGPluginError) ?? DGPluginError(code: "storage_error", message: "plugin operation failed") }
    private func complete<T>(_ completion: @escaping (Result<T, DGPluginError>) -> Void, error: Error) { let value = pluginError(error); DispatchQueue.main.async { completion(.failure(value)) } }
}
