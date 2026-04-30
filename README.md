# ToolFetcher (v3.0.0)

ToolFetcher is a PowerShell tool designed to fetch and manage a collection of DFIR and other GitHub tools. It streamlines the process of downloading, extracting, and organizing forensic utilities from various sources—whether by cloning Git repositories, downloading the latest releases via the GitHub API, or pulling specific files directly.

## Features

- **Multiple Download Methods:**  
  Supports various methods including:
  - `gitClone` – Downloads a repository using GitHub API (no Git dependency)
  - `latestRelease` – Downloads the latest release assets via the GitHub API
  - `branchZip` – Downloads a branch ZIP archive (without the `.git` folder)
  - `specificFile` – Downloads a specific file directly

- **Automated Extraction & Management:**  
  - Automatically extracts ZIP archives when applicable (Zip-Slip-safe)
  - Creates `.downloaded.json` marker files (SHA256 manifest) to track managed files
  - Preserves user modifications during updates; modified files are renamed `*.save1`/`save2`/...
  - Supports force re-download with complete directory overwrite
  - Skips tools that are already up-to-date (compares marker version to upstream tag/commit)

- **Parallel Downloads & Interactive TUI:**
  - `-Parallel` runs downloads concurrently via runspaces (PowerShell 7+; falls back to sequential on PS 5.1)
  - `-Interactive` launches a multi-select picker (Out-ConsoleGridView) with live local/remote version status
  - `-DryRun` previews what `-UpdateAll` will touch without writing anything

