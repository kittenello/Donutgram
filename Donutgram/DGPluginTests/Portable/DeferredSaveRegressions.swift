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

func runDeferredSaveRegressions() throws {
    for mode in ["background", "next-write"] {
        let accountKey = "deferred-save-regression-" + mode
        let manager = DGPluginManager.shared(accountKey: accountKey)
        manager.setAccountActive(true)
        manager.setForegroundActive(true)
        manager.setGloballyEnabled(true)
        let permissions = [DGPluginPermission(capability: "storage.local", scope: "pluginAccount", reason: "test"), DGPluginPermission(capability: "ui.contribute", scope: "settings", reason: "test")]
        let id = try installFixture(manager, fixture("let writes=0;await api.commands.register({id:'write',title:'write',placement:'settings',run:()=>api.storage.set('retry','durable'+(++writes))});", permissions: permissions))
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DG_PLUGIN_TEST_ROOT"]!)
        let state = root.appendingPathComponent("state.json")
        let backup = root.appendingPathComponent("state-save-backup.json")
        try FileManager.default.moveItem(at: state, to: backup)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false)
        try Data("blocked".utf8).write(to: state.appendingPathComponent("blocker"))
        try hostResult { manager.runCommand(installationId: id, commandId: "write", completion: $0) }
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertNotEqual(manager.persistenceError, nil)
        try FileManager.default.removeItem(at: state)
        try FileManager.default.moveItem(at: backup, to: state)
        if mode == "background" { manager.setForegroundActive(false) }
        else {
            try hostResult { manager.runCommand(installationId: id, commandId: "write", completion: $0) }
            Thread.sleep(forTimeInterval: 0.7)
        }
        let barrier = DispatchSemaphore(value: 0)
        DGPluginManager.setTestIOFailure(nil) { barrier.signal() }
        XCTAssertTrue(barrier.wait(timeout: .now() + 4) == .success)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: state)) as! [String: Any]
        let records = saved["installations"] as! [[String: Any]]
        let account = (records.first(where: { $0["id"] as? String == id })!["accounts"] as! [String: [String: Any]])[accountKey]!
        XCTAssertEqual((account["storage"] as? [String: String])?["retry"], mode == "background" ? "durable1" : "durable2")
        XCTAssertNil(manager.persistenceError)
        manager.setForegroundActive(true)
        try hostResult { manager.remove(id: id, completion: $0) }
    }
    print("deferred save retries real atomic write failure on background flush and next plugin write: passed")
}
