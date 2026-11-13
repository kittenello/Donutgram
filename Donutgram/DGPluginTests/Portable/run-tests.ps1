param(
    [string]$BuildPath = (Join-Path $env:TEMP 'donutgram-plugin-portable-tests'),
    [string]$Swiftc = (Join-Path $env:TEMP 'donutgram-swift-toolchain/portable/LocalApp/Programs/Swift/Toolchains/6.4.2+NoAsserts/usr/bin/swiftc.exe'),
    [string]$Sdk = 'C:/!vazjnoe/dg-swift/LocalApp/Programs/Swift/Platforms/6.4.2/Windows.platform/Developer/SDKs/Windows.sdk',
    [string]$RuntimePath = 'C:/!vazjnoe/dg-swift',
    [string]$Clang = 'C:/Program Files/Microsoft Visual Studio/18/Community/VC/Tools/Llvm/x64/bin/clang.exe',
    [string]$VcEnvironment = 'C:/Program Files/Microsoft Visual Studio/18/Community/VC/Auxiliary/Build/vcvars64.bat'
)
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
New-Item -ItemType Directory -Force -Path $BuildPath | Out-Null
$BuildPath = (Resolve-Path $BuildPath).Path
$dependencies = Join-Path $env:TEMP 'donutgram-plugin-portable-deps'
New-Item -ItemType Directory -Force -Path $dependencies | Out-Null
$zlibArchive = Join-Path $dependencies 'zlib-1.3.2.tar.gz'
if (!(Test-Path -LiteralPath $zlibArchive)) { Invoke-WebRequest -Uri 'https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz' -OutFile $zlibArchive }
if ((Get-FileHash -LiteralPath $zlibArchive -Algorithm SHA256).Hash -ne 'BB329A0A2CD0274D05519D61C667C062E06990D72E125EE2DFA8DE64F0119D16') { throw 'zlib source checksum mismatch' }
$zlib = Join-Path $dependencies 'zlib-1.3.2'
if (!(Test-Path -LiteralPath (Join-Path $zlib 'zlib.h'))) {
    tar.exe -xzf $zlibArchive -C $dependencies
    if ($LASTEXITCODE -ne 0) { throw 'zlib extraction failed' }
}
function Compile-NativeSource([string]$Source, [string]$Name, [string]$Arguments) {
    $object = Join-Path $BuildPath ($Name + '.o')
    $command = 'call "' + $VcEnvironment + '" >nul && "' + $Clang + '" -c -O2 -fms-runtime-lib=dll ' + $Arguments + ' "' + $Source + '" -o "' + $object + '"'
    cmd.exe /c $command
    if ($LASTEXITCODE -ne 0) { throw ('native compilation failed: ' + $Name) }
    return $object
}
function Compile-SwiftModule([string]$Name, [string[]]$NativeObjects = @(), [string[]]$Libraries = @(), [string[]]$Extra = @()) {
    $sources = @(Get-ChildItem -LiteralPath (Join-Path $repository ('Donutgram/' + $Name + '/Sources')) -Filter '*.swift' | ForEach-Object { $_.FullName })
    & $Swiftc -sdk $Sdk -swift-version 5 -I $BuildPath -L $BuildPath -emit-library -emit-module -enable-testing -module-name $Name -emit-module-path (Join-Path $BuildPath ($Name + '.swiftmodule')) -o (Join-Path $BuildPath ($Name + '.dll')) @Libraries @Extra @NativeObjects @sources
    if ($LASTEXITCODE -ne 0) { throw ('swift module compilation failed: ' + $Name) }
}
$archiveHeader = (Join-Path $repository 'Donutgram/DGPluginInstaller/Archive/DGPluginArchive.h').Replace('\', '/')
$runtimeHeader = (Join-Path $repository 'Donutgram/DGPluginRuntime/CHost/include/DGPluginCHost.h').Replace('\', '/')
@"
module DGPluginArchiveC {
 header "$archiveHeader"
 export *
}
module DGPluginCHost {
 header "$runtimeHeader"
 export *
}
"@ | Set-Content -LiteralPath (Join-Path $BuildPath 'module.modulemap')
Push-Location $repository
try {
    Compile-SwiftModule 'DGPluginModel'
    $archiveObjects = @()
    foreach ($source in @('adler32', 'crc32', 'inflate', 'inftrees', 'inffast', 'zutil')) { $archiveObjects += Compile-NativeSource (Join-Path $zlib ($source + '.c')) ('zlib-' + $source) ('-D_CRT_SECURE_NO_WARNINGS -I"' + $zlib + '"') }
    $archiveObjects += Compile-NativeSource (Join-Path $repository 'Donutgram/DGPluginInstaller/Archive/DGPluginArchive.c') 'DGPluginArchive' ('-I"' + $zlib + '"')
    Compile-SwiftModule 'DGPluginInstaller' $archiveObjects @('-lDGPluginModel') @('-Xlinker', 'bcrypt.lib')
    $runtimeObjects = @()
    foreach ($source in @('quickjs', 'dtoa', 'libregexp', 'libunicode')) { $runtimeObjects += Compile-NativeSource (Join-Path $repository ('third-party/quickjs-ng/quickjs/' + $source + '.c')) $source '-DQUICKJS_NG_BUILD -Ithird-party/quickjs-ng/include -Ithird-party/quickjs-ng/quickjs -Wno-everything' }
    $runtimeObjects += Compile-NativeSource (Join-Path $repository 'Donutgram/DGPluginRuntime/CHost/DGPluginCHost.cpp') 'DGPluginCHost' '-std=c++17 -DQUICKJS_NG_BUILD -IDonutgram/DGPluginRuntime/CHost/include -Ithird-party/quickjs-ng/include'
    Compile-SwiftModule 'DGPluginRuntime' $runtimeObjects
    Compile-SwiftModule 'DGPluginNetwork' @() @('-lDGPluginModel')
    Compile-SwiftModule 'DGPluginHost' @() @('-lDGPluginModel', '-lDGPluginInstaller', '-lDGPluginRuntime', '-lDGPluginNetwork') @('-D', 'DG_PLUGINS_SIDELOAD', '-D', 'DG_PLUGIN_TESTS')
    python (Join-Path $PSScriptRoot 'generate_harness.py') $repository $BuildPath
    if ($LASTEXITCODE -ne 0) { throw 'harness generation failed' }
    $fixtures = Join-Path $BuildPath 'fixtures'
    python Donutgram/DGPluginTests/hostile-fixtures/generate_archives.py $fixtures
    if ($LASTEXITCODE -ne 0) { throw 'archive fixture generation failed' }
    & $Swiftc -sdk $Sdk -swift-version 5 -I $BuildPath -L $BuildPath -lDGPluginModel -lDGPluginInstaller -lDGPluginHost -lDGPluginRuntime -lDGPluginNetwork -o (Join-Path $BuildPath 'production-tests.exe') (Join-Path $PSScriptRoot 'Assertions.swift') (Join-Path $PSScriptRoot 'AdditionalTests.swift') (Join-Path $PSScriptRoot 'ReviewRegressions.swift') (Join-Path $PSScriptRoot 'HostLifecycleRegressions.swift') (Join-Path $PSScriptRoot 'DeferredSaveRegressions.swift') (Join-Path $PSScriptRoot 'ViewModelCallbackRegressions.swift') (Join-Path $BuildPath 'installer-tests.swift') (Join-Path $BuildPath 'policy-tests.swift') (Join-Path $BuildPath 'host-tests.swift') (Join-Path $BuildPath 'main.swift')
    if ($LASTEXITCODE -ne 0) { throw 'production test compilation failed' }
    $previousPath = $env:PATH
    $previousRoot = $env:DG_PLUGIN_TEST_ROOT
    $previousBacktrace = $env:SWIFT_BACKTRACE
    try {
        $env:PATH = $RuntimePath + ';' + $BuildPath + ';' + $env:PATH
        $env:DG_PLUGIN_TEST_ROOT = Join-Path $BuildPath ('state-' + [guid]::NewGuid().ToString('N'))
        $env:SWIFT_BACKTRACE = 'enable=no'
        & (Join-Path $BuildPath 'production-tests.exe') $fixtures
        if ($LASTEXITCODE -ne 0) { throw 'production checks failed' }
    } finally { $env:PATH = $previousPath; $env:DG_PLUGIN_TEST_ROOT = $previousRoot; $env:SWIFT_BACKTRACE = $previousBacktrace }
} finally { Pop-Location }
