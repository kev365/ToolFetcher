# ToolFetcher development tooling: checks, release, upstream audit, tests, CI

Date: 2026-11-04. Status: implemented 2026-11-05 on branch dev-tooling. Item 6 of the efficiency pass agreed on 2026-11-04.

## Intent

ToolFetcher is a single-file PowerShell script that must run on Windows PowerShell 5.1 and PowerShell 7+. Every change today is verified by hand with the four steps in CLAUDE.md, every release zip is assembled by hand, and the upstream audit of the tool definitions has been done twice (September and November 2026) with throwaway scripts outside the repo. This project turns those three recurring jobs into scripts that live in the repo, adds a unit test suite for the parts of the script that can be tested without the network, and runs the checks in GitHub Actions so regressions are caught on every push.

The why: the November pass found a dead URL scheme, a deleted repository, a renamed repository and an asset rename, none of which anything would have reported until a user hit them. The same pass spent most of its effort re-deriving verification steps that had been done by hand two months earlier.

## Goals

- One command runs everything CLAUDE.md asks for before a change is claimed to work, on both editions, and fails loudly.
- One command prepares a release: version bump, CHANGELOG heading, release zip identical in layout to the shipped 2.2.x zips, release notes, and the exact push and `gh release create` commands printed for the human to run.
- One command audits every tool definition against its upstream and reports what is broken, moved, archived, ambiguous or out of date, with an optional mode that downloads everything through ToolFetcher itself.
- A Pester test suite for the pure parts of the script, runnable locally on both editions and in CI.
- GitHub Actions runs the checks and tests on every push and pull request, and the upstream audit on a schedule.
- Repository hygiene files so line endings and analyzer rules no longer depend on each clone's settings.

## Non-goals

- No split of `ToolFetcher.ps1` into a module. Single-file distribution is a deliberate design and stays.
- No change in how tools are downloaded, verified or installed. Any refactor made for testability must be behavior-preserving and covered by the new tests.
- No automatic push, tag push or GitHub release from any script or workflow. CLAUDE.md requires explicit human approval for every push; the scripts stop at printing the commands.
- No network access in unit tests. Integration coverage comes from the audit script's download mode, run on demand or on a schedule.

## Anti-goals

- A CI pipeline that needs secrets beyond the default `GITHUB_TOKEN`.
- Flaky scheduled runs that cry wolf: the audit must distinguish "upstream broken" from "transient network error" and only fail on the former.
- Tooling that only works under PowerShell 7. The dev scripts themselves may require 7+, but everything they verify must be exercised under 5.1 as well.

## Constraints

From CLAUDE.md and the repository as it stands:

- `ToolFetcher.ps1` stays ASCII with no BOM, CRLF in the working tree, LF in the index. PSScriptAnalyzer 1.25.0 must report 0 findings; new suppressions need a stated reason.
- Functions used by validation or `-ListTools` must stay above the first `if (-not $SourceOnly)` gate. `-SourceOnly` dot-sources all 58 functions with no side effects beyond script-scope settings, and is the hook the tests use.
- `powershell-yaml` is pinned and imported with `-RequiredVersion` on branch `perf-hashing` (0.4.12); `main` at tag v2.2.2 still pins 0.4.7 and imports any installed version. The checks script and CI read the pin from `$script:RequiredYamlVersion` in the script under test and install exactly that version for both editions, so the tooling is correct on either tree.
- `Test-GitHubPAT` validates a token against `GET /user`, which an Actions `GITHUB_TOKEN` cannot call; a failed validation prompts with `Read-Host` and exits in a non-interactive runner. Nothing in CI may therefore pass `GITHUB_TOKEN` to `ToolFetcher.ps1` itself. The static audit makes its own API calls and is unaffected.
- `Format-RedactedMessage` only redacts the literal token when `$script:GitHubPAT` is set; tests that dot-source the script must set it through `Set-ToolFetcherRunState`.
- `Resolve-ToolsFileContent` resolves a relative `-ToolsFile` against the script folder, not the current directory; the dev scripts pass absolute paths.
- `-DryRun` with a fresh `-ToolsDirectory` makes no network calls (`Get-ToolPlan` returns before `Resolve-ToolRemote` when no marker exists), so the dry-run check is safe in CI without a token.
- Windows PowerShell 5.1 must be invoked with the call operator (`& powershell.exe ...`), never `Start-Process`, so it keeps its own module path.
- `docs/` is gitignored today because it holds the September audit report. This design file sits under `docs/superpowers/specs/` and is therefore not tracked until that rule changes (open question below).
- Only Pester 3.4 is present on the development machine; Pester 5 must be installed for the current user and in CI.
- The repository is public and GitHub Actions is enabled with all actions allowed.

