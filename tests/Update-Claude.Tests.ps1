#requires -Version 7.0
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../Update-Claude.ps1"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock] $Action, [string] $Pattern) {
    try { & $Action }
    catch {
        if ($_ -notlike "*$Pattern*") { throw "Expected '$Pattern', got: $_" }
        return
    }
    throw "Expected failure containing '$Pattern'."
}

# Mock only external boundaries: GitHub and executable execution. File replacement,
# hashing, archive extraction, link resolution and rollback use the real filesystem.
function Get-ClaudeVersion([string] $ExecutablePath) {
    if ($script:failInstalled -and $ExecutablePath -eq $script:destination -and
        (Get-Content -LiteralPath $ExecutablePath -Raw).Trim() -eq '2.0.0') {
        throw 'Simulated installed executable failure'
    }
    return [version] (Get-Content -LiteralPath $ExecutablePath -Raw).Trim()
}
function Invoke-RestMethod { return $script:release }
function Invoke-WebRequest {
    param($Uri, $OutFile, $Headers)
    Copy-Item -LiteralPath $script:archive -Destination $OutFile
}

$root = Join-Path ([IO.Path]::GetTempPath()) "claude-tests-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $root
try {
    $script:destination = Join-Path $root 'claude.exe'
    $payload = Join-Path $root 'payload'
    $null = New-Item -ItemType Directory -Path $payload
    Set-Content -LiteralPath "$payload/claude.exe" -Value '2.0.0'
    $script:archive = Join-Path $root 'release.zip'
    Compress-Archive -Path "$payload/claude.exe" -DestinationPath $script:archive
    $hash = (Get-FileHash -LiteralPath $script:archive).Hash
    $script:release = [pscustomobject]@{
        tag_name = 'v2.0.0'; draft = $false; prerelease = $false
        assets = @([pscustomobject]@{
            name = 'claude-win32-x64.zip'; digest = "sha256:$hash"
            browser_download_url = 'https://github.com/anthropics/claude-code/releases/download/v2.0.0/claude-win32-x64.zip'
        })
    }
    $script:failInstalled = $false
    Set-Content -LiteralPath $destination -Value '1.0.0'
    Update-Claude -Path $destination -Check
    Update-Claude -Path $destination -WhatIf
    Assert-True (-not (Test-Path "$destination.update.lock")) 'Read-only modes wrote a lock.'
    Assert-True ((Get-ClaudeVersion $destination) -eq [version]'1.0.0') 'Read-only modes changed executable.'
    Update-Claude -Path $destination
    Assert-True ((Get-ClaudeVersion $destination) -eq [version]'2.0.0') 'Update did not install release.'
    $backups = @(Get-ChildItem -LiteralPath $root -Filter '*.bak')
    Assert-True ($backups.Count -eq 1) 'Expected one retained backup.'
    Assert-True ((Get-Content $backups[0].FullName).Trim() -eq '1.0.0') 'Backup lost original content.'
    Update-Claude -Path $destination
    Set-Content -LiteralPath $destination -Value '3.0.0'
    Update-Claude -Path $destination
    Assert-True ((Get-ClaudeVersion $destination) -eq [version]'3.0.0') 'Updater downgraded executable.'
    Set-Content -LiteralPath $destination -Value '1.0.0'
    $release.assets[0].digest = 'sha256:' + ('0' * 64)
    Assert-Throws { Update-Claude -Path $destination } 'SHA-256 mismatch'
    Assert-True ((Get-ClaudeVersion $destination) -eq [version]'1.0.0') 'Hash failure changed executable.'
    $release.assets[0].digest = "sha256:$hash"
    $script:failInstalled = $true
    Assert-Throws { Update-Claude -Path $destination } 'original executable was restored'
    Assert-True ((Get-ClaudeVersion $destination) -eq [version]'1.0.0') 'Rollback did not restore original.'
    $script:failInstalled = $false
    $heldLock = [IO.File]::Open("$destination.update.lock", 'OpenOrCreate', 'ReadWrite', 'None')
    try { Assert-Throws { Update-Claude -Path $destination } 'Cannot acquire update lock' }
    finally { $heldLock.Dispose() }
    # A junction/symlink requires privileges on some hosts; an existing WinGet link
    # is checked separately during read-only integration validation.
    Assert-Throws { Resolve-ClaudePath $archive } 'Expected an existing claude.exe'
    Assert-True (@(Get-ChildItem -LiteralPath $root -Filter '*.new').Count -eq 0) 'Staged file leaked.'
    $secondDirectory = Join-Path $root 'second'
    $null = New-Item -ItemType Directory -Path $secondDirectory
    $second = Join-Path $secondDirectory 'claude.exe'
    Set-Content -LiteralPath $second -Value '1.0.0'
    # Simulate PATH discovery with a repeated target, including case differences.
    $script:discovered = @($destination, $destination.ToUpperInvariant(), $second)
    function Get-Command { $script:discovered | ForEach-Object { [pscustomobject]@{ Source = $_ } } }
    Update-Claude -Check
    Update-Claude -WhatIf
    Assert-True ((Get-ClaudeVersion $second) -eq [version]'1.0.0') 'Multi-install preview changed executable.'
    Assert-True (-not (Test-Path "$second.update.lock")) 'Multi-install preview wrote a lock.'
    $beforeBackups = @(Get-ChildItem -LiteralPath $root -Filter '*.bak').Count
    Update-Claude
    Assert-True ((Get-ClaudeVersion $destination) -eq [version]'2.0.0') 'First installation was not updated.'
    Assert-True ((Get-ClaudeVersion $second) -eq [version]'2.0.0') 'Second installation was not updated.'
    Assert-True (@(Get-ChildItem -LiteralPath $root -Filter '*.bak').Count -eq ($beforeBackups + 1)) 'Duplicate targets produced extra backups.'
    Assert-True (@(Get-ChildItem -LiteralPath $secondDirectory -Filter '*.bak').Count -eq 1) 'Second backup missing.'
    Set-Content -LiteralPath $destination -Value '1.0.0'
    Set-Content -LiteralPath $second -Value '1.0.0'
    $heldLock = [IO.File]::Open("$destination.update.lock", 'OpenOrCreate', 'ReadWrite', 'None')
    try { Assert-Throws { Update-Claude } 'One or more Claude installations failed' }
    finally { $heldLock.Dispose() }
    Assert-True ((Get-ClaudeVersion $destination) -eq [version]'1.0.0') 'Locked installation changed.'
    Assert-True ((Get-ClaudeVersion $second) -eq [version]'2.0.0') 'Failure prevented independent installation update.'
    Write-Host 'PASS: update, backup, no-op, downgrade prevention, hash rejection, rollback, locking, path validation, multi-install discovery, deduplication, previews and partial failure.'
}
finally {
    # The absolute deletion target is the unique directory created above.
    if ((Split-Path $root -Parent) -ne [IO.Path]::GetTempPath().TrimEnd('\', '/')) { throw "Unexpected test cleanup path: $root" }
    Remove-Item -LiteralPath $root -Recurse -Force
}
