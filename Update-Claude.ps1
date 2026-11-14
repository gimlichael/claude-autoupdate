<#
.SYNOPSIS
Updates existing Windows x64 Claude executables from official GitHub releases.
.DESCRIPTION
Finds every native claude.exe on PATH, follows links and updates each distinct
target. Verifies the archive SHA-256 and executable version, retains a backup,
and attempts rollback if the installed version check fails. Requires Windows x64
and PowerShell 7. Failed installations do not prevent attempts on the others.
.PARAMETER Path
Update only this existing claude.exe instead of discovering all targets on PATH.
.PARAMETER Check
Show installed and latest versions without downloading or writing files.
.EXAMPLE
./Update-Claude.ps1
Updates all distinct native Claude installations on PATH.
.EXAMPLE
./Update-Claude.ps1 -Check
Checks all discovered installations without changing files.
.EXAMPLE
./Update-Claude.ps1 -Path "$HOME/.local/bin/claude.exe"
Updates only the specified installation.
.EXAMPLE
./Update-Claude.ps1 -WhatIf
Previews replacements without downloading or changing files.
.NOTES
MIT License

Copyright (c) 2026 gimlichael

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

#requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Path,
    [switch] $Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ClaudePath {
    param([string] $ExecutablePath)
    $item = Get-Item -LiteralPath $ExecutablePath -Force
    if ($item.PSIsContainer -or $item.Name -ine 'claude.exe') {
        throw "Expected an existing claude.exe: $ExecutablePath"
    }
    if ($item.LinkType) {
        $item = $item.ResolveLinkTarget($true)
        if ($null -eq $item -or -not $item.Exists) { throw "Broken executable link: $ExecutablePath" }
    }
    return $item.FullName
}

function Get-ClaudeVersion {
    param([string] $ExecutablePath)
    $output = & $ExecutablePath --version 2>&1
    if ($LASTEXITCODE -ne 0 -or "$output" -notmatch '^\s*(\d+\.\d+\.\d+)(?:\s|$)') {
        throw "Cannot read Claude version from '$ExecutablePath': $output"
    }
    return [version] $Matches[1]
}

function Install-ClaudeExecutable {
    param([string] $Source, [string] $Destination, [version] $Version)
    # Stage beside the destination so replacement stays on the same volume.
    $staged = "$Destination.$([guid]::NewGuid().ToString('N')).new"
    $backup = "$Destination.$([guid]::NewGuid().ToString('N')).bak"
    try {
        Copy-Item -LiteralPath $Source -Destination $staged
        try {
            [IO.File]::Replace($staged, $Destination, $backup)
        }
        catch {
            throw "Cannot replace '$Destination'. Close Claude sessions and check directory permissions (an administrator shell may be needed). $($_.Exception.Message)"
        }
        try {
            if ((Get-ClaudeVersion $Destination) -ne $Version) { throw 'Installed version does not match the release.' }
        }
        catch {
            $failure = $_
            try { [IO.File]::Replace($backup, $Destination, [System.Management.Automation.Language.NullString]::Value) }
            catch { throw "Update verification failed; rollback also failed. Restore '$backup' to '$Destination'. $($_.Exception.Message)" }
            throw "Update verification failed; the original executable was restored. $failure"
        }
        Write-Host "Updated Claude to $Version at $Destination"
        Write-Host "Previous executable retained at $backup"
    }
    finally {
        if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Force }
    }
}