## Decisions already made

These were decided in the conversation and are not open:

- Folder layout: dev scripts under `build/`, tests under `tests/`, workflows under `.github/workflows/`. The name `tools/` is avoided because "tools" means the downloaded products everywhere else in this repo.
- Test framework: Pester 5.x.
- CI: GitHub Actions on `windows-latest`, which carries both pwsh and Windows PowerShell.
- The upstream audit is written in PowerShell and reuses ToolFetcher's own YAML loading and validation through `-SourceOnly`, so it audits exactly what the script would run.
- Release artifacts go to `dist/`, which is added to `.gitignore`.
- Scripts print push, tag and release commands; they never execute them.

## Components

### 1. `build/Invoke-Checks.ps1`

Requires PowerShell 7. Runs, in order, and reports a pass/fail table at the end with a non-zero exit code on any failure:

1. Parse check with `[System.Management.Automation.Language.Parser]::ParseFile`.
2. Encoding check: ASCII only, no BOM, CRLF line endings on `ToolFetcher.ps1`.
3. PSScriptAnalyzer with the repo settings file; 0 findings required.
4. `-ListTools` under pwsh and under `& powershell.exe -NoProfile -ExecutionPolicy Bypass`; each must exit 0 and report `Total Tools: N`, where N is counted from `tools.yaml` by the script rather than hard-coded, so CLAUDE.md no longer carries a number to keep in sync.
5. `-ListTools -ToolsFile` for every file in `tool_groups/` (template excluded) under pwsh; each must exit 0.
6. `-DryRun` with `-ToolsDirectory` pointing at a fresh temp folder under both editions; exit 0 and nothing written.
7. `git status --porcelain` unchanged across the run.
8. Optional `-Pester` switch runs the test suite under both editions (component 4).

Parameters: `-SkipAnalyzer`, `-Pester`, `-Edition pwsh|desktop|both` (default both). Output: console table; `-OutJson` for CI.

### 2. `build/New-Release.ps1`

Requires PowerShell 7. `New-Release.ps1 -Version X.Y.Z [-Date yyyy-MM-dd]`:

1. Preconditions: clean working tree; CHANGELOG has a `## [Unreleased]` section with at least one bullet; `$script:Version` and the README title currently agree with each other; `Invoke-Checks.ps1` passes (skippable with `-SkipChecks` for a dry rehearsal only).
2. Bumps `$script:Version` and the README title, renames the Unreleased heading to `## [X.Y.Z] - date`, and re-runs the parse check.
3. Builds `dist/ToolFetcher-X.Y.Z.zip` from the working tree with the top-level `ToolFetcher/` folder and the exact file set shipped in 2.2.x: script, `tools.yaml`, every `tool_groups/*.yaml` including the template, README, CHANGELOG, LICENSE. Files keep CRLF, matching the 2.2.0 through 2.2.2 zips.
4. Verifies the zip: entry list equals the expected set, every entry's CR-stripped SHA256 equals the working-tree file's CR-stripped SHA256, and the script inside reports the new version.
5. Writes `dist/release-notes-X.Y.Z.md`: the new CHANGELOG section plus the standard "Full changelog" link.
6. Prints, without running them: the suggested commit command for the release commit, the merge-to-main step if not on main, `git tag -a vX.Y.Z -m "ToolFetcher X.Y.Z"`, `git push --dry-run` for main and the tag, and the `gh release create` line with the zip and notes file.

