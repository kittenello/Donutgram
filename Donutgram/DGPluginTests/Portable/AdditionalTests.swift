import Foundation
import DGPluginModel
import DGPluginInstaller
import DGPluginHost

func runNativeActionTests() throws {
    let store = DGPluginNativeActionStore()
    let handle = try store.prepare(scope: "installation-a/account-a", recipient: "recipient-a", text: "ordinary text", now: 100)
    XCTAssertEqual(try store.preview(handle: handle, scope: "installation-a/account-a", recipient: "recipient-a", now: 101), "ordinary text")
    XCTAssertThrowsError(try store.consume(handle: handle, scope: "installation-b/account-a", recipient: "recipient-a", paidRecipient: false, now: 101))
    XCTAssertThrowsError(try store.consume(handle: handle, scope: "installation-a/account-a", recipient: "recipient-b", paidRecipient: false, now: 101))
    XCTAssertEqual(try store.consume(handle: handle, scope: "installation-a/account-a", recipient: "recipient-a", paidRecipient: false, now: 102), "ordinary text")
    XCTAssertThrowsError(try store.consume(handle: handle, scope: "installation-a/account-a", recipient: "recipient-a", paidRecipient: false, now: 102))
    let paid = try store.prepare(scope: "installation-a/account-a", recipient: "recipient-a", text: "no spending", now: 100)
    XCTAssertThrowsError(try store.consume(handle: paid, scope: "installation-a/account-a", recipient: "recipient-a", paidRecipient: true, now: 101))
    XCTAssertThrowsError(try store.consume(handle: paid, scope: "installation-a/account-a", recipient: "recipient-a", paidRecipient: false, now: 101))
    let expired = try store.prepare(scope: "installation-a/account-a", recipient: "recipient-a", text: "expire", now: 100)
    XCTAssertThrowsError(try store.preview(handle: expired, scope: "installation-a/account-a", recipient: "recipient-a", now: 146))
    XCTAssertThrowsError(try store.consume(handle: expired, scope: "installation-a/account-a", recipient: "recipient-a", paidRecipient: false, now: 146))
    let cancelled = try store.prepare(scope: "installation-a/account-a", recipient: "recipient-a", text: "cancel", now: 200)
    store.cancel(handle: cancelled)
    XCTAssertThrowsError(try store.preview(handle: cancelled, scope: "installation-a/account-a", recipient: "recipient-a", now: 201))
    let removed = try store.prepare(scope: "installation-a/account-a", recipient: "recipient-a", text: "stop", now: 200)
    store.removeAll()
    XCTAssertThrowsError(try store.preview(handle: removed, scope: "installation-a/account-a", recipient: "recipient-a", now: 201))
    let scoped = try store.prepare(scope: "scope-a", recipient: "recipient-a", text: "remove only a", now: 300)
    let other = try store.prepare(scope: "scope-b", recipient: "recipient-a", text: "keep b", now: 300)
    store.removeAll(scope: "scope-a")
    XCTAssertThrowsError(try store.preview(handle: scoped, scope: "scope-a", recipient: "recipient-a", now: 301))
    XCTAssertEqual(try store.preview(handle: other, scope: "scope-b", recipient: "recipient-a", now: 301), "keep b")
    print("native confirmation tests: passed")
}

func runSemanticVersionTests() throws {
    let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "2.0.0", "99999999999999999999999999.0.0"]
    for pair in zip(ordered, ordered.dropFirst()) { XCTAssertTrue(try XCTUnwrap(DGPluginSemanticVersion(pair.0)) < XCTUnwrap(DGPluginSemanticVersion(pair.1))) }
    XCTAssertEqual(DGPluginSemanticVersion("1.2.3+build.1"), DGPluginSemanticVersion("1.2.3+other.2"))
    for value in ["1.0", "01.0.0", "1.0.0-01", "1.0.0-", "1.0.0+", "1.0.0-alpha..1"] { XCTAssertNil(DGPluginSemanticVersion(value)) }
    print("semantic version tests: passed")
}

func runGeneratedArchiveTests(directory: URL) throws {
    let valid = try Data(contentsOf: directory.appendingPathComponent("valid.deflate.dgplugin"))
    let package = try DGPluginInstaller.preview(data: valid, fileName: "fixture.dgplugin")
    XCTAssertEqual(package.manifest.id, "dev.donutgram.fixture-archive")
    for name in ["traversal.dgplugin", "case-collision.dgplugin", "expanded-limit.dgplugin", "file-count.dgplugin", "nested.dgplugin", "symlink.dgplugin", "mismatched-local-crc.dgplugin"] {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        XCTAssertThrowsError(try DGPluginInstaller.preview(data: data, fileName: name), name)
    }
    print("production deflate and hostile archive fixtures: 8 passed")
}

private func portableResult<T>(_ operation: (@escaping (Result<T, DGPluginError>) -> Void) -> Void) -> Result<T, DGPluginError> {
    let test = XCTestCase()
    let completed = test.expectation(description: "portable production operation")
    var result: Result<T, DGPluginError>?
    operation { result = $0; completed.fulfill() }
    test.wait(for: [completed], timeout: 8)
    return result ?? .failure(DGPluginError(code: "test_timeout", message: "operation did not complete"))
}

private func portableFault(_ operation: String?) {
    let test = XCTestCase()
    let configured = test.expectation(description: "one-shot storage fault configured")
    DGPluginManager.setTestIOFailure(operation) { configured.fulfill() }
    test.wait(for: [configured], timeout: 3)
}

