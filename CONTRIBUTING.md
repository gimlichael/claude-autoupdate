# Contributing

Bug reports, documentation fixes, and small, focused pull requests are welcome.

## Set up

Fork the repository on GitHub, clone your fork, and open the folder in PowerShell 7 on Windows x64. No package restore, npm install, or Pester installation is needed.

```powershell
git clone https://github.com/YOUR-USERNAME/claude-autoupdate.git
cd claude-autoupdate
git switch -c v1.0.0/describe-your-change
pwsh -NoProfile -File ./tests/Update-Claude.Tests.ps1
```

Replace `YOUR-USERNAME` with your GitHub account. Keep feature branches short-lived and open pull requests against `main`. After its initial empty seed commit, changes reach `main` through pull requests.

## Make a change

- Keep the standalone script dependency-free and compatible with PowerShell 7 on Windows x64.
- Follow the existing function names, four-space indentation, and explicit error handling.
- Preserve `-Check` and `-WhatIf` as read-only operations.
- Add a regression test for behavior changes, especially replacement, rollback, and partial failures.
- Update the README when commands, prerequisites, or behavior change.

## Validate

```powershell
pwsh -NoProfile -File ./tests/Update-Claude.Tests.ps1
```

Tests use temporary files and mock the GitHub and executable-execution boundaries. They exercise real hashing, ZIP extraction, backups, replacement, rollback, and multiple-installation handling without downloading Claude or modifying your installation. GitHub Actions runs the same command on Windows.

For an optional live metadata check, use `pwsh -NoProfile -File ./Update-Claude.ps1 -Check`. This requires an existing native Claude installation and internet access. Avoid running an actual update just to validate a documentation change.

Open a PR describing the problem, the resulting behavior, and the checks you ran. Report failures with the command, PowerShell version (`$PSVersionTable.PSVersion`), and redacted output. Remove usernames, private paths, tokens, and other personal information before posting.

Contributions are made under the repository's [MIT license](LICENSE). That license covers this updater; Claude Code remains governed by Anthropic's terms.