The script never commits, tags, pushes or publishes. `-WhatIf` support via `SupportsShouldProcess` for the file edits.

### 3. `build/Test-ToolDefinitions.ps1`

Requires PowerShell 7. The upstream audit, replacing the throwaway bash scripts.

Input: `tools.yaml` and every `tool_groups/*.yaml` by default, or `-ToolsFile`. Entries are loaded and validated with ToolFetcher's own functions via `-SourceOnly`, then de-duplicated by the fields that affect a download (`RepoUrl`, `DownloadMethod`, `Branch`, `DownloadName`, `AssetFilename`, `AssetType`, `SpecificFilePath`), so a tool that appears in the main file and two groups is checked once.

Checks per unique entry, with results of `ok`, `warn`, `broken`, `skipped` or `transient`:

- GitHub repositories: exists; `full_name` differs from the URL (moved or renamed, case-insensitive compare); archived; last push date.
- `latestRelease`: latest tag and date; the entry's selector applied exactly as the script applies it (`DownloadName` exact, `AssetFilename` with `-match`, `AssetType` with the script's `$script:AssetPatterns`), reporting no match as `broken`, more than one match as `warn` with the list, and a first match ending in `.asc`, `.sig` or `.sha256` as `broken`.
- `branchZip` and `gitClone`: the branch exists; last commit date; default branch if different.
- `specificFile` and non-GitHub URLs: ranged GET (`Range: bytes=0-0`), following redirects, reporting status, final URL, size and Last-Modified; `text/html` where a binary is expected is `broken`. HEAD is not used because some fronts (download.ericzimmermanstools.com) answer HEAD with 404.
- Version-locked URLs (a version number embedded in the URL): flagged `warn` with the version so a human can check for a newer one. ExifTool additionally compares against `https://exiftool.org/ver.txt`.
- Entries with `SkipDownload: true` are listed with their comment and still probed, reported as `skipped` (never fail the run), so a placeholder that becomes fetchable is noticed.
- Network failures and 5xx are retried once and then reported as `transient`, which does not fail the run.
- Status rules: a repository that redirects to a new name is `warn` (the download still works, but every run pays the redirect and the entry should be updated); an archived repository is `warn`; a missing repository, branch or asset, a selector that matches nothing or a signature file first, and an HTML page where a binary was expected are `broken`. With these rules all 78 current entries come out `ok`, `warn` or `skipped`.

Authentication: `-GitHubPAT`, else `GH_TOKEN`, else `GITHUB_TOKEN` environment variables, else anonymous with a warning about the 60-per-hour limit. The token is never written to output or files.

Output: console table sorted broken first; `-OutFile path.json` with the full record per entry; exit code 1 when any live entry is `broken`.

`-Download` switch: after the static audit, runs `ToolFetcher.ps1` once per YAML file into a temp directory (`-Log`, PAT passed through) and appends each run's summary and failures to the report. This is the end-to-end verification done by hand in November; it moves several gigabytes and is a local, manual mode only. It is not offered from the Actions workflow, because `ToolFetcher.ps1` cannot authenticate with the runner's `GITHUB_TOKEN` (see constraints) and an anonymous run of 78 entries would exceed the 60-per-hour limit and report false failures.

Acceptance test: a committed fixture `tests/fixtures/audit-regressions.yaml` holds entries reproducing the breakages found by hand in September and November: the Eric Zimmerman `net9/` URL (404), `DownloadName: "APT-Hunter.zip"` (asset renamed), `acquiredsecurity/forensic-timeliner` (repository deleted), `Neo23x0/Loki2` (repository renamed), ExifTool 13.59 (newer version available). The audit must report each with the expected status. The v2.2.1 tag is not used as the fixture: Loki2 only entered the definitions in 2.2.2, already under its new name.

