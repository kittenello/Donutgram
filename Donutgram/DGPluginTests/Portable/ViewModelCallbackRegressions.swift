import Foundation
import DGPluginModel
import DGPluginInstaller
import DGPluginHost

private func hostResult<T>(_ operation: (@escaping (Result<T, DGPluginError>) -> Void) -> Void) throws -> T {
    let done = DispatchSemaphore(value: 0)
    var outcome: Result<T, DGPluginError>?
    operation { outcome = $0; done.signal() }
    guard done.wait(timeout: .now() + 8) == .success else { throw DGPluginError(code: "test_timeout", message: "host operation timed out") }
    return try outcome!.get()
}
private func fixture(_ body: String, permissions: [DGPluginPermission]) throws -> DGVerifiedPluginPackage {
    let manifest = DGPluginManifest(id: "dev.example.regression-" + UUID().uuidString.lowercased(), name: "regression", version: "1.0.0", description: "regression", permissions: permissions)
    let json = String(data: try JSONEncoder().encode(manifest), encoding: .utf8)!
    return try DGPluginInstaller.preview(data: Data(("const _plugin = \"donutgram\";\nconst manifest = " + json + ";\nexport default definePlugin(manifest,{async activate(api){" + body + "}});").utf8), fileName: "fixture.donut.js")
}
private func installFixture(_ manager: DGPluginManager, _ package: DGVerifiedPluginPackage) throws -> String {
    let id = try hostResult { manager.install(package, completion: $0) }
    try hostResult { manager.setGrants(id: id, permissions: package.manifest.permissions, completion: $0) }
    try hostResult { manager.setEnabled(id: id, enabled: true, completion: $0) }
    return id
}

func runViewModelCallbackRegressions() throws {
    for mode in ["pending", "deferred", "invalidated"] {
        let manager = DGPluginManager.shared(accountKey: "view-callback-" + mode)
        manager.setAccountActive(true)
        manager.setForegroundActive(true)
        manager.setGloballyEnabled(true)
        let permissions = [DGPluginPermission(capability: "ui.transform", scope: "profile", reason: "test"), DGPluginPermission(capability: "ui.contribute", scope: "settings", reason: "test")]
        let id = try installFixture(manager, fixture("await api.transforms.register({id:'hide',slot:'profile'},async()=>{await api.ui.toast('hold');return {hide:['media']}});await api.commands.register({id:'hold',title:'hold',placement:'settings',run:()=>api.ui.toast('hold')});", permissions: permissions))
        let entered = DispatchSemaphore(value: 0)
        var reply: ((Result<DGPluginJSON, DGPluginError>) -> Void)?
        manager.nativeRequest = { _, _, _, _, completion in reply = completion; entered.signal() }
        let commandDone = DispatchSemaphore(value: 0)
        if mode == "deferred" {
            manager.runCommand(installationId: id, commandId: "hold") { _ in commandDone.signal() }
            XCTAssertTrue(entered.wait(timeout: .now() + 4) == .success)
        }
        let input: DGPluginJSON = .object(["panes": .array([.object(["id": .string("media"), "empty": .bool(true)])])])
        let first = DispatchSemaphore(value: 0)
        let second = DispatchSemaphore(value: 0)
        _ = manager.transformedViewModel(slot: "profile", input: input, update: { first.signal() })
        if mode != "deferred" { XCTAssertTrue(entered.wait(timeout: .now() + 4) == .success) }
        _ = manager.transformedViewModel(slot: "profile", input: input, update: { second.signal() })
        let barrier = DispatchSemaphore(value: 0)
        DGPluginManager.setTestIOFailure(nil) { barrier.signal() }
        XCTAssertTrue(barrier.wait(timeout: .now() + 4) == .success)
        if mode == "invalidated" { try hostResult { manager.setGrants(id: id, permissions: [], completion: $0) } }
        reply?(.success(.null))
        XCTAssertTrue(first.wait(timeout: .now() + 4) == .success, "first consumer " + mode)
        XCTAssertTrue(second.wait(timeout: .now() + 4) == .success, "second consumer " + mode)
        if mode == "pending" { XCTAssertNotEqual(manager.transformedViewModel(slot: "profile", input: input, update: {}), input) }
        if mode == "invalidated" { XCTAssertEqual(manager.transformedViewModel(slot: "profile", input: input, update: {}), input) }
        if mode == "deferred" { XCTAssertTrue(commandDone.wait(timeout: .now() + 4) == .success) }
        try hostResult { manager.remove(id: id, completion: $0) }
        manager.nativeRequest = nil
    }
    print("all consumers notified for pending, deferred and invalidated transforms: passed")
}
