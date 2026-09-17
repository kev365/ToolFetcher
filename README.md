# ToolFetcher (v2.2.0)

ToolFetcher is a PowerShell tool designed to fetch and manage a collection of DFIR and other GitHub tools. It streamlines the process of downloading, extracting, and organizing forensic utilities from various sources—whether by cloning Git repositories, downloading the latest releases via the GitHub API, or pulling specific files directly.

## Features

- **Multiple Download Methods:**  
  Supports various methods including:
  - `gitClone` – Downloads a repository using GitHub API (no Git dependency)
  - `latestRelease` – Downloads the latest release assets via the GitHub API
  - `branchZip` – Downloads a branch ZIP archive (without the `.git` folder)
  - `specificFile` – Downloads a specific file directly

- **Automated Extraction & Management:**  
  - Automatically extracts ZIP archives when applicable (Zip-Slip safe)
  - Creates `.downloaded.json` marker files to track managed files
  - Preserves user modifications during updates (changed files are kept as `.save1`, `.save2`, ...)
  - Skips tools that are already up to date (release tag, commit, or upstream ETag) after verifying the installed files
  - Never removes an installed tool until its replacement has been downloaded and extracted
  - Force re-download with `-ForceDownload`

- **External YAML Configuration:**  
  ToolFetcher loads its tool configuration from one or more YAML files that support:
  - Multiple download methods
  - Custom output folders
  - Asset type filtering (win64, win32, linux64, linux32, macos64, macos32, arm64, arm32) or regex asset names
  - Skip download options
  - Extraction control
  - Branch selection
  - Local or remote YAML files, merged when several are given
  - Category tags for selective runs (`-Tag`)
  - Optional SHA256 pinning per tool (`ExpectedSha256`)

- **Enhanced Logging & Debugging:**  
  - Multiple log levels (Error, Warning, Info, Debug, Trace)
  - File logging with timestamps
  - Detailed debug output when enabled
  - Run summary at the end and a non-zero exit code when any tool failed
  - GitHub tokens are scrubbed from all log output

- **GitHub Integration:**  
  - Conditional API requests: checking an unchanged tool costs no rate-limit quota
  - Clear rate-limit diagnosis with the reset time, plus retries with backoff on transient errors
  - Secure token input options and PAT validation
  - Support for private repositories

- **Parallel Downloads (PowerShell 7+):**  
  `-Parallel` downloads several tools at once (`-ThrottleLimit`, default 4). Metadata is resolved serially first, then only the downloads run in parallel. On Windows PowerShell 5.1 the script warns and runs sequentially.

## Requirements

- **PowerShell:** Windows PowerShell 5.1 or PowerShell 7+
- **Internet Connection:** Required for downloading tools and GitHub API access
- **powershell-yaml Module:**  
  This module is required to parse the YAML configuration files. The script imports it if installed and otherwise offers to install a pinned version (0.4.7).
- **.NET 9 runtime:** the Eric Zimmerman tools in the shipped configuration are the `net9` builds.

## Getting Started