### 4. Pester tests under `tests/`

Pester 5, one file per area, each dot-sourcing `ToolFetcher.ps1 -SourceOnly` in `BeforeAll`. Must pass under both editions. No network; anything that would touch the network is mocked or avoided.

- `Validation.Tests.ps1`: `Test-ToolEntry` and `Test-ToolConfiguration` accept every shipped YAML file; reject names with path separators or `..`, absolute `OutputFolder`, `http://` warning, unknown `DownloadMethod`, `specificFile` on GitHub without `SpecificFilePath` or `DownloadName`; placeholder detection (`Test-PlaceholderEntry`) and tag matching (`Test-ToolHasTag`).
- `AssetSelection.Tests.ps1`: given a fake release asset list, `DownloadName` selects exactly by name, `AssetFilename` uses `-match`, `AssetType: win64` requires a Windows marker plus x64 and rejects arm64, Linux and macOS, the first match wins. This needs the selection logic extracted from `Resolve-ToolRemote` into a small function (for example `Select-ReleaseAsset`) with identical behavior; that refactor is part of this work and is the only change to script logic the project makes.
- `Hashing.Tests.ps1`: `Get-FileHashHex` equals `Get-FileHash` for SHA256 and MD5 on small, empty and multi-megabyte files; `Get-ManifestEntryAlgorithm` returns MD5 for 32-character digests and SHA256 for 64; `ConvertTo-ManifestTable` round-trips a marker.
- `ZipSafety.Tests.ps1`: `Expand-ZipSafely` extracts a normal zip and refuses entries with `..` or absolute paths, using zips built in `TestDrive:` with `System.IO.Compression`.
- `Paths.Tests.ps1`: `Initialize-OutputFolder` rejects traversal and drive-prefixed folders and creates nested relative ones under the tools directory.
- `Redaction.Tests.ps1`: `Format-RedactedMessage` removes classic and fine-grained PAT shapes from messages, URLs and exception text.
- `Retry.Tests.ps1`: `Invoke-WithRetry` does not retry on 404 or 403, retries on 500 and on connection errors with the configured delays (delays set to 0 in tests), honours a short Retry-After on 429, and gives up after the maximum.
- `Intact.Tests.ps1`: `Test-ToolIntact` is true for an untouched install, false when a managed file is modified or missing, and ignores user-added files.
- `Markers.Tests.ps1`: `Write-MarkerFile` then `Get-ToolMarker` round-trips every field including `HashAlgorithm`; a 2.1-style MD5 manifest is read correctly.

### 5. GitHub Actions

`.github/workflows/checks.yml`, on push and pull request to any branch:

- `windows-latest`; install `powershell-yaml` at the version read from the script's `$script:RequiredYamlVersion`, PSScriptAnalyzer 1.25.0 and Pester 5 for the current user under both editions (`-SkipPublisherCheck` is needed because the inbox Pester 3.4 carries a different publisher certificate); run `build/Invoke-Checks.ps1 -Pester -OutJson`; upload the JSON as an artifact. Action versions pinned to a major version tag.

`.github/workflows/upstream-audit.yml`, on `schedule` (monthly) and `workflow_dispatch`:

