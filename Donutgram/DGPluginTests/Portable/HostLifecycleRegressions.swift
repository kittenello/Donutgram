import Foundation
import DGPluginModel
import DGPluginHost
import DGPluginInstaller

func runInterruptedRecoveryChild(mode: String) throws {
    if mode == "marker-write" { try runMarkerWriteFailureTests(child: true); return }
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DG_PLUGIN_TEST_ROOT"]!)
    let manager = DGPluginManager.shared(accountKey: "recovery-account")
    let loaded = DispatchSemaphore(value: 0)
    DGPluginManager.setTestIOFailure(nil) { loaded.signal() }
    guard loaded.wait(timeout: .now() + 15) == .success else { throw DGPluginError(code: "test_timeout", message: "recovery load timed out") }
    let marker = root.appendingPathComponent("running.json")
    let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("state.json"))) as! [String: Any]
    let records = persisted["installations"] as! [[String: Any]]
    let accounts = records[0]["accounts"] as! [String: [String: Any]]
    let account = accounts["recovery-account"]!
    if mode == "fail" {
        XCTAssertFalse(manager.globallyEnabled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(account["enabled"] as? Bool, true)
        XCTAssertEqual(account["failures"] as? Int, 0)
    } else {
        XCTAssertTrue(manager.globallyEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(account["enabled"] as? Bool, false)
        XCTAssertEqual(account["failures"] as? Int, 1)
        XCTAssertTrue((account["lastError"] as? String)?.contains("closed unexpectedly") == true)
        XCTAssertEqual((account["diagnostics"] as? [String])?.count, 1)
        XCTAssertEqual(manager.installations.first?.enabled, false)
    }
    print("interrupted recovery child " + mode + ": passed")
}

func runInterruptedRecoveryTests() throws {
    let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DG_PLUGIN_TEST_ROOT"]!)
    let root = base.appendingPathComponent("interrupted-recovery-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let id = UUID().uuidString
    let manifest = DGPluginManifest(id: "dev.example.interrupted-recovery", name: "recovery", version: "1.0.0", description: "recovery persistence fixture")
    let manifestObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest))
    func state(padding: Int) throws -> Data {
        let account: [String: Any] = ["enabled": true, "grants": [], "settings": ["padding": String(repeating: "x", count: padding)], "storage": [:], "failures": 0]
        let record: [String: Any] = ["id": id, "manifest": manifestObject, "digest": String(repeating: "a", count: 64), "publisherIdentity": "fixture", "trust": "local", "fileName": "fixture.donut.js", "removing": false, "accounts": ["recovery-account": account]]
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "globallyEnabled": true, "installations": [record]])
    }
    let stateURL = root.appendingPathComponent("state.json")
    let padding = 32 * 1024 * 1024 - (try state(padding: 0)).count - 8
    try state(padding: padding).write(to: stateURL)
    try JSONSerialization.data(withJSONObject: [["account": "recovery-account", "installation": id]]).write(to: root.appendingPathComponent("running.json"))
    for mode in ["fail", "retry", "verify"] {
        if mode == "retry" { try state(padding: 0).write(to: stateURL) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [CommandLine.arguments[1]]
        var environment = ProcessInfo.processInfo.environment
        environment["DG_PLUGIN_TEST_ROOT"] = root.path
        environment["DG_PLUGIN_RECOVERY_CHILD"] = mode
        process.environment = environment
        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 45) { if process.isRunning { process.terminate() } }
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "recovery child " + mode)
    }
    print("interrupted recovery preserves markers through failed persistence and retries once: passed")
}

func runMarkerWriteFailureTests(child: Bool = false) throws {
    let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DG_PLUGIN_TEST_ROOT"]!)
    if !child {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [CommandLine.arguments[1]]
        var environment = ProcessInfo.processInfo.environment
        environment["DG_PLUGIN_TEST_ROOT"] = base.appendingPathComponent("marker-write-" + UUID().uuidString).path
        environment["DG_PLUGIN_RECOVERY_CHILD"] = "marker-write"
        process.environment = environment
        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { if process.isRunning { process.terminate() } }
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "marker-write child")
        return
    }
    func result<T>(_ operation: (@escaping (Result<T, DGPluginError>) -> Void) -> Void) throws -> T {
        let completed = DispatchSemaphore(value: 0)
        var outcome: Result<T, DGPluginError>?
        operation { outcome = $0; completed.signal() }
        guard completed.wait(timeout: .now() + 8) == .success else { throw DGPluginError(code: "test_timeout", message: "marker-write operation timed out") }
        return try outcome!.get()
    }
    let manager = DGPluginManager.shared(accountKey: "marker-account")
    manager.setAccountActive(true)
    manager.setForegroundActive(true)
    manager.setGloballyEnabled(true)
    let ui = DGPluginPermission(capability: "ui.contribute", scope: "settings", reason: "activation probe")
    let manifest = DGPluginManifest(id: "dev.example.marker-write", name: "marker write", version: "1.0.0", description: "startup marker fixture", permissions: [ui])
    let manifestJSON = String(data: try JSONEncoder().encode(manifest), encoding: .utf8)!
    let source = "const _plugin = \"donutgram\";\nconst manifest = " + manifestJSON + ";\nexport default definePlugin(manifest,{async activate(api){await api.ui.toast('activated')}});"
    let package = try DGPluginInstaller.preview(data: Data(source.utf8), fileName: "fixture.donut.js")
    let id = try result { manager.install(package, completion: $0) }
    try result { manager.setGrants(id: id, permissions: [ui], completion: $0) }
    let marker = base.appendingPathComponent("running.json")
    var nativeCalls = 0
    manager.nativeRequest = { _, _, _, _, completion in
        nativeCalls += 1
        do {
            let markers = try JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as! [[String: String]]
            XCTAssertEqual(markers, [["account": "marker-account", "installation": id]])
        } catch { XCTFail("runtime executed without a persisted startup marker") }
        completion(.success(.null))
    }
    try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
    XCTAssertThrowsError(try result { manager.setEnabled(id: id, enabled: true, completion: $0) })
    XCTAssertEqual(nativeCalls, 0)
    XCTAssertNil(manager.nativeScope(installationId: id))
    XCTAssertEqual(manager.installations.first(where: { $0.id == id })?.enabled, false)
    try FileManager.default.removeItem(at: marker)
    try result { manager.setEnabled(id: id, enabled: true, completion: $0) }
    XCTAssertEqual(nativeCalls, 1)
    XCTAssertNotEqual(manager.nativeScope(installationId: id), nil)
    let fault = DispatchSemaphore(value: 0)
    DGPluginManager.setTestIOFailure("runningWrite") { fault.signal() }
    XCTAssertTrue(fault.wait(timeout: .now() + 3) == .success)
    try result { manager.setEnabled(id: id, enabled: false, completion: $0) }
    XCTAssertNil(manager.nativeScope(installationId: id))
    XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    try result { manager.setEnabled(id: id, enabled: true, completion: $0) }
    XCTAssertEqual(nativeCalls, 2)
    try result { manager.setEnabled(id: id, enabled: false, completion: $0) }
    XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    try result { manager.remove(id: id, completion: $0) }
    print("startup marker write failure prevents execution; retry and cleanup recover: passed")
}
