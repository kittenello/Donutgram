param([string]$BuildPath = (Join-Path $env:TEMP 'donutgram-plugin-runtime-tests'))
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$vc = 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat'
$clang = 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\Llvm\x64\bin\clang.exe'
New-Item -ItemType Directory -Force $BuildPath | Out-Null
$BuildPath = (Resolve-Path $BuildPath).Path
Push-Location $repository
try {
    $engineLock = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'engine-lock.json') | ConvertFrom-Json
    foreach ($entry in $engineLock.files.PSObject.Properties) {
        $sourceBytes = [System.Text.Encoding]::UTF8.GetBytes([System.IO.File]::ReadAllText((Join-Path $repository $entry.Name)).Replace("`r`n", "`n"))
        $sourceHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($sourceBytes)).Replace('-', '').ToLowerInvariant()
        if ($sourceHash -ne $entry.Value) {
            throw ('engine checksum mismatch: ' + $entry.Name)
        }
    }
    $bootstrap = (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'Sources/bootstrap.js')).TrimEnd("`r", "`n")
    $swiftBootstrap = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'Sources/DGPluginBootstrap.swift')
    if (!$swiftBootstrap.Contains($bootstrap)) { throw 'embedded bootstrap mismatch' }
    $objects = @()
    foreach ($source in @('quickjs', 'dtoa', 'libregexp', 'libunicode')) {
        $object = Join-Path $BuildPath ($source + '.o')
        $command = 'call "' + $vc + '" >nul && "' + $clang + '" -c -O2 -DQUICKJS_NG_BUILD -Ithird-party/quickjs-ng/include -Ithird-party/quickjs-ng/quickjs third-party/quickjs-ng/quickjs/' + $source + '.c -Wno-everything -o "' + $object + '"'
        cmd /c $command
        if ($LASTEXITCODE -ne 0) { throw ('compile failed: ' + $source) }
        $objects += '"' + $object + '"'
    }
    $executable = Join-Path $BuildPath 'runtime-tests.exe'
    $command = 'call "' + $vc + '" >nul && "' + $clang + '" -std=c++17 -O2 -DQUICKJS_NG_BUILD -IDonutgram/DGPluginRuntime/CHost/include -Ithird-party/quickjs-ng/include Donutgram/DGPluginRuntime/CHost/DGPluginCHost.cpp Donutgram/DGPluginRuntime/Tests/RuntimeTests.cpp ' + ($objects -join ' ') + ' -o "' + $executable + '"'
    cmd /c $command
    if ($LASTEXITCODE -ne 0) { throw 'link failed' }
    $nativeExecutable = Join-Path $BuildPath 'native-work-tests.exe'
    $command = 'call "' + $vc + '" >nul && "' + $clang + '" -std=c++17 -O2 -DQUICKJS_NG_BUILD -IDonutgram/DGPluginRuntime/CHost/include -Ithird-party/quickjs-ng/include Donutgram/DGPluginRuntime/CHost/DGPluginCHost.cpp Donutgram/DGPluginRuntime/Tests/NativeWorkTests.cpp ' + ($objects -join ' ') + ' -o "' + $nativeExecutable + '"'
    cmd /c $command
    if ($LASTEXITCODE -ne 0) { throw 'native-work link failed' }
    foreach ($suite in @('smoke', 'host')) {
        $shim = if ($suite -eq 'smoke') { 'third-party/quickjs-ng/shim/qjs_shim.c ' } else { '' }
        $defaultExecutable = Join-Path $BuildPath ('quickjs-' + $suite + '-tests.exe')
        $command = 'call "' + $vc + '" >nul && "' + $clang + '" -O2 -DQUICKJS_NG_BUILD -Wno-deprecated-declarations -Ithird-party/quickjs-ng/include -Ithird-party/quickjs-ng/quickjs third-party/quickjs-ng/tests/quickjs_' + $suite + '_test.c ' + $shim + ($objects -join ' ') + ' -Xlinker /stack:8388608 -o "' + $defaultExecutable + '"'
        cmd /c $command
        if ($LASTEXITCODE -ne 0) { throw ('default engine link failed: ' + $suite) }
    }
    python (Join-Path $PSScriptRoot 'Tests/run_watchdog.py') --regression $executable --native $nativeExecutable --bootstrap (Join-Path $PSScriptRoot 'Sources/bootstrap.js') --default-smoke (Join-Path $BuildPath 'quickjs-smoke-tests.exe') --default-host (Join-Path $BuildPath 'quickjs-host-tests.exe')
    if ($LASTEXITCODE -ne 0) { throw 'runtime watchdog tests failed' }
} finally {
    Pop-Location
}
