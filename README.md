# ToolFetcher (v2.1.2)

ToolFetcher is a PowerShell tool designed to fetch and manage a collection of DFIR and other GitHub tools. It streamlines the process of downloading, extracting, and organizing forensic utilities from various sources—whether by cloning Git repositories, downloading the latest releases via the GitHub API, or pulling specific files directly.

## Features

- **Multiple Download Methods:**  
  Supports various methods including:
  - `gitClone` – Downloads a repository using GitHub API (no Git dependency)
  - `latestRelease` – Downloads the latest release assets via the GitHub API
  - `branchZip` – Downloads a branch ZIP archive (without the `.git` folder)
  - `specificFile` – Downloads a specific file directly

- **Automated Extraction & Management:**  
  - Automatically extracts ZIP archives when applicable
  - Creates `.downloaded.json` marker files to track managed files
  - Preserves user modifications during updates
  - Supports force re-download with complete directory overwrite

- **External YAML Configuration:**  
  ToolFetcher loads its tool configuration from an external YAML file that supports:
  - Multiple download methods
  - Custom output folders
  - Asset type filtering (win64, win32, linux64, linux32, macos64, macos32, arm64, arm32)
  - Skip download options
  - Extraction control
  - Branch selection
  - Local or remote YAML file support

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

- **PowerShell:** Version 5.1 or later (or PowerShell Core)
- **Internet Connection:** Required for downloading tools and GitHub API access
- **powershell-yaml Module:**  
  This module is required to parse the external YAML configuration file. The script automatically checks for and installs it if requested.

## Configuration & Parameters

ToolFetcher uses a parameter-based approach for flexibility. Key parameters include:

- **`-ToolsFile` (alias `-tf`):**  
  Specifies the YAML configuration file. This can be a local file or a URL.  
  *Default:* `"tools.yaml"`  
  If the specified file is not found or is unreachable, the script offers to use a default URL:  
  ```
  https://raw.githubusercontent.com/kev365/ToolFetcher/refs/heads/main/tools.yaml
  ```

- **`-ToolsDirectory` (alias `-td`):**  
  The directory where all downloaded tools will be stored.  
  *Example:* `C:\tools`

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
Name: "ToolName"      # Tool identifier, also used to name the parent folder
RepoUrl: ""           # URL goes here
DownloadMethod: ""    # Options: gitClone | latestRelease | branchZip | specificFile
OutputFolder: ""      # Appends a subdirectory to $toolsFolder
Branch: ""            # Defaults to master if not provided, also checks main if master is not available
DownloadName: ""      # Used to download a particular file from the latestRelease
AssetFilename: ""     # Used to specify exact filename to download from latestRelease (supports regex)
AssetType: ""         # Options: win64 | win32 | linux64 | linux32 | macos64 | macos32 | arm64 | arm32
SpecificFilePath: ""  # Used with the 'specificFile' DownloadMethod to specify file path in repository
Extract: true         # Whether to extract the downloaded file (default: true)
SkipDownload: false   # Whether to skip downloading this tool (default: false)
```

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

- **Parallel Download and Extraction:**  
  Separate download and extraction processes for improved performance.
  
- **Additional Archive Formats:**  
  Expand support beyond ZIP archives to include other formats.

- **Non-GitHub Support:**  
  Current focus is primarily on GitHub-based downloads.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.

## Author

Kevin Stokes

[Blog write-up](https://dfir-kev.medium.com/tool-fetcher-86691e65731b) · [LinkedIn Profile](https://www.linkedin.com/in/dfir-kev/) · [Buy me a coffee!](https://www.buymeacoffee.com/dfirkev)
