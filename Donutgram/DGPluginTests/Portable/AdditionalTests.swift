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
