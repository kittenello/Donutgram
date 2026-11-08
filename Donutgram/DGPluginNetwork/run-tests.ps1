param(
    [string]$BuildPath = (Join-Path $env:TEMP 'donutgram-plugin-network-tests'),
    [string]$Swiftc = (Join-Path $env:TEMP 'donutgram-swift-toolchain/portable/LocalApp/Programs/Swift/Toolchains/6.4.2+NoAsserts/usr/bin/swiftc.exe'),
    [string]$Sdk = 'C:/!vazjnoe/dg-swift/LocalApp/Programs/Swift/Platforms/6.4.2/Windows.platform/Developer/SDKs/Windows.sdk',
    [string]$RuntimePath = 'C:/!vazjnoe/dg-swift'
)
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
New-Item -ItemType Directory -Force -Path $BuildPath | Out-Null
$BuildPath = (Resolve-Path $BuildPath).Path
$modelSources = @(Get-ChildItem -LiteralPath (Join-Path $repository 'Donutgram/DGPluginModel/Sources') -Filter '*.swift' | ForEach-Object { $_.FullName })
$networkSources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Sources') -Filter '*.swift' | ForEach-Object { $_.FullName })
& $Swiftc -sdk $Sdk -swift-version 5 -emit-library -emit-module -module-name DGPluginModel -emit-module-path (Join-Path $BuildPath 'DGPluginModel.swiftmodule') -o (Join-Path $BuildPath 'DGPluginModel.dll') @modelSources
if ($LASTEXITCODE -ne 0) { throw 'model compilation failed' }
& $Swiftc -sdk $Sdk -swift-version 5 -I $BuildPath -L $BuildPath -lDGPluginModel -emit-library -emit-module -module-name DGPluginNetwork -emit-module-path (Join-Path $BuildPath 'DGPluginNetwork.swiftmodule') -o (Join-Path $BuildPath 'DGPluginNetwork.dll') @networkSources
if ($LASTEXITCODE -ne 0) { throw 'network helper compilation failed' }
$testSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Tests/DGPluginNetworkTests.swift')).Replace("import XCTest`r`n", '').Replace("import XCTest`n", '')
[System.IO.File]::WriteAllText((Join-Path $BuildPath 'NetworkTests.swift'), $testSource)
& $Swiftc -sdk $Sdk -swift-version 5 -I $BuildPath -L $BuildPath -lDGPluginModel -lDGPluginNetwork -o (Join-Path $BuildPath 'network-tests.exe') (Join-Path $PSScriptRoot 'Tests/StandaloneAssertions.swift') (Join-Path $BuildPath 'NetworkTests.swift') (Join-Path $PSScriptRoot 'Tests/main.swift')
if ($LASTEXITCODE -ne 0) { throw 'network test compilation failed' }
$previousPath = $env:PATH
try {
    $env:PATH = $RuntimePath + ';' + $BuildPath + ';' + $env:PATH
    & (Join-Path $BuildPath 'network-tests.exe')
    if ($LASTEXITCODE -ne 0) { throw 'network helper tests failed' }
} finally { $env:PATH = $previousPath }