private func portablePackage(id: String, version: String = "1.0.0", body: String = "") throws -> DGVerifiedPluginPackage {
    let manifest = DGPluginManifest(id: id, name: "portable persistence fixture", version: version, description: "isolated production lifecycle fixture")
    let json = String(data: try JSONEncoder().encode(manifest), encoding: .utf8)!
    let source = "const _plugin = \"donutgram\";\nconst manifest = " + json + ";\nexport default definePlugin(manifest,{activate(){" + body + "}});"
    return try DGPluginInstaller.preview(data: Data(source.utf8), fileName: "fixture.donut.js")
}

func runPersistenceFaultTests() throws {
    let manager = DGPluginManager.shared(accountKey: "fault-tests-" + UUID().uuidString)
    manager.setAccountActive(true)
    manager.setGloballyEnabled(true)
    let first = try portablePackage(id: "dev.example.fault-" + UUID().uuidString.lowercased())
    let id = try portableResult { manager.install(first, completion: $0) }.get()
    defer { portableFault(nil); _ = portableResult { manager.remove(id: id, completion: $0) }; manager.setAccountActive(false) }
    try portableResult { manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
    let initialScope = try XCTUnwrap(manager.nativeScope(installationId: id))
    let test = XCTestCase()
    let cleaned = test.expectation(description: "native resource cancelled despite persist error")
    XCTAssertNotEqual(manager.ownNativeResource(installationId: id, scope: initialScope, cleanup: { cleaned.fulfill() }), nil)
    portableFault("persist")
    let disabled = portableResult { manager.setEnabled(id: id, enabled: false, completion: $0) }
    XCTAssertThrowsError(try disabled.get())
    XCTAssertNil(manager.nativeScope(installationId: id))
    test.wait(for: [cleaned], timeout: 2)
    try portableResult { manager.setEnabled(id: id, enabled: false, completion: $0) }.get()
    try portableResult { manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
    let update = try portablePackage(id: first.manifest.id, version: "2.0.0", body: "throw Error('must not activate');")
    portableFault("packageWrite")
    XCTAssertThrowsError(try portableResult { manager.install(update, completion: $0) }.get())
    XCTAssertEqual(manager.installations.first(where: { $0.id == id })?.digest, first.digest)
    XCTAssertEqual(manager.installations.first(where: { $0.id == id })?.manifest.version, "1.0.0")
    portableFault("persist")
    XCTAssertThrowsError(try portableResult { manager.remove(id: id, completion: $0) }.get())
    XCTAssertNil(manager.nativeScope(installationId: id))
    portableFault("cleanup")
    XCTAssertThrowsError(try portableResult { manager.remove(id: id, completion: $0) }.get())
    XCTAssertEqual(manager.installations.first(where: { $0.id == id })?.state, .removing)
    try portableResult { manager.remove(id: id, completion: $0) }.get()
    XCTAssertNil(manager.installations.first(where: { $0.id == id }))
    print("production persistence faults: disable, package-write and removal retry passed")
}

func runRestartChild(mode: String) throws {
    let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["DG_PLUGIN_TEST_ROOT"]), isDirectory: true)
    let marker = root.appendingPathComponent("restart-id.txt")
    let original = root.appendingPathComponent("original-document.donut.js")
    let manager = DGPluginManager.shared(accountKey: "restart-fixture-account")
    portableFault(nil)
    if mode == "create" {
        manager.setAccountActive(true)
        let package = try portablePackage(id: "dev.example.restart")
        try package.originalData.write(to: original)
        let id = try portableResult { manager.install(package, completion: $0) }.get()
        try portableResult { manager.setEnabled(id: id, enabled: true, completion: $0) }.get()
        try Data(id.utf8).write(to: marker)
        portableFault("cleanup")
        XCTAssertThrowsError(try portableResult { manager.remove(id: id, completion: $0) }.get())
        XCTAssertEqual(manager.installations.first(where: { $0.id == id })?.state, .removing)
        XCTAssertNil(manager.nativeScope(installationId: id))
        let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("state.json"))) as! [String: Any]
        let records = persisted["installations"] as! [[String: Any]]
        XCTAssertEqual(records.first?["removing"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path))
    } else if mode == "verify" {
        let id = try String(contentsOf: marker, encoding: .utf8)
        XCTAssertTrue(manager.installations.isEmpty)
        XCTAssertNil(manager.nativeScope(installationId: id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try DGPluginInstaller.preview(data: Data(contentsOf: original), fileName: "original.donut.js").manifest.id, "dev.example.restart")
        let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("state.json"))) as! [String: Any]
        XCTAssertEqual((persisted["installations"] as? [Any])?.count, 0)
    } else { throw DGPluginError(code: "invalid_argument", message: "unknown restart fixture mode") }
    print("production restart child " + mode + ": passed")
}

func runDurableRemovalRestartTests() throws {
    let base = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["DG_PLUGIN_TEST_ROOT"]), isDirectory: true)
    let childRoot = base.appendingPathComponent("restart-child-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: childRoot, withIntermediateDirectories: true)
    for mode in ["create", "verify"] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [CommandLine.arguments[1]]
        var environment = ProcessInfo.processInfo.environment
        environment["DG_PLUGIN_TEST_ROOT"] = childRoot.path
        environment["DG_PLUGIN_RESTART_MODE"] = mode
        process.environment = environment
        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { if process.isRunning { process.terminate() } }
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "restart child " + mode)
    }
    print("durable removing restart cleanup passed in fresh child processes")
}
