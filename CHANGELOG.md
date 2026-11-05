# Changelog

All notable changes to ToolFetcher. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- File hashing (`Get-FileHashHex`) reads through a 64 KB stream buffer instead of 1 MB. Hash output is unchanged; manifests after extraction and the managed-file checks on `-UpdateAll` are about 2x faster on PowerShell 7 and 5x to 6x faster on Windows PowerShell 5.1 for many-file tools (5,084-file tree: 12.3 s to about 2 s on 5.1).
- `powershell-yaml` is pinned to 0.4.12 (cloudbase, published 2025-01-23) instead of 0.4.7, and the pin is now enforced: the module is imported with `-RequiredVersion`, where before any installed version was loaded and the pin only applied to a fresh install. The newer build imports about 1 s faster on PowerShell 7. When the pinned version is missing the script offers to install it for the current user, side by side with other versions.

### Tool definitions

- aleapp and ileapp follow the `windows-x64-portable` release zips instead of the `main` branch zips; the ILEAPP branch zip had grown to 348 MB of source and test data, and the portable builds need no Python.

## [2.2.2] - 2026-11-03

### Tool definitions

- Added the two Eric Zimmerman tools that were missing, `bstrings` and `SrumECmd` (.NET 10 builds), to `tools.yaml` and the `zimmerman_tools` group; `SrumECmd` also joins `log_analysis`. The configuration now carries all 29 tools on the official download page.
- APT-Hunter: release V4.0 (2026-09-20) ships a single `APT-Hunter.exe` instead of `APT-Hunter.zip`; `DownloadName` updated in `tools.yaml` and `log_analysis` (the old name failed with "No matching asset").
- Forensic Timeliner: `acquiredsecurity/forensic-timeliner` was deleted from GitHub without a redirect; the entry now follows `AndrewRathbun/forensic-timeliner`, a mirror that carries the full v2.3 history.
- ExifTool bumped from the version-locked 13.59 to 13.60.
- Hashcat and Autopsy `AssetFilename` patterns are anchored with `$` so the `.7z.asc` and `.msi.asc` signature files can never be selected (the script takes the first `-match`, which only worked because the archive is listed first).
- Every entry in `tools.yaml` and the group files was checked against its upstream on 2026-11-02 and downloaded end to end with ToolFetcher; the `# confirmed` comments carry that date. Still skipped, with a refreshed note: RegistryScanner (repository still gone), DB Browser for SQLCipher (still no Windows build), the NirSoft bundle (URL now redirects to a 403 page).

## [2.2.1] - 2026-11-02

### Tool definitions

- Eric Zimmerman tools moved from the retired `net9` builds to the .NET 10 builds, published under `net/` on download.ericzimmermanstools.com; the `net9/` paths now return 404. hasher and XWFIM are no longer offered as .NET 4 builds at the site root, and TimeApp is switched to its `net/` build as well, so every Zimmerman entry needs the .NET 10 runtime. All 27 entries were checked on 2026-11-02.

## [2.2.0] - 2026-09-16

### Added

- `-Tag` filters entries by `Category`; every `tool_groups` file carries a file-level `category:` (an entry may override it with one tag or a list).
- `-DryRun` (alias `-dry`) previews a run without writing anything. In update mode it makes read-only metadata requests so the preview can say "up to date" or "would update".
- `-Parallel` and `-ThrottleLimit` download several tools at once on PowerShell 7+. Metadata is resolved serially first; Windows PowerShell 5.1 warns and runs sequentially.
- Up-to-date detection for `-UpdateAll` and `-UpdateTools`: a tool is skipped when its release tag, commit, or upstream ETag is unchanged **and** every managed file is intact. Checks use conditional requests, which cost no API quota. `-ForceDownload` re-downloads regardless.
- `ExpectedSha256` is honoured by every download method, including `gitClone`.
- Run summary at the end of every run; exit code `1` when any tool failed or was skipped because of a rate limit.
- Rate-limit awareness: `X-RateLimit-*` and `Retry-After` are read, a hit stops further API calls with a reset time and a `-PromptForPAT` hint, and 5xx/network errors are retried with backoff.
- Repositories that moved are followed with the token intact and reported with a WARNING that names the new location.
- Default branch is resolved through the API with a quota-free fallback (codeload probe of `main` then `master`).
- `DownloadName` on a `specificFile` entry names the saved file, which makes vendor "latest" links usable (for example the Visual Studio Code stable installer).
- Marker files (`.downloaded.json`) record `Branch`, `HashAlgorithm`, `ApiETag`, `RemoteETag`, `RemoteLastModified`, and `RemoteLength`.
- `CHANGELOG.md` (this file).

### Changed

