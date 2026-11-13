import Foundation
import DGPluginModel
import DGPluginInstaller
import DGPluginHost

private enum DGPluginReviewRegressions {
    static func log(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
    static func result<T>(_ operation: (@escaping (Result<T,DGPluginError>) -> Void) -> Void) throws -> T {
        let done = DispatchSemaphore(value: 0)
        var outcome: Result<T,DGPluginError>?
        operation { outcome = $0; done.signal() }
        guard done.wait(timeout: .now() + 12) == .success else { throw DGPluginError(code: "test_timeout", message: "probe timed out") }
        return try outcome!.get()
    }
    static func package(_ body: String, permissions: [DGPluginPermission], schema: DGPluginJSON? = nil, id: String = "dev.review.probe-" + UUID().uuidString.lowercased(), version: String = "1.0.0") throws -> DGVerifiedPluginPackage {
        let manifest = DGPluginManifest(id: id, name: "review probe", version: version, description: "isolated review probe", permissions: permissions, settingsSchema: schema)
        let json = String(data: try JSONEncoder().encode(manifest), encoding: .utf8)!
        let source = "const _plugin = \"donutgram\";\nconst manifest = " + json + ";\nexport default definePlugin(manifest,{async activate(api){" + body + "}});"
        return try DGPluginInstaller.preview(data: Data(source.utf8), fileName: "probe.donut.js")
    }
    static func install(_ manager: DGPluginManager, _ package: DGVerifiedPluginPackage) throws -> String {
        let id = try result { manager.install(package, completion: $0) }
        try result { manager.setGrants(id: id, permissions: package.manifest.permissions, completion: $0) }
        try result { manager.setEnabled(id: id, enabled: true, completion: $0) }
        return id
    }
    static func manager(_ suffix: String) -> DGPluginManager {
        let manager = DGPluginManager.shared(accountKey: "review-" + suffix)
        manager.setAccountActive(true)
        manager.setForegroundActive(true)
        manager.setGloballyEnabled(true)
        return manager
    }
    static let ui = DGPluginPermission(capability: "ui.contribute", scope: "settings", reason: "review")
    static let storage = DGPluginPermission(capability: "storage.local", scope: "pluginAccount", reason: "review")
    static let transform = DGPluginPermission(capability: "ui.transform", scope: "profile", reason: "review")
    
    static func cacheProbe() throws {
        let m = manager("cache")
        let schema: DGPluginJSON = .object(["type": .string("object"), "properties": .object(["hide": .object(["type": .string("boolean"), "title": .string("hide"), "default": .bool(true)])])])
        let id = try install(m, package("await api.transforms.register({id:'hide',slot:'profile'},async()=>({hide:(await api.settings.get()).hide?['media']:[]}));", permissions: [transform], schema: schema))
        let input: DGPluginJSON = .object(["panes": .array([.object(["id": .string("media"), "empty": .bool(true)])])])
        let ready = DispatchSemaphore(value: 0)
        _ = m.transformedViewModel(slot: "profile", input: input, update: { ready.signal() })
        guard ready.wait(timeout: .now() + 4) == .success else { throw DGPluginError(code:"test_timeout",message:"cache not populated") }
        let before = m.transformedViewModel(slot: "profile", input: input, update: {})
        let revision = m.viewTransformState(slot: "profile").revision
        try result { m.updateSettings(id: id, values: ["hide": .bool(false)], completion: $0) }
        let after = m.transformedViewModel(slot: "profile", input: input, update: {})
        guard before != input, after == input, revision != m.viewTransformState(slot:"profile").revision else { throw DGPluginError(code:"regression",message:"stale transform") }; log("cache passed")
        try result { m.remove(id: id, completion: $0) }
    }
    static func callbacksProbe() throws {
        let m = manager("callbacks")
        var invoke: ((String,DGPluginJSON) -> Void)?
        var callbackId = ""
        var actionId = ""
        var reply: ((Result<DGPluginJSON,DGPluginError>) -> Void)?
        var toasts = 0
        let first = DispatchSemaphore(value: 0)
        m.nativeRender = { _,page,_,_,_,callback,_ in
            invoke = callback
            if case let .array(nodes)? = page.objectValue?["nodes"] { callbackId = nodes[0].objectValue?["callbackId"]?.stringValue ?? ""; actionId = nodes[1].objectValue?["callbackId"]?.stringValue ?? "" }
            return .success({})
        }
        m.nativeRequest = { _,_,_,_,completion in toasts += 1; if toasts == 1 { reply = completion; first.signal() } else { completion(.success(.null)) } }
        let id = try install(m, package("let seen=[];const page=()=>({id:'page',title:'page',nodes:[{id:'input',type:'input',title:'input',callbackId:cb.id,value:''},{id:'action',type:'button',title:'action',callbackId:action.id}]});const cb=api.ui.callback(async v=>{seen.push(v);await api.ui.toast('wait');await api.ui.render(page())});const action=api.ui.callback(v=>{seen.push(v)});await api.commands.register({id:'show',title:'show',placement:'settings',run:()=>api.ui.render(page())});await api.commands.register({id:'verify',title:'verify',placement:'settings',run:()=>{if(seen.join(',')!=='a,value99,action1,value101')throw Error('unexpected values')}});",permissions:[ui]))
        try result { m.runCommand(installationId: id, commandId: "show", completion: $0) }
        invoke?(callbackId, .string("a"))
        guard first.wait(timeout: .now() + 4) == .success else { throw DGPluginError(code:"test_timeout",message:"callback not run") }
        for index in 0..<100 { invoke?(callbackId, .string("value\(index)")) }
        invoke?(actionId, .string("action1"))
        invoke?(callbackId, .string("value101"))
        Thread.sleep(forTimeInterval: 0.1)
        reply?(.success(.null))
        Thread.sleep(forTimeInterval: 0.15)
        try result { m.runCommand(installationId: id, commandId: "verify", completion: $0) }
        guard toasts == 3 else { throw DGPluginError(code:"regression",message:"callback lost") }; log("callbacks passed")
        try result { m.remove(id: id, completion: $0) }
    }
    static func transformInvalidationDrainProbe() throws {
        let m = manager("transform-drain")
        var invoke: ((String, DGPluginJSON) -> Void)?
        var callbackId = ""
        var reply: ((Result<DGPluginJSON, DGPluginError>) -> Void)?
        var requests = 0
        let entered = DispatchSemaphore(value:0)
        let delivered = DispatchSemaphore(value:0)
        m.nativeRender = { _, page, _, _, _, callback, _ in
            invoke = callback
            if case let .array(nodes)? = page.objectValue?["nodes"] { callbackId = nodes[0].objectValue?["callbackId"]?.stringValue ?? "" }
            return .success({})
        }
        m.nativeRequest = { _, _, _, _, completion in
            requests += 1
            if requests == 1 { reply = completion; entered.signal() }
            else { completion(.success(.null)); delivered.signal() }
        }
        let id = try install(m, package("const cb=api.ui.callback(()=>api.ui.toast('callback'));await api.events.on('locale.changed',()=>api.ui.toast('event'));await api.transforms.register({id:'mutate',slot:'profile'},async()=>{await api.ui.toast('hold');await api.settings.set({});return {}});await api.commands.register({id:'show',title:'show',placement:'settings',run:()=>api.ui.render({id:'page',title:'page',nodes:[{id:'button',type:'button',title:'button',callbackId:cb.id}]})});", permissions:[ui,transform]))
        try result { m.runCommand(installationId:id,commandId:"show",completion:$0) }
        _ = m.transformedViewModel(slot:"profile",input:.object(["panes":.array([])]),update:{})
        guard entered.wait(timeout:.now() + 4) == .success else { throw DGPluginError(code:"regression",message:"transform not entered") }
        invoke?(callbackId,.null)
        m.emitNativeEvent(name:"locale.changed",payload:.object([:]),installationId:id)
        Thread.sleep(forTimeInterval:0.05)
        reply?(.success(.null))
        for _ in 0..<2 {
            guard delivered.wait(timeout:.now() + 4) == .success else { throw DGPluginError(code:"regression",message:"invalidated transform stranded queued work") }
        }
        try result { m.remove(id:id,completion:$0) }
        log("transform invalidation drain passed")
    }
    static func sharedCallbackProbe() throws {
        let m = manager("shared-callback")
        var invoke: ((String, DGPluginJSON) -> Void)?
        var callbackId = ""
        var reply: ((Result<DGPluginJSON, DGPluginError>) -> Void)?
        let entered = DispatchSemaphore(value:0)
        m.nativeRender = { _, page, _, _, _, callback, _ in
            invoke = callback
            if case let .array(nodes)? = page.objectValue?["nodes"] { callbackId = nodes[0].objectValue?["callbackId"]?.stringValue ?? "" }
            return .success({})
        }
        m.nativeRequest = { _, _, _, _, completion in reply = completion; entered.signal() }
        let id = try install(m, package("let seen=[];const cb=api.ui.callback(async v=>{seen.push(v);if(v==='a')await api.ui.toast('wait')});await api.commands.register({id:'show',title:'show',placement:'settings',run:()=>api.ui.render({id:'page',title:'page',nodes:[{id:'one',type:'input',title:'one',callbackId:cb.id,value:''},{id:'two',type:'input',title:'two',callbackId:cb.id,value:''}]})});await api.commands.register({id:'verify',title:'verify',placement:'settings',run:()=>{if(seen.join(',')!=='a,one,two,one-again')throw Error(seen.join(','))}});", permissions:[ui]))
        try result { m.runCommand(installationId:id,commandId:"show",completion:$0) }
        invoke?(callbackId,.string("a"))
        guard entered.wait(timeout:.now() + 4) == .success else { throw DGPluginError(code:"regression",message:"shared callback not entered") }
        for value in ["one", "two", "one-again"] { invoke?(callbackId,.string(value)) }
        Thread.sleep(forTimeInterval:0.05)
        reply?(.success(.null))
        Thread.sleep(forTimeInterval:0.15)
        try result { m.runCommand(installationId:id,commandId:"verify",completion:$0) }
        try result { m.remove(id:id,completion:$0) }
        log("shared callback passed")
    }
    static func pageLifetimeProbe() throws {
        let m = manager("page-lifetime")
        var invoke: ((String, DGPluginJSON) -> Void)?
        var closed: (() -> Void)?
        var callbackId = ""
        var reply: ((Result<DGPluginJSON, DGPluginError>) -> Void)?
        let entered = DispatchSemaphore(value: 0)
        m.nativeRender = { _, page, _, _, _, callback, onClose in
            invoke = callback; closed = onClose
            if case let .array(nodes)? = page.objectValue?["nodes"] { callbackId = nodes[0].objectValue?["callbackId"]?.stringValue ?? "" }
            return .success({})
        }
        m.nativeRequest = { _, _, _, _, completion in reply = completion; entered.signal() }
        let id = try install(m, package("let seen=[];const cb=api.ui.callback(async v=>{seen.push(v);if(v==='a')await api.ui.toast('wait')});await api.commands.register({id:'show',title:'show',placement:'settings',run:()=>api.ui.render({id:'page',title:'page',nodes:[{id:'input',type:'input',title:'input',callbackId:cb.id,value:''}]})});await api.commands.register({id:'verify',title:'verify',placement:'settings',run:()=>{if(seen.join(',')!=='a,fresh')throw Error(seen.join(','))}});", permissions:[ui]))
        try result { m.runCommand(installationId:id, commandId:"show", completion:$0) }
        let oldInvoke = invoke
        invoke?(callbackId, .string("a"))
        guard entered.wait(timeout:.now() + 4) == .success else { throw DGPluginError(code:"regression",message:"callback not entered") }
        invoke?(callbackId, .string("queued-old"))
        closed?()
        reply?(.success(.null))
        Thread.sleep(forTimeInterval:0.15)
        try result { m.runCommand(installationId:id, commandId:"show", completion:$0) }
        oldInvoke?(callbackId, .string("late-old"))
        invoke?(callbackId, .string("fresh"))
        Thread.sleep(forTimeInterval:0.15)
        try result { m.runCommand(installationId:id, commandId:"verify", completion:$0) }
        try result { m.remove(id:id, completion:$0) }
        log("page lifetime passed")
    }
    static func callbackOverflowProbe() throws {
        let m = manager("callback-overflow")
        var invoke: ((String, DGPluginJSON) -> Void)?
        var callbackId = ""
        var reply: ((Result<DGPluginJSON, DGPluginError>) -> Void)?
        let entered = DispatchSemaphore(value: 0)
        m.nativeRender = { _, page, _, _, _, callback, _ in
            invoke = callback
            if case let .array(nodes)? = page.objectValue?["nodes"] { callbackId = nodes[0].objectValue?["callbackId"]?.stringValue ?? "" }
            return .success({})
        }
        m.nativeRequest = { _, _, _, _, completion in reply = completion; entered.signal() }
        let id = try install(m, package("let taps=0;const cb=api.ui.callback(async()=>{if(++taps===1)await api.ui.toast('wait')});await api.commands.register({id:'show',title:'show',placement:'settings',run:()=>api.ui.render({id:'page',title:'page',nodes:[{id:'button',type:'button',title:'button',callbackId:cb.id}]})});await api.commands.register({id:'verify',title:'verify',placement:'settings',run:()=>{if(taps!==65)throw Error(String(taps))}});", permissions:[ui]))
        try result { m.runCommand(installationId:id, commandId:"show", completion:$0) }
        invoke?(callbackId, .null)
        guard entered.wait(timeout:.now() + 4) == .success else { throw DGPluginError(code:"regression",message:"first tap not delivered") }
        // 80 taps while the first waits: 64 queue, the rest are dropped, and the plugin stays on.
        for _ in 0..<80 { invoke?(callbackId, .null) }
        Thread.sleep(forTimeInterval:0.1)
        reply?(.success(.null))
        Thread.sleep(forTimeInterval:1.0)
        guard m.installations.first(where: { $0.id == id })?.state == .running else { throw DGPluginError(code:"regression",message:"taps on a busy page turned the plugin off") }
        try result { m.runCommand(installationId:id, commandId:"verify", completion:$0) }
        try result { m.remove(id:id, completion:$0) }
        log("callback overflow passed")
    }
    static func defaultsProbe() throws {
        let schema: DGPluginJSON = .object(["type": .string("object"), "properties": .object(["label": .object(["type": .string("string"), "title": .string("label"), "maxLength": .number(1), "default": .string("😀")]), "enabled": .object(["type": .string("boolean"), "title": .string("enabled"), "default": .bool(true)])])])
        let p = try package("",permissions:[],schema:schema)
        guard DGPluginPolicy.settingsDefaults(p.manifest).count == 2 else { throw DGPluginError(code:"regression",message:"defaults lost") }; log("defaults passed")
    }
    static func environmentProbe() throws {
        let m = manager("environment")
        let id = try install(m, package("await api.commands.register({id:'check',title:'check',placement:'settings',run:async()=>{if((await api.environment.get()).locale!=='ru')throw Error('changed')}});",permissions:[ui]))
        m.updateEnvironment(locale:"ru",appearance:"dark")
        try result { m.runCommand(installationId:id,commandId:"check",completion:$0) }
        log("environment passed")
        try result { m.remove(id:id,completion:$0) }
    }
    static func packageCacheProbe() throws {
        let m = manager("packages")
        func cachedPackages() -> Int {
            let coordinator = Mirror(reflecting:m).children.first{$0.label == "coordinator"}!.value
            return (Mirror(reflecting:coordinator).children.first{$0.label == "packages"}!.value as! [String:DGVerifiedPluginPackage]).count
        }
        let before = cachedPackages()
        let pluginId = "dev.review.versions-" + UUID().uuidString.lowercased()
        var installation = ""
        for n in 1...5 {
            let p = try package("",permissions:[],id:pluginId,version:"\(n).0.0")
            installation = try result { m.install(p,completion:$0) }
        }
        let root = URL(fileURLWithPath:ProcessInfo.processInfo.environment["DG_PLUGIN_TEST_ROOT"]!)
        let files = try FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent(installation).path)
        guard files.filter({ $0.hasSuffix(".package") }).count == 2 else { throw DGPluginError(code:"regression",message:"disk version retention") }
        let during = cachedPackages()
        try result { m.remove(id:installation,completion:$0) }
        guard during-before <= 2, cachedPackages() == before else { throw DGPluginError(code:"regression",message:"package leak") }; log("package cache passed")
    }
    static func quotaProbe() throws {
        let m = manager("quota")
        var ids: [String] = []
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DG_PLUGIN_TEST_ROOT"]!)
        let body = "let next=0;await api.commands.register({id:'fill',title:'fill',placement:'settings',run:async()=>{for(let i=0;i<10;i++)await api.storage.set('key'+next++,'x'.repeat(60000))}});"
        var rejected = false
        for n in 0..<7 {
            let id = try install(m, package(body, permissions:[ui,storage]))
            ids.append(id)
            for _ in 0..<8 { do { try result { m.runCommand(installationId:id,commandId:"fill",completion:$0) } } catch { rejected = true; break } }
            if n < 6 { try result { m.setEnabled(id:id,enabled:false,completion:$0) } }
            log("quota fill plugin \(n+1): disk_bytes=\((try? Data(contentsOf:root.appendingPathComponent("state.json")).count) ?? -1)")
        }
        Thread.sleep(forTimeInterval:0.8)
        guard rejected, m.persistenceError == nil else { throw DGPluginError(code:"regression",message:"quota not enforced") }
        try result { m.setEnabled(id:ids.last!,enabled:false,completion:$0) }
        log("quota passed")
        for id in ids { try result { m.resetData(id:id,completion:$0) }; try result { m.remove(id:id,completion:$0) } }
    }
}