- **External YAML Configuration:**  
  ToolFetcher loads its tool configuration from one or more external YAML files that support:
  - Multiple download methods
  - Custom output folders
  - Asset type filtering (win64, win32, linux64, linux32, macos64, macos32, arm64, arm32)
  - Optional `Category` tags for the `-Tag` filter
  - Optional `ExpectedSha256` per-tool integrity pinning
  - Skip download options and placeholder/wishlist entries
  - Extraction control
  - Branch selection (or auto-detect via the repo's `default_branch`)
  - Local or remote YAML file support
  - Multi-file composition: `-tf tools.yaml,tool_groups/registry_analysis.yaml`

- **Enhanced Logging & Debugging:**  
  - Multiple log levels (Error, Warning, Info, Debug, Trace)
  - File logging with timestamps
  - Detailed debug output when enabled
  - Comprehensive error messages with troubleshooting guidance

- **GitHub Integration:**  
  - GitHub API rate limit handling
  - Secure token input options
  - PAT validation
  - Support for private repositories

## Requirements

- **PowerShell:**
  - **5.1+** for the standard CLI (download, update, list, dry-run).
  - **7+** required for `-Parallel` (concurrent downloads) and `-Interactive` (TUI). On PS 5.1, `-Parallel` falls back to sequential with a warning; `-Interactive` exits with a clear error.
- **Internet Connection:** Required for downloading tools and GitHub API access.
- **`powershell-yaml` Module:**  
  Required to parse YAML configuration files. The script offers to install it on first run (pinned version - see `$script:RequiredYamlVersion` in the script).
- **`Microsoft.PowerShell.ConsoleGuiTools` Module** *(only if using `-Interactive`)*:  
  The script offers to install it on first interactive launch.

## Configuration & Parameters

ToolFetcher uses a parameter-based approach for flexibility. Key parameters include:

- **`-ToolsFile` (alias `-tf`):**  
  Specifies one or more YAML configuration files (local paths or URLs).
  Accepts a comma-separated list - the resulting `tools` arrays are concatenated.
  The first file's `tooldirectory` wins; conflicting values produce a warning.  
  *Default:* `"tools.yaml"`  
  If a specified file is not found or unreachable, the script offers to fall back to:  
  ```text
  https://raw.githubusercontent.com/kev365/ToolFetcher/refs/heads/main/tools.yaml
  ```

- **`-ToolsDirectory` (alias `-td`):**  
  The directory where all downloaded tools will be stored.  
  *Example:* `C:\tools`  
  Resolution order: `-ToolsDirectory` parameter -> YAML `tooldirectory:` field ->
  the script's own folder (`$PSScriptRoot`). If a default is used, the script
  logs which path it picked. The directory itself is created lazily on the
  first download, so `-list` and `-DryRun` have no side effects.

- **`-ForceDownload` (alias `-force`):**  
  Forces a complete re-download of a tool by overwriting its existing directory.
  When used with `-UpdateAll`, it will update all downloaded tools, bypassing the skipdownload setting.

- **`-UpdateAll` (alias `-upall`):**  
  Updates all previously downloaded tools that have downloads enabled (skipdownload: false).
  Updates preserve user modifications by only removing managed files (tracked in .downloaded.json).

- **`-UpdateTools` (alias `-uptool`):**  
  Specify tool names to update (comma-separated). If a tool is not already downloaded, it will be downloaded.
  Updates preserve user modifications by only removing managed files (tracked in .downloaded.json).

- **`-VerboseOutput` (alias `-vo`):**  
  Enables detailed debug output for troubleshooting.

- **`-TraceOutput` (alias `-to`):**  
  Enables very detailed trace information (most verbose).

- **`-Log` (alias `-l`):**  
  Enables logging to a file in the tools directory.

- **`-GitHubPAT` (alias `-pat`):**  
  Optionally provide your GitHub Personal Access Token to avoid API rate limits.

- **`-PromptForPAT` (alias `-ppat`):**  
  Securely prompt for GitHub Personal Access Token (recommended over -GitHubPAT).

- **`-ListTools` (alias `-list`):**  
  Lists all available tools in the configuration file.

- **`-Tag <string[]>`:**  
  Filter the merged tool list to entries whose `Category` field matches one of the
  given tags (case-insensitive). Tools without a `Category` are excluded when this is set.

- **`-Parallel`:**  
  Run downloads concurrently. Requires PowerShell 7+. On PS 5.1 a warning is
  shown and execution falls back to sequential.

- **`-ThrottleLimit <int>`:**  
  Maximum concurrent downloads when `-Parallel` is set. Default: 4.

- **`-DryRun` (alias `-dry`):**  
  Show what would be downloaded/updated without writing anything. No network
  downloads, no file changes - useful for previewing `-UpdateAll`.

- **`-Interactive` (alias `-i`):**  
  Launch a TUI picker (`Out-ConsoleGridView`) showing every tool with its local
  version and the latest upstream version. Multi-select, then Enter to run the
  downloads through the parallel engine. Requires PowerShell 7+ and the
  `Microsoft.PowerShell.ConsoleGuiTools` module (offered for install on first run).
  Strongly recommend pairing with `-PromptForPAT` so the upfront status check
  doesn't hit GitHub's 60/hr unauthenticated limit.

## YAML Configuration

The YAML configuration file supports the following fields for each tool:

```yaml
Name: "ToolName"        # Tool identifier, also used to name the parent folder.
                        # Path separators and '..' are rejected.
RepoUrl: ""             # URL goes here. Plaintext http:// produces a warning.
DownloadMethod: ""      # Options: gitClone | latestRelease | branchZip | specificFile
                        # (case-insensitive; normalized at load)
OutputFolder: ""        # Relative subdirectory under -ToolsDirectory.
                        # Absolute paths and '..' are rejected.
Category: ""            # Optional tag used by the -Tag CLI filter
                        # (e.g. "registry", "memory"). Free-form string.
Branch: ""              # If omitted, the repo's default_branch is queried via
                        # the GitHub API at download time. Set explicitly to
                        # pin to a specific branch (e.g. "develop").
DownloadName: ""        # Exact filename match for latestRelease assets.
                        # Prefer AssetFilename (regex) for tools whose release
                        # filenames embed a version - DownloadName breaks
                        # silently when upstream bumps version.
AssetFilename: ""       # Regex match against latestRelease asset names.
                        # The first match wins.
AssetType: ""           # Options: win64 | win32 | linux64 | linux32 |
                        #          macos64 | macos32 | arm64 | arm32
SpecificFilePath: ""    # Used with the 'specificFile' DownloadMethod to
                        # specify file path in repository.
ExpectedSha256: ""      # Optional. If set, the downloaded file's SHA256 is
                        # verified against this value; mismatch fails the
                        # tool with no on-disk write. See Security
                        # Considerations.
Extract: true           # Whether to extract the downloaded ZIP (default: true)
SkipDownload: false     # Whether to skip downloading this tool (default: false)
```

**Placeholder entries** — a tool entry with `Name` set but `RepoUrl` and
`DownloadMethod` both empty is treated as a wishlist item: it passes
validation, appears in `-list` output as `[PLACEHOLDER]`, and is silently
skipped by the dispatcher. Useful for tracking tools you intend to add later.

## Tool Groups

The [`tool_groups/`](tool_groups/) directory contains curated YAML bundles
organized by analysis domain. Each file is a standalone tools list you can
load on its own or merge with others via the comma-separated `-tf` syntax.

| Group file | Focus |
| --- | --- |
| `_tool_template.yaml` | Field reference (not a real group) |
| `crypto_password_recovery.yaml` | CyberChef, hashcat, John the Ripper, KeeFarce |
| `disk_analysis.yaml` | Autopsy, ExifTool, INDXRipper, MFTECmd, Oletools, RustyUsn, WinPrefetchView, XstReader |
| `log_analysis.yaml` | APT-Hunter, chainsaw, EvtxECmd, EvtxHussar, hayabusa, hindsight, SumECmd |
| `memory_analysis.yaml` | capa, CobaltStrikeParser, MemProcFS, RdpCacheStitcher, Volatility2/3 |
| `miscellaneous.yaml` | Sysinternals, dnSpy, ILSpy, jadx, KAPE, OneDriveExplorer, sidr, VS Code, ... |
| `mobile_forensics.yaml` | ALEAPP, ILEAPP, mac_apt variants, plist_time_dump, WhatsApp Viewer |
| `network_analysis.yaml` | NetworkMiner, Wireshark |
| `nirsoft_tools.yaml` | Nirsoft utility collection |
| `registry_analysis.yaml` | AmCache-EvilHunter, RECmd, RegRipper3.0, ShellBagsExplorer |
| `wordlists.yaml` | rockyou, SecLists |
| `zimmerman_tools.yaml` | Eric Zimmerman's full .NET 6 tool collection |

To create your own group: copy `_tool_template.yaml`, fill in the entries,
and load it with `-tf my_group.yaml`. Multi-file load merges the `tools`
arrays from each file; the first file's `tooldirectory` wins.

## Usage Examples

1. **Basic Usage:**
   ```powershell
   .\ToolFetcher.ps1
   ```

2. **Custom Configuration:**
   ```powershell
   .\ToolFetcher.ps1 -tf "my_tools.yaml" -td "D:\DFIR\Tools"
   ```

3. **Update All Downloaded Tools:**
   ```powershell
   .\ToolFetcher.ps1 -upall
   
   .\ToolFetcher.ps1 -UpdateAll
   ```

4. **Update Specific Tools:**
   ```powershell
   # Comma-separated list with quotes
   .\ToolFetcher.ps1 -uptools "LECmd","JLECmd","KStrike"
   .\ToolFetcher.ps1 -UpdateTools "LECmd,JLECmd,KStrike"

   # Multiple parameters
   .\ToolFetcher.ps1 -UpdateTools RustyUsn -UpdateTools KStrike

   # Array syntax
   .\ToolFetcher.ps1 -UpdateTools @("RustyUsn","KStrike")
   ```

5. **Update All Tools (Bypass SkipDownload):**
   ```powershell
   .\ToolFetcher.ps1 -upall -force
   ```

6. **List Available Tools:**
   ```powershell
   .\ToolFetcher.ps1 -list
   ```

7. **Enable Logging:**
   ```powershell
   .\ToolFetcher.ps1 -l
   ```

8. **Use Remote Configuration:**
   ```powershell
   .\ToolFetcher.ps1 -tf "https://raw.githubusercontent.com/kev365/ToolFetcher/main/tools.yaml"
   ```

9. **Secure GitHub Token Input:**
   ```powershell
   .\ToolFetcher.ps1 -PromptForPAT
   ```

10. **Compose Multiple Tool Groups:**
    ```powershell
    # Merge curated bundles. tools arrays are concatenated.
    .\ToolFetcher.ps1 -tf tools.yaml,tool_groups\registry_analysis.yaml,tool_groups\memory_analysis.yaml -td "C:\dfir"
    ```

11. **Filter by Category Tag:**
    ```powershell
    # Only download tools whose YAML entry has Category: "registry"
    .\ToolFetcher.ps1 -Tag registry -td "C:\dfir"
    ```

12. **Preview an Update Without Writing:**
    ```powershell
    # Dry run - shows "[DRY-RUN] Would <method> tool: X -> path" for each candidate, no network downloads
    .\ToolFetcher.ps1 -upall -DryRun -td "C:\dfir"
    ```

13. **Parallel Downloads (PowerShell 7+):**
    ```powershell
    # 8-way concurrent download. On PS 5.1 falls back to sequential with a warning.
    .\ToolFetcher.ps1 -Parallel -ThrottleLimit 8 -PromptForPAT -td "C:\dfir"
    ```

14. **Interactive TUI (PowerShell 7+):**
    ```powershell
    # Multi-select picker with live local/remote version status.
    # Pair with -PromptForPAT - the upfront status check otherwise hits
    # GitHub's 60/hr unauthenticated rate limit fast.
    .\ToolFetcher.ps1 -Interactive -PromptForPAT -td "C:\dfir"
    ```

## Update Behavior

Each successful download writes a `.downloaded.json` marker file inside the
tool's folder. The marker captures version metadata plus a SHA256 manifest of
every file ToolFetcher placed there. This is what makes safe updates possible.

**On `-UpdateAll` / `-UpdateTools <names>`:**

1. **Skip up-to-date.** For `latestRelease` tools, the marker's `Version` is
   compared to GitHub's current `tag_name`. For `gitClone`/`branchZip`, the
   marker's `CommitHash` is compared to the branch HEAD. If they match, the
   tool is logged as up-to-date and skipped (no download). Use `-ForceDownload`
   to bypass.
2. **Remove only managed files.** When a re-download is required, ToolFetcher
   walks the marker's manifest and removes only the files whose SHA256 still
   matches what was originally written. User-added files in the same folder
   are untouched.
3. **Back up modified files.** If a managed file's SHA256 has changed since
   download (i.e. you edited it), it's renamed to `<name>.save1` (or `.save2`,
   `.save3`, ... if a backup already exists) instead of being deleted.