- With no `tooldirectory:` and no `-ToolsDirectory`, tools are downloaded next to the script and a WARNING says so; the interactive prompt is gone. Relative `-ToolsDirectory` paths resolve against the current location.
- Marker manifests use SHA256 digests. Markers written by 2.1 (MD5) are still read and are replaced on the next update without spurious backups.
- Managed-file cleanup is keyed by path: only files at their manifest path are managed, so a managed file a user renamed inside the tool folder is left alone.
- Downloads are staged under `%TEMP%\ToolFetcher_<PID>\<tool>` and cleaned up; several instances can run at once. Staged content is moved into place instead of copied.
- The previous install is removed only after the new download has been staged and verified, so a failed download never leaves a half-empty tool.
- `AssetType` patterns require a platform marker: `win64` needs a Windows name plus x64/amd64/x86_64 and rejects arm64, Linux, and macOS builds. Use `AssetFilename` when a release ships several matching builds.
- Placeholder entries are those with a `Name` but no `RepoUrl` **or** no `DownloadMethod`; they are listed as `[PLACEHOLDER]` and skipped instead of failing validation for the whole file.
- Every `Invoke-WebRequest` uses `-UseBasicParsing` and a timeout, sends a `ToolFetcher/<version>` user agent, and hides the progress bar (Windows PowerShell installs are about 7x faster).
- The YAML module is imported before the module path is scanned; the log level enum no longer needs a C# compile; remote YAML is fetched with one request.
- Placeholders in `-ListTools -vo` show their `Category`; the help text and README document every parameter, alias, YAML field, and exit code.
- PSScriptAnalyzer reports no findings.

### Fixed

- Updating an install made by 2.1 renamed every managed file to `.save1` because MD5 manifests were compared as SHA256.
- `-Parallel` aborted before processing any tool and still exited `0`.
- A failed update download wiped the previous version of the tool.
- The GitHub token was dropped when the API answered with a redirect for a moved repository, so those lookups ran against the anonymous 60-requests-per-hour limit.
- On a patched Windows PowerShell 5.1 (CVE-2025-54100), `Invoke-WebRequest` without `-UseBasicParsing` prompted and non-interactive runs failed.
- `-Tag` could never match because no entry had a `Category`.
- `-DryRun -Log` created the tools directory.
- A token inside a URL or exception message could reach the log file.
- Log writes from parallel runspaces were not synchronised.
- Verbose and trace output was lost inside parallel runspaces.
- Two managed files with identical content collapsed into one manifest entry.
- A `RepoUrl` with a trailing slash produced `//releases/latest`.
- A quoted comma-separated `-ToolsFile` value was not split.
- The file count printed after a `gitClone` download was empty.
- Alias `-uptools` was documented as `-uptool`.
- Four group files (miscellaneous, network_analysis, nirsoft_tools, wordlists) could not be loaded because reference entries without a download method failed validation.
- `AssetType: win64` selected Linux builds for hayabusa and EvtxHussar.

### Tool definitions

- Eric Zimmerman tools moved from the retired `net6` builds to `net9` (PR #9 by stark4n6). The `net9` builds need the .NET 9 runtime.
- Every entry was checked against its upstream on 2026-09-16 and carries a `# confirmed 2026-09-16` comment; asset choices default to Windows x64 builds.
- Moved repositories updated: chainsaw (WithSecureOpenSource), hindsight (RyanDFIR), steghide (StegHigh), dnSpy (dnSpyEx, the maintained fork).
- Version-locked asset names in `tools.yaml` replaced by regular expressions (INDXRipper, MemProcFS-Analyzer, Microsoft-Analyzer-Suite, RdpCacheStitcher, RustyUsn, Windows MBox Viewer, XstReader).
- Fixed or completed entries: CyberChef, ILSpy (v11 asset names), john (openwall.com Windows build), Radare2, vol2 (2.6.1 Windows standalone), CobaltStrikeParser and OfficeMalScanner (branch zips), WhatsApp-Viewer, SecLists, ExifTool, Visual Studio Code, hayabusa, XstReader (2.x app), and the NirSoft utilities (direct x64 zips). aleapp, ileapp and plist_time_dump follow their `main` branch.
- Set to `SkipDownload: true` with a dated reason: RegistryScanner (repository gone), DB-Browser-SQLCipher (no Windows build), Nirsoft Utilities bundle (needs a referer and is password-protected). All placeholder entries are `SkipDownload: true`.

## [2.1.2] - 2025-05-22

- Documentation and tool definition updates.

## [2.1.1] - 2025-03-17

- Added `-UpdateAll`; `-UpdateTools` accepts multiple tools reliably.
- `-ListTools` no longer requires a tools directory.

## [2.0.1] - 2025-03-08

- Fixed parameter alias conflicts (`-GitHubPAT`, `-PromptForPAT`, `-Log`) and empty `tooldirectory` validation; clearer aliases.

## [2.0.0] - 2025-03-02

- Major update: new download methods and asset handling, improved logging and error handling, PAT security, validation of the YAML configuration, and preservation of user files in tool folders.

## [1.2.2] - 2025-02-16

- Housekeeping release.

## [1.2.0] - 2025-02-12

- First tagged release.

[2.2.0]: https://github.com/kev365/ToolFetcher/compare/v2.1.2...v2.2.0
[2.1.2]: https://github.com/kev365/ToolFetcher/compare/V2.1.1...v2.1.2
[2.1.1]: https://github.com/kev365/ToolFetcher/compare/v2.0.1...V2.1.1
[2.0.1]: https://github.com/kev365/ToolFetcher/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/kev365/ToolFetcher/compare/v1.2.2...v2.0.0
[1.2.2]: https://github.com/kev365/ToolFetcher/compare/v1.2.0...v1.2.2
[1.2.0]: https://github.com/kev365/ToolFetcher/releases/tag/v1.2.0
