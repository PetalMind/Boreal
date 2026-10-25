param(
    [string] $Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$caprica = if ([string]::IsNullOrWhiteSpace($env:CAPRICA_EXE)) {
    Join-Path $root "../../.local-tools/caprica/Caprica.exe"
} else {
    $env:CAPRICA_EXE
}

if ([string]::IsNullOrWhiteSpace($env:VCPKG_ROOT)) {
    throw "Set VCPKG_ROOT to your vcpkg checkout before building."
}
if (-not (Test-Path $caprica)) {
    throw "Caprica Papyrus Compiler was not found at $caprica. Set CAPRICA_EXE."
}

$toolchain = Join-Path $env:VCPKG_ROOT "scripts/buildsystems/vcpkg.cmake"
if (-not (Test-Path $toolchain)) {
    throw "vcpkg CMake toolchain was not found at $toolchain."
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("quest-tracker-hud-se-" + [guid]::NewGuid().ToString("N"))
$vcpkgManifestDir = Join-Path $work "vcpkg-manifest"
$buildDir = Join-Path $work "build"
$stageDir = Join-Path $work "stage"
$scriptOutput = Join-Path $stageDir "Data/Scripts"
$pluginOutput = Join-Path $stageDir "Data"
$archive = Join-Path $root "QuestTrackerHUDSE.zip"

try {
    New-Item -ItemType Directory -Force -Path $vcpkgManifestDir, $scriptOutput, $pluginOutput | Out-Null
    $vcpkgManifest = Get-Content (Join-Path $root "vcpkg.json.in") -Raw
    $vcpkgManifest = $vcpkgManifest.Replace("@VERSION@", [string]$manifest.version)
    Set-Content -Path (Join-Path $vcpkgManifestDir "vcpkg.json") -Value $vcpkgManifest -Encoding utf8
    Copy-Item (Join-Path $root "vcpkg-configuration.json") (Join-Path $vcpkgManifestDir "vcpkg-configuration.json") -Force

    cmake -S $root -B $buildDir `
        -DCMAKE_TOOLCHAIN_FILE="$toolchain" `
        -DVCPKG_MANIFEST_DIR="$vcpkgManifestDir" `
        -DVCPKG_TARGET_TRIPLET=x64-windows-static-md `
        -DCMAKE_BUILD_TYPE=$Configuration
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed." }

    cmake --build $buildDir --config $Configuration
    if ($LASTEXITCODE -ne 0) { throw "Plugin build failed." }

    $dll = Join-Path $buildDir "QuestTrackerHUDSE.dll"
    if (-not (Test-Path $dll)) {
        $dll = Join-Path $buildDir "$Configuration/QuestTrackerHUDSE.dll"
    }
    if (-not (Test-Path $dll)) { throw "Built plugin DLL was not found." }

    $flags = Join-Path $root "Source/CompilerImports/TESV_Papyrus_Flags.flg"
    $imports = Join-Path $root "Source/CompilerImports"
    $scripts = Join-Path $root "Source/Scripts"
    Push-Location $scripts
    try {
        & $caprica --game=skyrim --strict --ignorecwd --flags $flags -i $imports -o $scriptOutput `
            "QuestTrackerNative.psc" "QuestTrackerController.psc" "QuestTrackerMCM.psc"
        $papyrusExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    if ($papyrusExitCode -ne 0) { throw "Papyrus compilation failed." }

    python (Join-Path $root "Source/tools/build_plugin.py") (Join-Path $pluginOutput "QuestTrackerHUDSE.esp")
    if ($LASTEXITCODE -ne 0) { throw "Plugin data file build failed." }

    $sksePluginDir = Join-Path $pluginOutput "SKSE/Plugins"
    New-Item -ItemType Directory -Force -Path $sksePluginDir | Out-Null
    Copy-Item $dll (Join-Path $sksePluginDir "QuestTrackerHUDSE.dll") -Force

    if (Test-Path $archive) { Remove-Item $archive -Force }
    Compress-Archive -Path (Join-Path $stageDir "Data") -DestinationPath $archive
    Write-Output $archive
}
finally {
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
}
