#requires -Version 7
<#
.SYNOPSIS
    Builds the custom `vpk` dotnet tool package from this checkout.

.DESCRIPTION
    The custom changes in this fork are managed (C#) only. The native helper binaries (update/setup/stub
    executables, wix dlls, macOS/Linux updaters) are taken byte-for-byte from the official upstream `vpk`
    package of the base version and packed unchanged next to the custom managed code. No Rust toolchain is needed.

    Note: the vendor binaries are copied into <repo>/target/release (where upstream's pack step expects them),
    overwriting files with the same names there.

.PARAMETER UpstreamVersion
    Official upstream vpk version the vendor binaries are taken from (the base tag of this fork).

.PARAMETER OutputDir
    Where the resulting nupkg and SHA256SUMS are written. Default: <repo>/target/custom-release.

.PARAMETER SkipSignatureVerify
    Skip `dotnet nuget verify` of the downloaded official package.
#>
[CmdletBinding()]
param(
    [string]$UpstreamVersion = '1.3.39-g8d2844f',
    [string]$OutputDir,
    [switch]$SkipSignatureVerify
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) { $OutputDir = Join-Path $repoRoot 'target/custom-release' }
$OutputDir = [IO.Path]::GetFullPath($OutputDir)

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "'$Exe $($Arguments -join ' ')' failed with exit code $LASTEXITCODE" }
}