- Runs the static `build/Test-ToolDefinitions.ps1 -OutFile` with the default `GITHUB_TOKEN` (used only for the audit's own API calls, never passed to `ToolFetcher.ps1`); uploads the report; fails the run only on `broken`. No download mode in Actions.

### 6. Repository hygiene

- `.gitattributes`: `* text=auto` plus `eol=crlf` for `*.ps1`, `*.psd1`, `*.yaml`, `*.md`, `*.txt` and an explicit `LICENSE text eol=crlf` (the file has no extension and ships in the zip), so checkout is CRLF on every clone regardless of `core.autocrlf`, and binary rules for zips. Index content is already LF, so `git add --renormalize .` must produce no changes; the builder verifies that before committing.
- CHANGELOG: the tooling gets an `### Added` bullet under `[Unreleased]` even though `build/` and `tests/` are not in the release zip, because `New-Release.ps1` requires an Unreleased bullet and contributors should see the change.
- `.editorconfig`: UTF-8, CRLF, final newline, trim trailing whitespace, 4-space indent for `.ps1`, 2-space for `.yaml`.
- `PSScriptAnalyzerSettings.psd1`: severity all, default rules, no exclusions; `Invoke-Checks.ps1` passes it with `-Settings`. Existing inline suppressions stay.
- `.gitignore`: add `dist/` and `tests/TestResults/`.
- CLAUDE.md: "Verifying changes" becomes "run `build/Invoke-Checks.ps1 -Pester`" with the manual steps kept as the fallback; release and audit sections point at the two scripts; the tool-count sentence goes away.

## Left to the builder

- Exact parameter names, table formatting and JSON schema of the three scripts.
- How `Select-ReleaseAsset` is factored out of `Resolve-ToolRemote` (it must stay above the first `-SourceOnly` gate only if validation or `-ListTools` use it; today they do not).
- Pester 5 minor version to pin in CI; which `actions/checkout` and `actions/upload-artifact` majors.
- Whether the audit workflow opens an issue on failure or only fails the run (default: only fails).
- Test fixtures: small zips and YAML snippets generated in `TestDrive:` rather than committed binaries.

## Calls made by the author after the builder check

- `-Download` stays a local mode and is not exposed in Actions (reason in the constraints). Making `Test-GitHubPAT` accept installation tokens is a reasonable separate fix but is out of this project's scope.
- Renamed and archived repositories are `warn`, not `broken`.
- The audit's regression fixture is a committed YAML file, not the v2.2.1 tag.
- CI reads the YAML module pin from the script rather than hard-coding a version.
- The tooling gets its own CHANGELOG bullet under Added.
- `LICENSE` gets an explicit line-ending attribute.

## Owner decisions (approved 2026-11-05; defaults applied where no answer was given)

1. Order of work: the tooling is built on a branch off `perf-hashing`, so it targets the 0.4.12 pin and the current CHANGELOG. Whether `perf-hashing` ships as 2.2.3 before the tooling merges, or both ship together, is decided when the owner approves that release; the author's recommendation remains to release 2.2.3 first.
2. Specs are tracked: `.gitignore` changes `docs/` to `docs/*` with `!docs/superpowers/`, so the September audit report stays ignored and `docs/superpowers/` is committed.
3. `New-Release.ps1` prints the commit, tag, push and release commands and never runs them.
4. The checks workflow runs on every push and on pull requests.
5. The upstream audit runs monthly and on manual dispatch.

## Acceptance

- `pwsh -File build/Invoke-Checks.ps1 -Pester` passes on the branch it is built on and on `main` once merged, and replaces the manual CLAUDE.md steps.
- The release zip is accepted through the clone-based build-and-verify test (`tests/Build.NewRelease.Tests.ps1` builds the zip from a clone with `New-ReleaseZip` and verifies it with `Test-ReleaseZip`) together with a comparison of the zip's entry list and CR-stripped hashes against the published 2.2.2 asset for the same tree. A rehearsal `New-Release.ps1 -Version X.Y.Z -WhatIf` on a throwaway branch writes nothing (no zip, no notes, no version edits), leaves `[Unreleased]` intact, and prints commands that, when a human runs them, reproduce the 2.2.2 release flow exactly.
- `Test-ToolDefinitions.ps1` reports every entry in `tests/fixtures/audit-regressions.yaml` with its expected status and reports all 78 current entries as `ok`, `warn` or `skipped`.
- The Pester suite is green under pwsh 7.6 and Windows PowerShell 5.1 locally and in Actions.
- PSScriptAnalyzer still reports 0 findings for `ToolFetcher.ps1` and for every script under `build/`.
