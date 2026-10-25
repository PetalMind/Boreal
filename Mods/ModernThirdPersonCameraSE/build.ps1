param(
    [string] $Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$buildDir = Join-Path $root "build"
$vcpkgManifestDir = Join-Path $buildDir "vcpkg-manifest"
$stageDir = Join-Path $buildDir "stage"

if ([string]::IsNullOrWhiteSpace($env:VCPKG_ROOT)) {
    throw "Set VCPKG_ROOT to your vcpkg checkout before building."
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

$archive = Join-Path $buildDir "ModernThirdPersonCameraSE.zip"
if (Test-Path $archive) { Remove-Item $archive -Force }
Compress-Archive -Path (Join-Path $stageDir "Data") -DestinationPath $archive
Write-Output $archive
