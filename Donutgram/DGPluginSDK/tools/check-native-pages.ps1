param(
    [string]$BuildPath = (Join-Path $env:TEMP 'donutgram-sdk-native-page-tests'),
    [string]$Swiftc = (Join-Path $env:TEMP 'donutgram-swift-toolchain/portable/LocalApp/Programs/Swift/Toolchains/6.4.2+NoAsserts/usr/bin/swiftc.exe'),
    [string]$Sdk = 'C:/!vazjnoe/dg-swift/LocalApp/Programs/Swift/Platforms/6.4.2/Windows.platform/Developer/SDKs/Windows.sdk',
    [string]$RuntimePath = 'C:/!vazjnoe/dg-swift'
)
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
New-Item -ItemType Directory -Force -Path $BuildPath | Out-Null
$BuildPath = (Resolve-Path $BuildPath).Path
$model = @(Get-ChildItem -LiteralPath (Join-Path $repository 'Donutgram/DGPluginModel/Sources') -Filter '*.swift' | ForEach-Object { $_.FullName })
& $Swiftc -sdk $Sdk -swift-version 5 -emit-library -emit-module -module-name DGPluginModel -emit-module-path (Join-Path $BuildPath 'DGPluginModel.swiftmodule') -o (Join-Path $BuildPath 'DGPluginModel.dll') @model
if ($LASTEXITCODE -ne 0) { throw 'model compilation failed' }
@'
import Foundation
import DGPluginModel
struct Fixture: Decodable { let name: String; let page: DGPluginJSON; let valid: Bool }
let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
for fixture in fixtures {
    var accepted = false
    do { _ = try DGPluginRenderedState(page: fixture.page, pluginName: "fixture", validity: { true }, callback: { _, _ in }); accepted = true } catch {}
    precondition(accepted == fixture.valid, "native schema disagrees: " + fixture.name)
}
print("native page schema: \(fixtures.count) shared fixtures passed")
'@ | Set-Content -LiteralPath (Join-Path $BuildPath 'main.swift')
& $Swiftc -sdk $Sdk -swift-version 5 -I $BuildPath -L $BuildPath -lDGPluginModel -o (Join-Path $BuildPath 'native-pages.exe') (Join-Path $repository 'Donutgram/DGPluginsUI/Sources/DGPluginPageSchema.swift') (Join-Path $BuildPath 'main.swift')
if ($LASTEXITCODE -ne 0) { throw 'production page schema compilation failed' }
$previousPath = $env:PATH
try {
    $env:PATH = $RuntimePath + ';' + $BuildPath + ';' + $env:PATH
    & (Join-Path $BuildPath 'native-pages.exe') (Join-Path $repository 'Donutgram/DGPluginSDK/tests/ui-validation-cases.json')
    if ($LASTEXITCODE -ne 0) { throw 'native page schema checks failed' }
} finally { $env:PATH = $previousPath }
