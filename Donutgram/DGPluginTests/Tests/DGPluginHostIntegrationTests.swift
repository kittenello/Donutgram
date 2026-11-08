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

    func testOutgoingTextRunsBeforeSendAndCanCancel() throws {
        let permission = DGPluginPermission(capability: "messages.intercept", scope: "activeComposer", reason: "replace a typed command")
        let package = try self.package(permissions: [permission], body: "await api.messages.beforeSend({id:'text-command'},input=>input.text==='.testdonut'?{text:'replacement'}:input.text==='.cancel'?{cancel:true}:{});")
        let id = try self.install(package, permissions: [permission])
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        XCTAssertTrue(self.manager.interceptsOutgoingMessages)
        XCTAssertEqual(try self.result { self.manager.interceptOutgoingText(".testdonut", completion: $0) }.get(), "replacement")
        XCTAssertNil(try self.result { self.manager.interceptOutgoingText(".cancel", completion: $0) }.get())
        XCTAssertEqual(try self.result { self.manager.interceptOutgoingText("ordinary", completion: $0) }.get(), "ordinary")
        try self.result { self.manager.setGrants(id: id, permissions: [], completion: $0) }.get()
        XCTAssertFalse(self.manager.interceptsOutgoingMessages)
        XCTAssertEqual(try self.result { self.manager.interceptOutgoingText(".testdonut", completion: $0) }.get(), ".testdonut")
    }

    func testOutgoingFailureKeepsTheDraftInsteadOfSendingOriginalText() throws {
        let permission = DGPluginPermission(capability: "messages.intercept", scope: "activeComposer", reason: "test a broken interceptor")
        let package = try self.package(permissions: [permission], body: "await api.messages.beforeSend({id:'broken'},()=>{throw Error('stop')});")
        let id = try self.install(package, permissions: [permission])
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        let result = self.result { self.manager.interceptOutgoingText(".private-command", completion: $0) }
        if case .success = result { XCTFail("a broken handler must never send the original command") }
        XCTAssertFalse(self.manager.interceptsOutgoingMessages)
    }

    func testOutgoingPriorityComposesAndCancellationStopsTheChain() throws {
        let permission = DGPluginPermission(capability: "messages.intercept", scope: "activeComposer", reason: "ordered outgoing commands")
        let earlier = try self.package(permissions: [permission], body: "await api.messages.beforeSend({id:'earlier',priority:-10},input=>input.text==='.cancel'?{cancel:true}:{text:'first'});")
        let later = try self.package(permissions: [permission], body: "await api.messages.beforeSend({id:'later',priority:10},input=>{if(input.text!=='first')throw Error('wrong chain order');return {text:'second'}});")
        let laterId = try self.install(later, permissions: [permission])
        let earlierId = try self.install(earlier, permissions: [permission])
        try self.result { self.manager.setEnabled(id: laterId, enabled: true, completion: $0) }.get()
        try self.result { self.manager.setEnabled(id: earlierId, enabled: true, completion: $0) }.get()
        XCTAssertEqual(try self.result { self.manager.interceptOutgoingText("original", completion: $0) }.get(), "second")
        XCTAssertNil(try self.result { self.manager.interceptOutgoingText(".cancel", completion: $0) }.get())
        XCTAssertEqual(self.manager.installations.first(where: { $0.id == laterId })?.state, .running)
    }

    func testDirectMessageMethodsNeedGrantsWithoutRequiringAPerMessageGesture() throws {
        let permissions = [("messages.send", "chosenRecipient"), ("messages.edit", "selectedMessages"), ("messages.delete", "selectedMessages")].map { DGPluginPermission(capability: $0.0, scope: $0.1, reason: "explicit message automation") }
        var calls: [String] = []
        self.manager.nativeRequest = { _, method, _, valid, completion in
            XCTAssertTrue(valid())
            calls.append(method)
            completion(.success(.null))
        }
        let package = try self.package(permissions: permissions, body: "await api.messages.send({text:'direct'});await api.messages.edit({handle:'selected',text:'edited'});await api.messages.delete({handle:'selected'});")
        let id = try self.install(package, permissions: permissions)
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        XCTAssertEqual(calls, ["messages.send", "messages.edit", "messages.delete"])
    }

    func testMessageAutomationCannotBorrowReadOrInteractiveSendGrants() throws {
        var nativeCalls = 0
        self.manager.nativeRequest = { _, _, _, _, completion in nativeCalls += 1; completion(.success(.null)) }
        let permissions = [DGPluginPermission(capability: "messages.read", scope: "selectedChats", reason: "read selected"), DGPluginPermission(capability: "messages.sendInteractive", scope: "chosenRecipient", reason: "review each send")]
        let package = try self.package(permissions: permissions, body: "for(const attempt of [()=>api.messages.send({text:'denied'}),()=>api.messages.edit({text:'denied'}),()=>api.messages.delete(),()=>api.messages.beforeSend({id:'denied'},()=>({}))]){let denied=false;try{await attempt()}catch(e){denied=e.code==='permission_denied'}if(!denied)throw Error('message grant bypass')}")
        let id = try self.install(package, permissions: permissions)
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        XCTAssertEqual(nativeCalls, 0)
        XCTAssertFalse(self.manager.interceptsOutgoingMessages)
    }

    func testOutgoingRevocationRejectsDelayedReplacement() throws {
        let permissions = [DGPluginPermission(capability: "messages.intercept", scope: "activeComposer", reason: "delay replacement"), DGPluginPermission(capability: "ui.contribute", scope: "settings", reason: "delayed native fixture")]
        let package = try self.package(permissions: permissions, body: "await api.messages.beforeSend({id:'delayed'},async()=>{await api.ui.toast('wait');return {text:'late'}});")
        let id = try self.install(package, permissions: permissions)
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        let requested = self.expectation(description: "outgoing handler pending")
        let completed = self.expectation(description: "revoked outgoing handler fails")
        var reply: ((Result<DGPluginJSON, DGPluginError>) -> Void)?
        self.manager.nativeRequest = { _, _, _, _, completion in reply = completion; requested.fulfill() }
        self.manager.interceptOutgoingText("original") { result in
            if case .success = result { XCTFail("revoked outgoing handler must not resume sending") }
            completed.fulfill()
        }
        self.wait(for: [requested], timeout: 2)
        try self.result { self.manager.setGrants(id: id, permissions: [], completion: $0) }.get()
        reply?(.success(.null))
        self.wait(for: [completed], timeout: 4)
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

    func testTwoPluginTransformsComposeByPriorityAndStopClearsCache() throws {
        let permission = DGPluginPermission(capability: "ui.transform", scope: "profile", reason: "hide empty panes")
        let later = try self.package(permissions: [permission], body: "await api.transforms.register({id:'later',slot:'profile',priority:10},input=>{if(input.panes.some(p=>p.id==='media'))throw Error('wrong transform order');return {hide:['files']}});")
        let laterId = try self.install(later, permissions: [permission])
        try self.result { self.manager.setEnabled(id: laterId, enabled: true, completion: $0) }.get()
        let earlier = try self.package(permissions: [permission], body: "await api.transforms.register({id:'earlier',slot:'profile',priority:-10},()=>({hide:['media']}));")
        let earlierId = try self.install(earlier, permissions: [permission])
        try self.result { self.manager.setEnabled(id: earlierId, enabled: true, completion: $0) }.get()
        let input: DGPluginJSON = .object(["panes": .array([
            .object(["id": .string("media"), "empty": .bool(true)]),
            .object(["id": .string("files"), "empty": .bool(true)]),
            .object(["id": .string("voice"), "empty": .bool(false)])
        ])])
        let output: DGPluginJSON = .object(["panes": .array([.object(["id": .string("voice"), "empty": .bool(false)])])])
        let updated = self.expectation(description: "composed transform cached")
        var updates = 0
        XCTAssertEqual(self.manager.transformedViewModel(slot: "profile", input: input, update: { updates += 1; if updates == 1 { updated.fulfill() } }), input)
        self.wait(for: [updated], timeout: 3)
        XCTAssertEqual(self.manager.transformedViewModel(slot: "profile", input: input, update: { XCTFail("cache hit unexpectedly scheduled work") }), output)
        XCTAssertEqual(self.manager.transformedViewModel(slot: "profile", input: input, update: {}), output)
        XCTAssertEqual(updates, 1)
        try self.result { self.manager.setEnabled(id: earlierId, enabled: false, completion: $0) }.get()
        try self.result { self.manager.setEnabled(id: laterId, enabled: false, completion: $0) }.get()
        XCTAssertEqual(self.manager.transformedViewModel(slot: "profile", input: input, update: { XCTFail("stopped transforms changed native input") }), input)
    }

    func testTransformRegistrationCannotWidenExactScope() throws {
        let permission = DGPluginPermission(capability: "ui.transform", scope: "profile", reason: "profile only")
        let package = try self.package(permissions: [permission], body: "let denied=false;try{await api.transforms.register({id:'wrong-slot',slot:'chatList'},()=>({hidden:[]}))}catch(e){denied=e.code==='scope_denied'}if(!denied)throw Error('transform scope widened');")
        let id = try self.install(package, permissions: [permission])
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        let input: DGPluginJSON = .object(["items": .array([])])
        XCTAssertEqual(self.manager.transformedViewModel(slot: "chatList", input: input, update: { XCTFail("ungranted slot produced a patch") }), input)
        XCTAssertEqual(self.manager.installations.first(where: { $0.id == id })?.state, .running)
    }

    func testRevocationRejectsLateTransformPatchAndCache() throws {
        let transform = DGPluginPermission(capability: "ui.transform", scope: "profile", reason: "profile transform")
        let ui = DGPluginPermission(capability: "ui.contribute", scope: "settings", reason: "delayed native response")
        let package = try self.package(permissions: [transform, ui], body: "await api.transforms.register({id:'delayed',slot:'profile'},async()=>{await api.ui.toast('wait');return {hide:['media']}});")
        let id = try self.install(package, permissions: [transform, ui])
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        let requested = self.expectation(description: "transform awaits native callback")
        var reply: ((Result<DGPluginJSON, DGPluginError>) -> Void)?
        var validity: (() -> Bool)?
        self.manager.nativeRequest = { _, method, _, valid, completion in
            guard method == "ui.toast" else { XCTFail("unexpected transform adapter"); completion(.failure(DGPluginError(code: "feature_unavailable", message: "unavailable"))); return }
            reply = completion; validity = valid; requested.fulfill()
        }
        let input: DGPluginJSON = .object(["panes": .array([.object(["id": .string("media"), "empty": .bool(true)])])])
        XCTAssertEqual(self.manager.transformedViewModel(slot: "profile", input: input, update: { XCTFail("revoked transform posted stale output") }), input)
        self.wait(for: [requested], timeout: 2)
        try self.result { self.manager.setGrants(id: id, permissions: [], completion: $0) }.get()
        XCTAssertEqual(validity?(), false)
        reply?(.success(.null))
        try self.result { self.manager.setEnabled(id: id, enabled: false, completion: $0) }.get()
        XCTAssertEqual(self.manager.transformedViewModel(slot: "profile", input: input, update: { XCTFail("stale transform repopulated cache") }), input)
    }

    func testFailedUpdatedActivationRestoresPreviousCodeAndDataDisabled() throws {
        let pluginId = "dev.example.rollback-" + UUID().uuidString.lowercased()
        let storage = DGPluginPermission(capability: "storage.local", scope: "pluginAccount", reason: "persistent state")
        let v1 = try self.package(id: pluginId, permissions: [storage], body: "const value=await api.storage.get('version');if(value===null)await api.storage.set('version','v1');else if(value!=='v1')throw Error('previous data not restored');")
        let id = try self.install(v1, permissions: [storage])
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        let v2 = try self.package(id: pluginId, version: "2.0.0", permissions: [storage], body: "await api.storage.set('version','v2');throw Error('new activation failed');")
        XCTAssertEqual(try self.result { self.manager.install(v2, completion: $0) }.get(), id)
        XCTAssertThrowsError(try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get())
        let restored = try XCTUnwrap(self.manager.installations.first(where: { $0.id == id }))
        XCTAssertEqual(restored.manifest.version, "1.0.0")
        XCTAssertEqual(restored.digest, v1.digest)
        XCTAssertFalse(restored.enabled)
        XCTAssertNil(self.manager.nativeScope(installationId: id))
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        XCTAssertEqual(self.manager.installations.first(where: { $0.id == id })?.state, .running)
    }

    func testRollbackCannotResurrectRevokedGrants() throws {
        let pluginId = "dev.example.revoke-" + UUID().uuidString.lowercased()
        let storage = DGPluginPermission(capability: "storage.local", scope: "pluginAccount", reason: "persistent state")
        let v1 = try self.package(id: pluginId, permissions: [storage], body: "await api.storage.set('private','old');")
        let id = try self.install(v1, permissions: [storage])
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        let v2 = try self.package(id: pluginId, version: "2.0.0", permissions: [storage], body: "")
        _ = try self.result { self.manager.install(v2, completion: $0) }.get()
        try self.result { self.manager.setGrants(id: id, permissions: [], completion: $0) }.get()
        try self.result { self.manager.rollback(id: id, completion: $0) }.get()
        let restored = try XCTUnwrap(self.manager.installations.first(where: { $0.id == id }))
        XCTAssertTrue(restored.grants.isEmpty)
        XCTAssertFalse(restored.enabled)
        XCTAssertThrowsError(try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get())
    }

    func testEqualSemverBuildMetadataCannotReplaceReviewedVersion() throws {
        let pluginId = "dev.example.metadata-" + UUID().uuidString.lowercased()
        let first = try self.package(id: pluginId, version: "1.0.0+first", body: "")
        let id = try self.install(first)
        let equal = try self.package(id: pluginId, version: "1.0.0+second", body: "throw Error('unreviewed');")
        XCTAssertThrowsError(try self.result { self.manager.install(equal, completion: $0) }.get())
        XCTAssertEqual(self.manager.installations.first(where: { $0.id == id })?.digest, first.digest)
        XCTAssertEqual(self.manager.installations.first(where: { $0.id == id })?.manifest.version, "1.0.0+first")
    }

    func testResetDataCannotResurrectPrivateStateThroughRollback() throws {
        let pluginId = "dev.example.reset-" + UUID().uuidString.lowercased()
        let storage = DGPluginPermission(capability: "storage.local", scope: "pluginAccount", reason: "persistent state")
        let first = try self.package(id: pluginId, permissions: [storage], body: "await api.storage.set('private','secret');")
        let id = try self.install(first, permissions: [storage])
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        let update = try self.package(id: pluginId, version: "2.0.0", permissions: [storage], body: "if(await api.storage.get('private')!==null)throw Error('deleted private state resurrected');")
        _ = try self.result { self.manager.install(update, completion: $0) }.get()
        try self.result { self.manager.resetData(id: id, completion: $0) }.get()
        XCTAssertFalse(self.manager.canRollback(id: id))
        XCTAssertThrowsError(try self.result { self.manager.rollback(id: id, completion: $0) }.get())
        try self.result { self.manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
    }

    func testDetachedActivationRepliesCannotBorrowLaterGesture() throws {
        let ui = DGPluginPermission(capability: "ui.contribute", scope: "settings", reason: "activation notice")
        let composer = DGPluginPermission(capability: "composer.read", scope: "activeComposer", reason: "gesture-bound draft")
        let package = try self.package(permissions: [ui, composer], body: "api.ui.toast('hold').then(async()=>{let denied=false;try{await api.composer.getActiveDraft()}catch(e){denied=e.code==='permission_denied'}if(!denied)throw Error('detached activation borrowed a gesture')});")
        let id = try self.install(package, permissions: [ui, composer])
        let requested = self.expectation(description: "detached activation native wait")
        let activated = self.expectation(description: "activation drains detached native replies")
        var delayed: ((Result<DGPluginJSON, DGPluginError>) -> Void)?
        var composerCalls = 0
        self.manager.nativeRequest = { _, method, _, _, completion in
            if method == "ui.toast" { delayed = completion; requested.fulfill() }
            else { composerCalls += 1; completion(.success(.null)) }
        }
        self.manager.setEnabled(id: id, enabled: true) { result in
            if case let .failure(error) = result { XCTFail("activation failed: " + error.code) }
            activated.fulfill()
        }
        self.wait(for: [requested], timeout: 2)
        XCTAssertEqual(self.manager.installations.first(where: { $0.id == id })?.state, .starting)
        delayed?(.success(.null))
        self.wait(for: [activated], timeout: 3)
        XCTAssertEqual(composerCalls, 0)
        XCTAssertEqual(self.manager.installations.first(where: { $0.id == id })?.state, .running)
    }

    func testEventsRequireTheirOwnExactGrantAndNeverCreateGesture() throws {
        let storage = DGPluginPermission(capability: "storage.local", scope: "pluginAccount", reason: "event counters")
        let ui = DGPluginPermission(capability: "ui.contribute", scope: "settings", reason: "event check command")
        let theme = DGPluginPermission(capability: "theme.read", scope: "currentTheme", reason: "theme event")
        let composer = DGPluginPermission(capability: "composer.read", scope: "activeComposer", reason: "gesture-bound draft")
        let delivered = self.expectation(description: "granted event delivered")
        let gestureDenied = self.expectation(description: "event cannot create native gesture")
        var composerCalls = 0
        self.manager.nativeRequest = { _, method, params, _, completion in
            if method == "composer.getActiveDraft" { composerCalls += 1 }
            if params.objectValue?["text"] == .string("theme delivered") { delivered.fulfill() }
            if params.objectValue?["text"] == .string("gesture denied") { gestureDenied.fulfill() }
            completion(.success(.null))
        }
        let granted = try self.package(permissions: [storage, ui, theme, composer], body: "await api.events.on('theme.changed',async event=>{if(event.version!==1||typeof event.id!=='string'||event.data.appearance!=='dark')throw Error('invalid event envelope');await api.storage.set('theme',true);await api.ui.toast('theme delivered')});await api.events.on('locale.changed',async()=>{let denied=false;try{await api.composer.getActiveDraft()}catch(e){denied=e.code==='permission_denied'}if(!denied)throw Error('event acquired gesture');await api.ui.toast('gesture denied')});")
        let grantedId = try self.install(granted, permissions: [storage, ui, theme, composer])
        try self.result { self.manager.setEnabled(id: grantedId, enabled: true, completion: $0) }.get()
        let denied = try self.package(permissions: [storage, ui], body: "await api.events.on('theme.changed',async()=>{await api.storage.set('leak',true)});await api.commands.register({id:'assert',title:'assert',placement:'settings',async run(){if(await api.storage.get('leak')!==null)throw Error('theme event delivered without grant')}});")
        let deniedId = try self.install(denied, permissions: [storage, ui])
        try self.result { self.manager.setEnabled(id: deniedId, enabled: true, completion: $0) }.get()
        self.manager.emitNativeEvent(name: "theme.changed", payload: .object(["appearance": .string("dark")]))
        self.wait(for: [delivered], timeout: 3)
        self.manager.emitNativeEvent(name: "locale.changed", payload: .object(["locale": .string("ru")]), installationId: grantedId)
        self.wait(for: [gestureDenied], timeout: 3)
        try self.result { self.manager.runCommand(installationId: deniedId, commandId: "assert", completion: $0) }.get()
        XCTAssertEqual(composerCalls, 0)
    }
}
