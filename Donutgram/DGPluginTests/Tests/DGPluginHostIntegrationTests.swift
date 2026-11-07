import Foundation
import XCTest
import DGPluginModel
import DGPluginInstaller
import DGPluginHost

final class DGPluginHostIntegrationTests: XCTestCase {
    private var manager: DGPluginManager!
    private var installedIds: [String] = []

    override func setUpWithError() throws {
        try XCTSkipIf(!DGPluginManager.executionAvailable, "this distribution compiles external plugin execution out")
        self.manager = DGPluginManager.shared(accountKey: "plugin-test-" + UUID().uuidString)
        self.manager.setAccountActive(true)
        self.manager.setGloballyEnabled(true)
    }

    override func tearDownWithError() throws {
        if let manager = self.manager {
            for id in self.installedIds {
                _ = self.result { manager.remove(id: id, completion: $0) }
            }
            manager.nativeRequest = nil
            manager.setAccountActive(false)
        }
    }

    private func result<T>(_ operation: (@escaping (Result<T, DGPluginError>) -> Void) -> Void) -> Result<T, DGPluginError> {
        let expectation = self.expectation(description: "host operation")
        var result: Result<T, DGPluginError>?
        operation { result = $0; expectation.fulfill() }
        self.wait(for: [expectation], timeout: 5)
        return result ?? .failure(DGPluginError(code: "test_timeout", message: "host operation did not complete"))
    }

    private func package(id: String = "dev.example.test-" + UUID().uuidString.lowercased(), version: String = "1.0.0", profile: String = "localPrivate", permissions: [DGPluginPermission] = [], body: String) throws -> DGVerifiedPluginPackage {
        let manifest = DGPluginManifest(id: id, name: "host test", version: version, description: "host integration fixture", permissions: permissions, profile: profile)
        let json = String(data: try JSONEncoder().encode(manifest), encoding: .utf8)!
        let source = "const _plugin = \"donutgram\";\nconst manifest = " + json + ";\nexport default definePlugin(manifest,{async activate(api){" + body + "}});"
        return try DGPluginInstaller.preview(data: Data(source.utf8), fileName: "fixture.donut.js")
    }

    private func install(_ package: DGVerifiedPluginPackage, permissions: [DGPluginPermission] = []) throws -> String {
        let id = try self.result { self.manager.install(package, completion: $0) }.get()
        self.installedIds.append(id)
        if !permissions.isEmpty { try self.result { self.manager.setGrants(id: id, permissions: permissions, completion: $0) }.get() }
        return id
    }

    func testUndeclaredStorageCallRejectedByRealBroker() throws {
        var nativeCalls = 0
        self.manager.nativeRequest = { _, _, _, _, completion in nativeCalls += 1; completion(.success(.null)) }
        let package = try self.package(body: "let denied=false;try{await api.storage.set('x','private')}catch(e){denied=e.code==='permission_denied'}if(!denied)throw Error('storage bypass');")
        let id = try self.install(package)
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        XCTAssertEqual(nativeCalls, 0)
        XCTAssertEqual(self.manager.installations.first(where: { $0.id == id })?.state, .running)
    }

    func testForgedMethodAndIdentityFieldsDoNotExposeForbiddenEffects() throws {
        var nativeCalls = 0
        self.manager.nativeRequest = { _, _, _, _, completion in nativeCalls += 1; completion(.success(.null)) }
        let package = try self.package(body: "const encode=JSON.stringify;JSON.stringify=(value)=>encode(value&&value.method?{...value,method:'account.logout',pluginId:'other',accountId:'other',permissions:['all']}:value);let denied=false;try{await api.storage.set('x',1)}catch(e){denied=e.code==='feature_unavailable'}if(!denied)throw Error('forged request accepted');")
        let id = try self.install(package)
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        XCTAssertEqual(nativeCalls, 0)
    }

    func testCommandPlacementCannotWidenGrantedSlot() throws {
        let permission = DGPluginPermission(capability: "ui.contribute", scope: "settings", reason: "settings command")
        let package = try self.package(permissions: [permission], body: "let denied=false;try{await api.commands.register({id:'escape',title:'escape',placement:'composer',run(){}})}catch(e){denied=e.code==='scope_denied'}if(!denied)throw Error('slot widened');")
        let id = try self.install(package, permissions: [permission])
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        XCTAssertTrue(self.manager.commands.filter { $0.installationId == id }.isEmpty)
    }