function Update-Claude {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $Path, [switch] $Check)
    if (-not $IsWindows -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') {
        throw 'This updater supports Windows x64 only.'
    }
    $destinations = if ($Path) {
        @(Resolve-ClaudePath $Path)
    }
    else {
        @(Get-Command claude.exe -All -CommandType Application -ErrorAction SilentlyContinue |
            ForEach-Object { Resolve-ClaudePath $_.Source } | Sort-Object -Unique)
    }
    if (@($destinations).Count -eq 0) { throw 'No claude.exe found on PATH. Supply -Path to an existing executable.' }
    $failures = @()
    foreach ($destination in $destinations) {
        try {
            Update-ClaudeInstallation -Destination $destination -Check:$Check -WhatIf:$WhatIfPreference
        }
        catch {
            $failures += "${destination}: $($_.Exception.Message)"
            Write-Warning "Failed to update '${destination}': $($_.Exception.Message)"
        }
    }
    if ($failures.Count -gt 0) { throw "One or more Claude installations failed:`n$($failures -join "`n")" }
}

function Update-ClaudeInstallation {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $Destination, [switch] $Check)
    # Keep concurrent invocations from replacing the same executable.
    $lockPath = "$destination.update.lock"
    $lock = $null
    $temporary = $null
    try {
        $installed = Get-ClaudeVersion $destination
        $headers = @{ 'User-Agent' = 'claude-autoupdate'; Accept = 'application/vnd.github+json' }
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/anthropics/claude-code/releases/latest' -Headers $headers
        if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v?(\d+\.\d+\.\d+)$') {
            throw 'GitHub returned an unsupported release.'
        }
        $latest = [version] $Matches[1]
        Write-Host "Installed: $installed; latest release: $latest; executable: $destination"
        if ($installed -ge $latest) { Write-Host 'Claude is already up to date.'; return }
        if ($Check) { Write-Host 'Update available. Run Update-Claude.ps1 without -Check to update all installations on PATH.'; return }
        $assets = @($release.assets | Where-Object name -eq 'claude-win32-x64.zip')
        if ($assets.Count -ne 1) { throw 'Release must contain exactly one claude-win32-x64.zip.' }
        $asset = $assets[0]
        if ($asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw 'Release asset has no usable SHA-256 digest.' }
        $expectedHash = $Matches[1]
        $expectedUrl = "https://github.com/anthropics/claude-code/releases/download/$($release.tag_name)/claude-win32-x64.zip"
        if ($asset.browser_download_url -cne $expectedUrl) { throw 'Unexpected release download URL.' }
        if (-not $PSCmdlet.ShouldProcess($destination, "Download, verify and install Claude $latest")) { return }
        try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw "Cannot acquire update lock '$lockPath'. Check permissions or wait for another update to finish. $($_.Exception.Message)" }
        # Another updater may have finished while metadata was being fetched.
        if ((Get-ClaudeVersion $destination) -ge $latest) { Write-Host 'Claude is already up to date.'; return }
        $temporary = Join-Path ([IO.Path]::GetTempPath()) "claude-update-$([guid]::NewGuid().ToString('N'))"
        $null = New-Item -ItemType Directory -Path $temporary
        $archive = Join-Path $temporary 'claude.zip'
        Invoke-WebRequest -Uri $expectedUrl -OutFile $archive -Headers $headers
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $expectedHash) { throw 'Archive SHA-256 mismatch; nothing was installed.' }
        # Extract only the executable; archive paths cannot escape the staging directory.
        $zip = [IO.Compression.ZipFile]::OpenRead($archive)
        try {
            $entries = @($zip.Entries | Where-Object { ($_.FullName -replace '\\', '/').Split('/')[-1] -ieq 'claude.exe' })
            if ($entries.Count -ne 1) { throw 'Archive must contain exactly one claude.exe.' }
            $source = Join-Path $temporary 'claude.exe'
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], $source)
        }
        finally { $zip.Dispose() }
        if ((Get-ClaudeVersion $source) -ne $latest) { throw 'Downloaded executable version does not match the release.' }
        Install-ClaudeExecutable -Source $source -Destination $destination -Version $latest
    }
    finally {
        if ($null -ne $temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
        if ($null -ne $lock) { $lock.Dispose() }
        # Keep the empty lock file: deleting it introduces a race with other updaters.
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Update-Claude @PSBoundParameters }
    catch { Write-Error $_ -ErrorAction Continue; exit 1 }
}