4. **Write fresh content.** The new download is staged in
   `%TEMP%/ToolFetcher_<pid>/<tool-name>/` (per-tool subfolder so concurrent
   downloads can't collide), copied into the output folder, and a new marker
   is written.

**On `-DryRun`:** the dispatcher logs what *would* happen but performs no
file removals, downloads, or marker writes. Useful for previewing
`-UpdateAll` against a large tool set.

**Force re-download (`-ForceDownload`):** wipes the output folder including
managed-file removal and ignores both the version-skip and the
`SkipDownload: true` flag (when combined with `-UpdateAll`).

## Error Handling

ToolFetcher provides comprehensive error handling and user guidance:

- YAML syntax validation with helpful error messages
- GitHub API error handling
- File system operation error handling
- Network connectivity error handling
- Detailed logging for troubleshooting

## Security Considerations

ToolFetcher downloads and writes binaries to your filesystem based on
configuration files you supply. A few things to keep in mind:

- **Remote YAML trust boundary.** When you pass `-ToolsFile <url>`, the URL's
  author fully controls *which* repos are downloaded, *which* binaries are
  installed, and (within the bounds of the path-traversal guard) *where on
  disk* they land. Treat any third-party URL as you would `curl | bash` and
  prefer pinning to a specific commit:
  ```
  -tf "https://raw.githubusercontent.com/<owner>/<repo>/<commit-sha>/tools.yaml"
  ```
  rather than `main`/`master`, so a future commit can't silently change what
  gets installed.
- **Optional `ExpectedSha256` per tool.** For high-trust tools you can pin a
  known-good SHA256 in the YAML entry; ToolFetcher will refuse to install
  anything that doesn't match. Recommended for `specificFile` and
  `latestRelease` methods, where the content of an asset URL can change
  silently.
- **Path traversal is rejected.** Tool `Name` and `OutputFolder` are validated
  at load time and at write time — entries containing `..`, absolute paths,
  or path separators in `Name` are refused so downloads can't escape your
  `-ToolsDirectory`.
- **TLS 1.2+ enforced.** The script raises `[Net.ServicePointManager]::SecurityProtocol`
  to TLS 1.2 at startup so PS 5.1 on older Windows builds doesn't fall back
  to TLS 1.0.
- **PAT scrubbing.** GitHub Personal Access Tokens (`ghp_...`, `github_pat_...`,
  classic 40-char hex) are redacted from log output before display or
  persistence.
- **Plaintext HTTP warning.** `RepoUrl` or `-ToolsFile` values starting with
  `http://` produce a warning at validation time. They still work but are
  vulnerable to tampering in transit.
- **Pinned dependency.** The `powershell-yaml` module is installed at a
  specific version (see `$script:RequiredYamlVersion` in the script) to
  protect against supply-chain compromise of that module.

## Future Considerations

- **Verify the v3 `AssetFilename` regex patterns against current releases.**
  Phase 4 converted 15 version-locked `DownloadName` entries to regex
  `AssetFilename` matchers (Autopsy, hashcat, CyberChef, capa, jadx,
  Microsoft-Analyzer-Suite, several DB Browser / RustyUsn variants, etc.)
  but each pattern was inferred from the previously hardcoded filename and
  has not been live-tested against the upstream's current asset naming.
  Some may need tuning when an upstream renames `64bit` to `x64` etc.

- **Persistent runspace pool for `-Parallel`.** The current implementation
  dot-sources `ToolFetcher.ps1 -SourceOnly` once per tool, which has
  startup overhead. A long-lived runspace pool with thread-local engine
  state would amortize that cost and meaningfully speed up large
  parallel runs.

- **Full multi-pane TUI.** The v3 `-Interactive` mode uses `Out-ConsoleGridView`
  - a single multi-select grid. A richer Terminal.Gui layout (tool list /
  details / live download queue / status bar with background update polling)
  was scoped in the Phase 8 plan but deferred in favor of shipping the
  simpler picker.

- **Additional Archive Formats:**
  Expand support beyond ZIP archives - `.7z` (hashcat, john) and `.tar.gz`
  (RustyUsn macOS/Linux assets) currently can't be extracted automatically.

- **Non-GitHub Support:**
  Current focus is primarily on GitHub-based downloads. Direct-URL
  downloads work via `specificFile`, but the version-comparison shortcut
  on `-UpdateAll` requires a GitHub API endpoint and so doesn't help
  non-GitHub assets like the Eric Zimmerman `.NET 6` zips.

- **Schema validation for YAML.** The current validator checks structural
  fields; a JSON-Schema-style validator would catch typos like
  `DownloadMethod: "latetsRelease"` before runtime.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.

## Author

Kevin Stokes

[Blog write-up](https://dfir-kev.medium.com/tool-fetcher-86691e65731b) · [LinkedIn Profile](https://www.linkedin.com/in/dfir-kev/) · [Buy me a coffee!](https://www.buymeacoffee.com/dfirkev)