# Vendor files that Directory.Build.targets packs when PackRustAssets=true.
# The list is read from the targets file of this checkout, so it always matches the base version
# (e.g. a newer base may add more updaters than an older one).
$targetsText = Get-Content (Join-Path $repoRoot 'src/Directory.Build.targets') -Raw
$vendorFiles = @([regex]::Matches($targetsText, '\\target\\release\\([^"\\]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
if ($vendorFiles.Count -eq 0) { throw 'Could not read the vendor file list from src/Directory.Build.targets' }
Write-Host "Vendor files expected by the pack step: $($vendorFiles -join ', ')"

# Expected version: version.json (3-part version, prerelease tag = custom.N).
$versionJson = Get-Content (Join-Path $repoRoot 'version.json') -Raw | ConvertFrom-Json
$expectedVersion = $versionJson.version
if ($expectedVersion -notmatch '^\d+\.\d+\.\d+-custom\.\d+$') {
    throw "version.json version '$expectedVersion' must look like <major>.<minor>.<patch>-custom.<N>"
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("custom-vpk-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    # 1. Official package (fresh dir, untrusted data).
    $lower = $UpstreamVersion.ToLowerInvariant()
    $officialNupkg = Join-Path $work "vpk.$lower.nupkg"
    $url = "https://api.nuget.org/v3-flatcontainer/vpk/$lower/vpk.$lower.nupkg"
    Write-Host "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $officialNupkg -UseBasicParsing

    if (-not $SkipSignatureVerify) {
        Write-Host 'Verifying package signature'
        Invoke-Native dotnet @('nuget', 'verify', '--all', $officialNupkg)
    }

    $officialDir = Join-Path $work 'official'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($officialNupkg, $officialDir)

    # 2. Locate vendor files in the official package.
    $stageDir = Join-Path $work 'stage'
    New-Item -ItemType Directory -Path $stageDir | Out-Null
    foreach ($name in $vendorFiles) {
        $hits = @(Get-ChildItem -Path $officialDir -Recurse -File -Filter $name |
            Where-Object { $_.Name -ceq $name -and $_.FullName -match '[\\/]vendor[\\/]' })
        if ($hits.Count -ne 1) {
            throw "Expected exactly one vendor file '$name' in the official package, found $($hits.Count). Inspect $officialDir."
        }
        Copy-Item $hits[0].FullName (Join-Path $stageDir $name)
    }

    # 3. Place them where upstream's pack step expects the Rust build output.
    $rustOut = Join-Path $repoRoot 'target/release'
    New-Item -ItemType Directory -Force -Path $rustOut | Out-Null
    foreach ($name in $vendorFiles) { Copy-Item (Join-Path $stageDir $name) (Join-Path $rustOut $name) -Force }

    # 4. Build the tool package (managed code only).
    $builtDir = Join-Path $repoRoot 'build/Release'
    Get-ChildItem $builtDir -Filter 'vpk.*.nupkg' -ErrorAction SilentlyContinue | Remove-Item -Force
    Invoke-Native dotnet @(
        'build', (Join-Path $repoRoot 'src/vpk/Velopack.Vpk/Velopack.Vpk.csproj'),
        '-c', 'Release', '/p:PackRustAssets=true', '/p:ContinuousIntegrationBuild=true')

    $customNupkgs = @(Get-ChildItem $builtDir -Filter 'vpk.*.nupkg' | Where-Object { $_.Name -notlike '*.symbols.nupkg' })
    if ($customNupkgs.Count -ne 1) { throw "Expected exactly one vpk nupkg in $builtDir, found $($customNupkgs.Count)" }
    $customNupkg = $customNupkgs[0]

    # 5. Post-checks.
    if ($customNupkg.Name -ne "vpk.$expectedVersion.nupkg") {
        throw "Built package '$($customNupkg.Name)' does not match version.json version '$expectedVersion'"
    }

    $customDir = Join-Path $work 'custom'
    [IO.Compression.ZipFile]::ExtractToDirectory($customNupkg.FullName, $customDir)

    foreach ($name in $vendorFiles) {
        $custom = @(Get-ChildItem -Path $customDir -Recurse -File -Filter $name |
            Where-Object { $_.Name -ceq $name -and $_.FullName -match '[\\/]vendor[\\/]' })
        if ($custom.Count -ne 1) { throw "Vendor file '$name' missing from custom package" }
        $a = (Get-FileHash (Join-Path $stageDir $name) -Algorithm SHA256).Hash
        $b = (Get-FileHash $custom[0].FullName -Algorithm SHA256).Hash
        if ($a -ne $b) { throw "Vendor file '$name' differs from the official package" }
    }
    Write-Host "All $($vendorFiles.Count) vendor files are identical to the official package."

    $officialPackaging = @(Get-ChildItem -Path $officialDir -Recurse -File -Filter 'Velopack.Packaging.Windows.dll' | Where-Object { $_.FullName -match 'net8\.0' })
    $customPackaging = @(Get-ChildItem -Path $customDir -Recurse -File -Filter 'Velopack.Packaging.Windows.dll' | Where-Object { $_.FullName -match 'net8\.0' })
    if ($officialPackaging.Count -ne 1 -or $customPackaging.Count -ne 1) {
        throw 'Could not locate Velopack.Packaging.Windows.dll (net8.0) in both packages'
    }
    if ((Get-FileHash $officialPackaging[0].FullName).Hash -eq (Get-FileHash $customPackaging[0].FullName).Hash) {
        throw 'Custom Velopack.Packaging.Windows.dll is identical to the official one: custom code is not in the package'
    }

    # Smoke test: install into a fresh tool path and check the custom options exist.
    $smokeDir = Join-Path $work 'smoke'
    Invoke-Native dotnet @('tool', 'install', '--tool-path', $smokeDir, 'vpk', '--version', $expectedVersion, '--add-source', $builtDir)
    $vpkExe = Join-Path $smokeDir ($IsWindows ? 'vpk.exe' : 'vpk')
    $help = (& $vpkExe pack --help 2>&1 | Out-String)
    foreach ($opt in '--msiUpgradeCode', '--msiFragment', '--msiCompression') {
        if ($help -notmatch [regex]::Escape($opt)) { throw "Installed tool does not list $opt in 'pack --help'" }
    }
    if ($LASTEXITCODE -ne 0) { throw "Installed tool 'pack --help' failed" }
    $reportedVersion = (& $vpkExe --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or ($reportedVersion -split '\+')[0] -ne $expectedVersion) {
        throw "Installed tool version '$reportedVersion' does not match '$expectedVersion'"
    }
    Write-Host "Smoke test passed (custom MSI options present; version $reportedVersion)."

    # 6. Output.
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $finalNupkg = Join-Path $OutputDir $customNupkg.Name
    Copy-Item $customNupkg.FullName $finalNupkg -Force
    $hash = (Get-FileHash $finalNupkg -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -Path (Join-Path $OutputDir 'SHA256SUMS') -Value "$hash  $($customNupkg.Name)" -Encoding ascii
    Write-Host "Package: $finalNupkg"
    Write-Host "SHA256:  $hash"
}
finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $resolvedWork = [IO.Path]::GetFullPath($work)
    if ((Split-Path -Parent $resolvedWork) -ne $tempRoot -or
        (Split-Path -Leaf $resolvedWork) -notmatch '^custom-vpk-[0-9a-f]{32}$') {
        throw "Refusing to remove unexpected temporary path '$resolvedWork'"
    }
    Remove-Item -LiteralPath $resolvedWork -Recurse -Force -ErrorAction SilentlyContinue
}