func runPluginReviewRegressionTests() throws {
    try DGPluginReviewRegressions.cacheProbe()
    try DGPluginReviewRegressions.callbacksProbe()
    try DGPluginReviewRegressions.transformInvalidationDrainProbe()
    try DGPluginReviewRegressions.sharedCallbackProbe()
    try DGPluginReviewRegressions.pageLifetimeProbe()
    try DGPluginReviewRegressions.callbackOverflowProbe()
    try DGPluginReviewRegressions.defaultsProbe()
    try DGPluginReviewRegressions.environmentProbe()
    try DGPluginReviewRegressions.packageCacheProbe()
    try DGPluginReviewRegressions.quotaProbe()
    try runMissingAccountQuotaRegression()
}

func runMissingAccountQuotaRegression(child: Bool = false) throws {
    if !child {
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DG_PLUGIN_TEST_ROOT"]!)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [CommandLine.arguments[1]]
        var environment = ProcessInfo.processInfo.environment
        environment["DG_PLUGIN_TEST_ROOT"] = base.appendingPathComponent("missing-account-child").path
        environment["DG_PLUGIN_QUOTA_CHILD"] = "1"
        process.environment = environment
        try process.run()
        DispatchQueue.global().asyncAfter(deadline:.now() + 30) { if process.isRunning { process.terminate() } }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DGPluginError(code:"regression",message:"missing account quota child failed") }
        return
    }
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DG_PLUGIN_TEST_ROOT"]!)
    let permissions = [DGPluginReviewRegressions.ui, DGPluginReviewRegressions.storage]
    let package = try DGPluginReviewRegressions.package("let rejected=0;try{await api.settings.set(await api.settings.get())}catch(e){if(e.code==='quota_exceeded')rejected++}try{await api.storage.remove('absent')}catch(e){if(e.code==='quota_exceeded')rejected++}if(rejected!==2)throw Error('missing-account writes exceeded quota');", permissions:permissions)
    let id = UUID().uuidString
    let directory = root.appendingPathComponent(id)
    try FileManager.default.createDirectory(at:directory, withIntermediateDirectories:true)
    try package.originalData.write(to:directory.appendingPathComponent(package.digest + ".package"))
    let manifest = try JSONSerialization.jsonObject(with:JSONEncoder().encode(package.manifest))
    var accounts: [String: Any] = [:]
    for n in 0..<7 {
        accounts["existing-\(n)"] = ["enabled":false,"grants":[],"settings":[:],"storage":["padding":String(repeating:"x",count:(31 * 1024 * 1024) / 7)],"failures":0] as [String:Any]
    }
    let record: [String:Any] = ["id":id,"manifest":manifest,"digest":package.digest,"publisherIdentity":package.publisherIdentity,"trust":package.trust,"fileName":"probe.donut.js","removing":false,"accounts":accounts]
    let state: [String:Any] = ["schemaVersion":1,"globallyEnabled":true,"installations":[record]]
    try JSONSerialization.data(withJSONObject:state).write(to:root.appendingPathComponent("state.json"))
    let manager = DGPluginReviewRegressions.manager("missing-account")
    let owner = UUID()
    try DGPluginReviewRegressions.result { manager.prepareSettings(id:id,owner:owner,completion:$0) }
    manager.closeSettings(id:id,owner:owner)
    manager.setForegroundActive(false)
    Thread.sleep(forTimeInterval:0.7)
    guard manager.persistenceError == nil else { throw DGPluginError(code:"regression",message:"missing account persistence failed") }
    let saved = try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("state.json"))) as! [String:Any]
    let savedAccounts = (saved["installations"] as! [[String:Any]])[0]["accounts"] as! [String:Any]
    guard savedAccounts["review-missing-account"] == nil else { throw DGPluginError(code:"regression",message:"quota created a new account") }
    DGPluginReviewRegressions.log("missing-account quota passed")
}
