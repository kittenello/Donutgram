param(
    [string]$BuildPath = (Join-Path $env:TEMP 'dg-plugin-view-adapter-checks'),
    [string]$ModelPath = (Join-Path $env:TEMP 'donutgram-plugin-portable-tests'),
    [string]$Swiftc = (Join-Path $env:TEMP 'donutgram-swift-toolchain/portable/LocalApp/Programs/Swift/Toolchains/6.4.2+NoAsserts/usr/bin/swiftc.exe'),
    [string]$Sdk = 'C:/!vazjnoe/dg-swift/LocalApp/Programs/Swift/Platforms/6.4.2/Windows.platform/Developer/SDKs/Windows.sdk',
    [string]$RuntimePath = 'C:/!vazjnoe/dg-swift'
)
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if (!(Test-Path -LiteralPath (Join-Path $ModelPath 'DGPluginModel.dll'))) { throw 'build the production portable tests first to provide the real model library' }
New-Item -ItemType Directory -Force -Path $BuildPath | Out-Null
$BuildPath = (Resolve-Path $BuildPath).Path
$env:PATH = $RuntimePath + ';' + $ModelPath + ';' + $BuildPath + ';' + $env:PATH
& $Swiftc -sdk $Sdk -swift-version 5 -emit-library -emit-module -module-name MergeLists -emit-module-path (Join-Path $BuildPath 'MergeLists.swiftmodule') -o (Join-Path $BuildPath 'MergeLists.dll') (Join-Path $repository 'submodules/MergeLists/Sources/Identifiable.swift') (Join-Path $repository 'submodules/MergeLists/Sources/MergeLists.swift')
if ($LASTEXITCODE -ne 0) { throw 'merge lists compilation failed' }
$sources = @(Get-ChildItem -LiteralPath (Join-Path $repository 'Donutgram/DGPluginViewAdapters/Sources') -Filter '*.swift' | ForEach-Object { $_.FullName })
& $Swiftc -sdk $Sdk -swift-version 5 -I $ModelPath -L $ModelPath -lDGPluginModel -emit-library -emit-module -module-name DGPluginViewAdapters -emit-module-path (Join-Path $BuildPath 'DGPluginViewAdapters.swiftmodule') -o (Join-Path $BuildPath 'DGPluginViewAdapters.dll') @sources
if ($LASTEXITCODE -ne 0) { throw 'view projection compilation failed' }
& $Swiftc -sdk $Sdk -swift-version 5 -parse-as-library -I $ModelPath -I $BuildPath -L $ModelPath -L $BuildPath -lDGPluginModel -lDGPluginViewAdapters -lMergeLists (Join-Path $PSScriptRoot 'ProjectionMain.swift') -o (Join-Path $BuildPath 'view-projection-checks.exe')
if ($LASTEXITCODE -ne 0) { throw 'view projection checks compilation failed' }
& (Join-Path $BuildPath 'view-projection-checks.exe')
if ($LASTEXITCODE -ne 0) { throw 'view projection checks failed' }