1. Download `ToolFetcher-<version>.zip` from the [latest release](https://github.com/kev365/ToolFetcher/releases/latest) and extract it. The zip holds `ToolFetcher.ps1`, `tools.yaml` and the `tool_groups\` folder together, so the default configuration is found next to the script.
2. If Windows marks the extracted files as downloaded from the internet, unblock them once:

   ```powershell
   Get-ChildItem -Path .\ToolFetcher -Recurse | Unblock-File
   ```

3. If your execution policy blocks unsigned scripts (the default on Windows PowerShell 5.1 is `Restricted`), allow them for the current session only:

   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
   ```

   This lasts until the window is closed and changes nothing on the machine. Alternatively, launch a one-off run with `powershell.exe -ExecutionPolicy Bypass -File .\ToolFetcher.ps1 ...`.

4. Run the script from the extracted folder, pointing `-ToolsDirectory` at where the tools should go:

   ```powershell
   .\ToolFetcher.ps1 -ToolsDirectory "D:\Tools"
   ```

   Use `-ListTools` to see what the configuration contains and `-DryRun` to preview a run without downloading anything. Working from a `git clone` of this repository is equivalent.

## Configuration & Parameters

ToolFetcher uses a parameter-based approach for flexibility. Key parameters include:

- **`-ToolsFile` (alias `-tf`):**  
  One or more YAML configuration files (local paths or URLs). Several files can be given as an array or as a comma-separated list; their `tools` arrays are merged and the first non-empty `tooldirectory` wins.  
  *Default:* `"tools.yaml"` next to the script  
  If a file is not found or is unreachable, the script offers to use a default URL:  
  ```
  https://raw.githubusercontent.com/kev365/ToolFetcher/refs/heads/main/tools.yaml
  ```

- **`-ToolsDirectory` (alias `-td`):**  
  The directory where all downloaded tools will be stored. Relative paths are resolved against the current location. If neither this parameter nor `tooldirectory:` in the YAML is set, tools are downloaded next to the script and a warning says so. The directory is created on the first real download, so `-ListTools` and `-DryRun` leave nothing behind.  
  *Example:* `C:\tools`

- **`-Tag`:**  
  Only process entries whose `Category` matches one of the given tags. Each shipped `tool_groups/*.yaml` file carries a file-level `category:` (its file name), and entries can set their own `Category` (a string or a list).

- **`-DryRun` (alias `-dry`):**  
  Show what would be downloaded or updated without writing anything. In update mode this still asks upstream whether a tool changed, so the preview is accurate.

- **`-ForceDownload` (alias `-force`):**  
  Re-download a tool even if it is installed and up to date. Managed files are replaced; modified managed files are kept as `.saveN` backups; user-added files are never touched.
  When used with `-UpdateAll`, it also updates tools that have `skipdownload: true`.

- **`-UpdateAll` (alias `-upall`):**  
  Updates all previously downloaded tools that have downloads enabled (skipdownload: false). Tools whose upstream has not changed and whose files are intact are skipped; modified or missing managed files trigger a fresh download. Use `-ForceDownload` to re-download everything.

- **`-UpdateTools` (alias `-uptools`):**  
  Specify tool names to update (comma-separated, repeated, or as an array). If a tool is not already downloaded, it will be downloaded. Up-to-date tools are skipped unless `-ForceDownload` is given.

- **`-Parallel` and `-ThrottleLimit`:**  
  Run downloads in parallel on PowerShell 7+ (`-ThrottleLimit` concurrent downloads, default 4). Ignored with a warning on Windows PowerShell 5.1.

- **`-VerboseOutput` (alias `-vo`):**  
  Enables detailed debug output for troubleshooting.

- **`-TraceOutput` (alias `-to`):**  
  Enables very detailed trace information (most verbose).

- **`-Log` (alias `-l`):**  
  Enables logging to a file in the tools directory (during a dry run against a missing tools directory the log goes to the temp folder instead).

- **`-GitHubPAT` (alias `-pat`):**  
  Optionally provide your GitHub Personal Access Token to raise the API rate limit from 60 to 5,000 requests per hour and to reach private repositories.

- **`-PromptForPAT` (alias `-ppat`):**  
  Securely prompt for GitHub Personal Access Token (recommended over -GitHubPAT).

- **`-ListTools` (alias `-list`):**  
  Lists all available tools in the configuration file(s).

### Exit codes

`0` when every processed tool succeeded, was skipped, or was up to date; `1` when at least one tool failed or was skipped because of a GitHub rate limit. A run summary is printed (and logged) at the end.

## YAML Configuration

Each file has two optional top-level keys, `tooldirectory` and `category`, and a `tools` list. A file-level `category` applies to every entry in that file that has no `Category` of its own.

```yaml
tooldirectory: ""     # Optional. Where tools go when -ToolsDirectory is not given
category: ""          # Optional. Default Category for every entry in this file (used by -Tag)
tools:
  - Name: "ToolName"      # Tool identifier, also used to name the parent folder
    RepoUrl: ""           # URL goes here
    DownloadMethod: ""    # Options: gitClone | latestRelease | branchZip | specificFile
    OutputFolder: ""      # Appends a subdirectory to the tools directory
    Branch: ""            # Optional. If omitted, the repository's default branch is looked up
    DownloadName: ""      # latestRelease: exact asset file name; specificFile: name to save the file as when the URL does not end with one
    AssetFilename: ""     # Regex for the asset file name (preferred: survives version bumps)
    AssetType: ""         # Options: win64 | win32 | linux64 | linux32 | macos64 | macos32 | arm64 | arm32
    SpecificFilePath: ""  # Used with the 'specificFile' DownloadMethod to specify file path in repository
    Extract: true         # Whether to extract the downloaded file (default: true)
    SkipDownload: false   # Whether to skip downloading this tool (default: false)
    Category: ""          # Optional. One tag or a list of tags for -Tag (overrides the file-level category)
    ExpectedSha256: ""    # Optional. Refuse to install anything whose SHA256 differs
```

Entries with a `Name` but no `RepoUrl` or no `DownloadMethod` are treated as placeholders (wishlist items, or tools with no automated download): they are listed as `[PLACEHOLDER]` and skipped. `AssetType` picks the first release asset whose name carries a marker for that platform and architecture (for example `win64` needs `win` plus `x64`/`amd64`/`x86_64` and rejects `arm64`, `linux` and `darwin` builds); when a release ships several matching builds, use `AssetFilename` to name the one you want.

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

10. **Merge Tool Groups and Filter by Category:**
    ```powershell
    .\ToolFetcher.ps1 -tf "tool_groups\registry_analysis.yaml,tool_groups\log_analysis.yaml" -Tag registry_analysis
    ```

11. **Preview an Update:**
    ```powershell
    .\ToolFetcher.ps1 -upall -DryRun
    ```

12. **Parallel Downloads (PowerShell 7+):**
    ```powershell
    .\ToolFetcher.ps1 -Parallel -ThrottleLimit 6
    ```

## Updating from v2.1

See [CHANGELOG.md](CHANGELOG.md) for the full list of changes.

- Installs made by v2.1 keep working: their `.downloaded.json` markers use MD5 digests, which are recognised and replaced by SHA256 markers on the next update. Nothing is backed up or removed spuriously.
- The first `-UpdateAll` after upgrading re-downloads `branchZip` and `specificFile` tools once to record the upstream ETag; from then on unchanged tools are skipped.
- With no `tooldirectory:` and no `-ToolsDirectory`, v2.1 prompted for a folder; v2.2 downloads next to the script and warns. Set one of the two to keep tools elsewhere.
- Runs now exit with code `1` when a tool fails; v2.1 always exited `0`.

## Error Handling

ToolFetcher provides comprehensive error handling and user guidance:

- YAML syntax validation with helpful error messages
- GitHub API error handling, including rate-limit diagnosis with the reset time and a hint to use a token
- Transient network errors are retried with backoff; stalled downloads time out
- A failed download never removes the previous version of a tool
- File system operation error handling
- Detailed logging for troubleshooting and a run summary listing every problem

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
  anything that doesn't match, for every download method.
- **Path traversal is rejected.** Tool `Name` and `OutputFolder` are validated
  at load time and at write time — entries containing `..`, absolute paths,
  or path separators in `Name` are refused so downloads can't escape your
  `-ToolsDirectory`. A configuration with such an entry is refused as a whole.
- **Zip-Slip safe extraction.** Every archive entry must resolve inside the
  staging folder before it is written.
- **TLS 1.2+ enforced.** The script raises `[Net.ServicePointManager]::SecurityProtocol`
  to TLS 1.2 at startup so PS 5.1 on older Windows builds doesn't fall back
  to TLS 1.0.
- **PAT scrubbing.** The token given to the script, and any GitHub token
  (`ghp_...`, `github_pat_...`, classic 40-char hex) in `token`/`Bearer`
  form, are redacted from log output before display or persistence.
- **Plaintext HTTP warning.** `RepoUrl` or `-ToolsFile` values starting with
  `http://` produce a warning at validation time. They still work but are
  vulnerable to tampering in transit.
- **Pinned dependency.** The `powershell-yaml` module is installed at a
  specific version (see `$script:RequiredYamlVersion` in the script) to
  protect against supply-chain compromise of that module.

## Future Considerations

- **Additional Archive Formats:**  
  Expand support beyond ZIP archives to include other formats.

- **Non-GitHub Support:**  
  Current focus is primarily on GitHub-based downloads; `specificFile` already works with any HTTPS URL and uses ETag/Last-Modified to detect changes.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.

## Author

Kevin Stokes

[Blog write-up](https://dfir-kev.medium.com/tool-fetcher-86691e65731b) · [LinkedIn Profile](https://www.linkedin.com/in/dfir-kev/) · [Buy me a coffee!](https://www.buymeacoffee.com/dfirkev)
