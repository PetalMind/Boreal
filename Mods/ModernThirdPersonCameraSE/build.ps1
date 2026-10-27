param(
    [string] $Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$buildDir = Join-Path $root "build"
$vcpkgManifestDir = Join-Path $buildDir "vcpkg-manifest"
$stageDir = Join-Path $buildDir "stage"
$compiler = Join-Path $root "../../.local-tools/caprica/Caprica.exe"
$python = Get-Command python -ErrorAction SilentlyContinue

if ([string]::IsNullOrWhiteSpace($env:VCPKG_ROOT)) {
    throw "Set VCPKG_ROOT to your vcpkg checkout before building."
}
if (-not (Test-Path $compiler)) {
    throw "Papyrus compiler was not found at $compiler."
}
if ($null -eq $python) {
    throw "Python 3 is required to create the plugin record."
}

$toolchain = Join-Path $env:VCPKG_ROOT "scripts/buildsystems/vcpkg.cmake"
if (-not (Test-Path $toolchain)) {
    throw "vcpkg CMake toolchain was not found at $toolchain."
}

New-Item -ItemType Directory -Force -Path $vcpkgManifestDir | Out-Null
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

$dll = Join-Path $buildDir "ModernThirdPersonCameraSE.dll"
if (-not (Test-Path $dll)) {
    $dll = Join-Path $buildDir "$Configuration/ModernThirdPersonCameraSE.dll"
}
if (-not (Test-Path $dll)) { throw "Built plugin DLL was not found." }

$pluginDir = Join-Path $stageDir "Data/SKSE/Plugins"
if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
Copy-Item $dll (Join-Path $pluginDir "ModernThirdPersonCameraSE.dll") -Force
Copy-Item (Join-Path $root "Data/SKSE/Plugins/ModernThirdPersonCameraSE.ini") $pluginDir -Force

$scriptsDir = Join-Path $stageDir "Data/Scripts"
New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
$compilerArgs = @(
    "--game=skyrim", "--strict", "--ignorecwd",
    "--flags", (Join-Path $root "Source/CompilerImports/TESV_Papyrus_Flags.flg"),
    "-i", (Join-Path $root "Source/CompilerImports"),
    "-o", $scriptsDir,
    "ModernThirdPersonCameraMCM.psc", "ModernThirdPersonCameraPlayerAlias.psc"
)
Push-Location (Join-Path $root "Source/Scripts")
try {
    & $compiler @compilerArgs
    if ($LASTEXITCODE -ne 0) { throw "Papyrus compilation failed." }
} finally {
    Pop-Location
}

$pluginOutput = Join-Path $stageDir "Data/ModernThirdPersonCameraSE.esp"
& $python.Source (Join-Path $root "tools/build_plugin.py") $pluginOutput
if ($LASTEXITCODE -ne 0) { throw "MCM plugin record generation failed." }
$sequenceDir = Join-Path $stageDir "Data/SEQ"
New-Item -ItemType Directory -Force -Path $sequenceDir | Out-Null
[System.IO.File]::WriteAllBytes(
    (Join-Path $sequenceDir "ModernThirdPersonCameraSE.seq"),
    [BitConverter]::GetBytes([uint32]0x01000800)
)

$archive = Join-Path $buildDir "ModernThirdPersonCameraSE.zip"
if (Test-Path $archive) { Remove-Item $archive -Force }
Compress-Archive -Path (Join-Path $stageDir "Data") -DestinationPath $archive
Write-Output $archive
