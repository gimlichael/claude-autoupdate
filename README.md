# Claude AutoUpdate

[![MIT license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Windows x64](https://img.shields.io/badge/Windows-x64-0078D4.svg)](#requirements)
[![PowerShell 7](https://img.shields.io/badge/PowerShell-7%2B-5391FE.svg)](#requirements)

**Update every native Claude Code installation on your PATH with one command.**

When the WinGet catalog trails an [official Claude Code release](https://github.com/anthropics/claude-code/releases), skip the manual download, extraction, and executable copying. This small PowerShell script downloads `claude-win32-x64.zip` from Anthropic's latest GitHub release and updates your existing executables, including installations reached through WinGet links.

- Finds all native installations on PATH and updates each resolved target once.
- Verifies the archive's SHA-256 digest and the executable's reported version.
- Keeps a backup per installation and attempts rollback if verification fails.
- Offers read-only checks and previews, with no extra PowerShell modules to install.

Independent community tool; not affiliated with or endorsed by Anthropic.

## Quick start

In PowerShell 7:

```powershell
git clone https://github.com/gimlichael/claude-autoupdate.git
cd claude-autoupdate
pwsh -NoProfile -File ./Update-Claude.ps1 -Check
```

Close your Claude sessions, then update **all** native installations on PATH:

```powershell
pwsh -NoProfile -File ./Update-Claude.ps1
```

Already cloned it? Use `git pull --ff-only` to get the latest updater before running it.

### Download just the script

Tagged [GitHub Releases](https://github.com/gimlichael/claude-autoupdate/releases) provide `Update-Claude.ps1` as a standalone asset, with its MIT notice included. Download it, open PowerShell 7 in that folder, and use the same commands above. No clone is needed.

For development snapshots, open a successful [PR Flow run](https://github.com/gimlichael/claude-autoupdate/actions/workflows/pr.yml) and download its `Update-Claude-snapshot-<run>.<attempt>-<commit>` artifact. The ZIP contains only `Update-Claude.ps1`. CI artifacts expire after 30 days and require a GitHub login to download; release assets remain available until removed.

## Requirements

- Windows x64 and PowerShell 7 (`pwsh`), rather than Windows PowerShell 5.1.
- An existing native `claude.exe` on PATH, or its full path supplied with `-Path`.
- Internet access to GitHub's API and release downloads.
- Write access to the installation folders. Protected folders may require an administrator shell.

This tool updates existing executables; it is not a first-time Claude installer. It targets `claude.exe`, rather than npm's `claude.cmd` or `claude.ps1` shims.

## Commands

| Command | Behavior |
| --- | --- |
| `./Update-Claude.ps1` | Update every distinct native installation on PATH. |
| `./Update-Claude.ps1 -Check` | Show installed and latest versions without writing files. |
| `./Update-Claude.ps1 -WhatIf` | Preview each replacement without downloading or changing files. |
| `./Update-Claude.ps1 -Path "$HOME/.local/bin/claude.exe"` | Update one specific installation. |
| `Get-Help ./Update-Claude.ps1 -Detailed` | Read the script's built-in help. |

You can combine `-Path` with `-Check` or `-WhatIf`. Symbolic links, including WinGet links, are followed to their actual executable. Installations already at or above the latest release are left alone.

### Run it from any directory

From your cloned repository, generate a function you can paste into your PowerShell profile (`$PROFILE`):

```powershell
$updater = (Resolve-Path ./Update-Claude.ps1).Path.Replace("'", "''")
"function Update-Claude { & '$updater' @args }"
```

Once saved in your profile, open a new PowerShell 7 session and run:

```powershell
Update-Claude -Check
Update-Claude
```

Keep the clone in that location; moving it requires updating the profile function.

## How updates work

For each installation, the updater reads the executable's version and queries the latest stable GitHub release. When a newer version exists, it verifies the download against the SHA-256 digest in GitHub's release metadata, extracts only `claude.exe`, and checks its version before staging it beside the destination.

The replacement retains the previous executable as `claude.exe.<unique-id>.bak` in the same folder. If the installed executable fails its version check, the updater attempts to restore that backup. If rollback also fails, the error identifies the backup to restore manually. Keep backups until you have confirmed the update works, then remove those you no longer need. An empty `claude.exe.update.lock` file remains to coordinate concurrent invocations.

Each installation has its own download and backup. If one fails, the script attempts the others, retains successful updates, and exits with code `1` listing the failures. A successful run, check, or preview exits with code `0`.

The updater does not change PATH, WinGet's package inventory, scheduled tasks, or Claude's built-in update notification. WinGet may still report its recorded package version. Hash verification trusts the official GitHub repository and metadata; the separate PGP signature is not verified.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| `pwsh` is not recognized | Install PowerShell 7 and open a new terminal. |
| No `claude.exe` found | Run `where.exe claude`, then supply `-Path` to a native executable. npm shims are not supported targets. |
| Access denied or replacement failed | Close Claude sessions, check folder permissions, and use an administrator PowerShell session if that installation requires it. |
| Cannot acquire update lock | Wait for another updater to finish and check directory permissions. The empty lock file's presence alone does not mean it is locked. |
| GitHub API or download failed | Check connectivity, proxy settings, and the reported HTTP error. For API rate limits, wait before retrying. |
| SHA-256 or version mismatch | The download was rejected before installation. Retry later; report persistent failures with redacted output. |

The script never elevates itself or terminates Claude processes. If your execution policy blocks scripts, follow your organization's PowerShell policy rather than changing machine-wide settings just for this tool.

## Contribute

Fork it, make a focused change, and open a PR against `main`. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow. There are no dependencies to restore; run the isolated tests on Windows x64:

```powershell
pwsh -NoProfile -File ./tests/Update-Claude.Tests.ps1
```

Tests use temporary fixtures without downloading Claude or changing your installed executables. [PR Flow](.github/workflows/pr.yml) runs the same suite on Windows for PRs targeting `main` and manual checks, then uploads a snapshot. [Release Flow](.github/workflows/release.yml) independently tests pushed release tags and publishes the tested script. Both use Codebelt's `git-checkout` action and require no repository secrets. Codebelt's shared .NET test workflows do not apply to this standalone PowerShell script.

Found a bug or have an idea? [Open an issue](https://github.com/gimlichael/claude-autoupdate/issues). If this saves you a few clicks, a star helps other Windows developers find it.

## License

[MIT](LICENSE), copyright (c) 2026 gimlichael. The license applies to this updater; Claude Code remains governed by Anthropic's terms.