    func testInstallationsCannotReadEachOthersStorage() throws {
        let permission = DGPluginPermission(capability: "storage.local", scope: "pluginAccount", reason: "private state")
        let first = try self.package(permissions: [permission], body: "await api.storage.set('secret','installation-a');")
        let firstId = try self.install(first, permissions: [permission])
        try self.result { self.manager.setEnabled(id: firstId, enabled: true, completion: $0) }.get()
        let second = try self.package(permissions: [permission], body: "if(await api.storage.get('secret')!==null)throw Error('cross-plugin storage');")
        let secondId = try self.install(second, permissions: [permission])
        try self.result { self.manager.setEnabled(id: secondId, enabled: true, completion: $0) }.get()
    }

    func testDeepStorageCannotPoisonPersistedDeviceState() throws {
        let permission = DGPluginPermission(capability: "storage.local", scope: "pluginAccount", reason: "bounded state")
        let package = try self.package(permissions: [permission], body: "let value=null;for(let n=0;n<30;n++)value=[value];let denied=false;try{await api.storage.set('deep',value)}catch(e){denied=e.code==='quota_exceeded'}if(!denied)throw Error('unbounded storage accepted');if(await api.storage.get('deep')!==null)throw Error('rejected storage persisted');")
        let id = try self.install(package, permissions: [permission])
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
    }

    func testUndeclaredGrantsAndUnknownSettingsRejected() throws {
        let package = try self.package(body: "")
        let id = try self.install(package)
        let permission = DGPluginPermission(capability: "composer.read", scope: "activeComposer", reason: "not declared")
        XCTAssertThrowsError(try self.result { self.manager.setGrants(id: id, permissions: [permission], completion: $0) }.get())
        XCTAssertThrowsError(try self.result { self.manager.updateSettings(id: id, values: ["security": .bool(false)], completion: $0) }.get())
    }

    func testProfileChangingUpdateCannotReadHistoricalPrivateStorage() throws {
        let pluginId = "dev.example.update-" + UUID().uuidString.lowercased()
        let storage = DGPluginPermission(capability: "storage.local", scope: "pluginAccount", reason: "private state")
        let first = try self.package(id: pluginId, permissions: [storage], body: "await api.storage.set('secret','private text');")
        let id = try self.install(first, permissions: [storage])
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        let network = DGPluginPermission(capability: "network.public", scope: "declaredOrigins", reason: "public request", origins: ["https://example.org"])
        let update = try self.package(id: pluginId, version: "2.0.0", profile: "publicNetwork", permissions: [storage, network], body: "")
        XCTAssertThrowsError(try self.result { self.manager.install(update, completion: $0) }.get())
        XCTAssertEqual(self.manager.installations.first(where: { $0.id == id })?.manifest.profile, "localPrivate")
    }

    func testDisableInvalidatesPendingNativeRead() throws {
        let ui = DGPluginPermission(capability: "ui.contribute", scope: "settings", reason: "test command")
        let composer = DGPluginPermission(capability: "composer.read", scope: "activeComposer", reason: "read current draft")
        let package = try self.package(permissions: [ui, composer], body: "await api.commands.register({id:'read',title:'read',placement:'settings',async run(){await api.composer.getActiveDraft();await api.ui.toast('late callback');}});")
        let id = try self.install(package, permissions: [ui, composer])
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        let requested = self.expectation(description: "native read requested")
        var lateReply: ((Result<DGPluginJSON, DGPluginError>) -> Void)?
        var validity: (() -> Bool)?
        var toasts = 0
        self.manager.nativeRequest = { _, method, _, valid, completion in
            if method == "composer.getActiveDraft" { lateReply = completion; validity = valid; requested.fulfill() }
            else { toasts += 1; completion(.success(.null)) }
        }
        let commandDone = self.expectation(description: "cancelled command")
        self.manager.runCommand(installationId: id, commandId: "read") { outcome in
            if case .success = outcome { XCTFail("disabled command reported success") }
            commandDone.fulfill()
        }
        self.wait(for: [requested], timeout: 2)
        try self.result { self.manager.setEnabled(id: id, enabled: false, completion: $0) }.get()
        XCTAssertEqual(validity?(), false)
        lateReply?(.success(.string("private draft")))
        self.wait(for: [commandDone], timeout: 2)
        XCTAssertEqual(toasts, 0)
        XCTAssertTrue(self.manager.commands.filter { $0.installationId == id }.isEmpty)
    }
}
