# ToolFetcher (v1.2.0)

ToolFetcher is a PowerShell tool designed to fetch and manage a collection of DFIR and other GitHub tools. It streamlines the process of downloading, extracting, and organizing forensic utilities from various sources—whether by cloning Git repositories, downloading the latest releases via the GitHub API, or pulling specific files directly.

## Features

- **Multiple Download Methods:**  
  Supports various methods including:
  - `gitClone` – Clones Git repositories.
  - `latestRelease` – Downloads the latest release assets via the GitHub API.
  - `branchZip` – Downloads a branch ZIP archive (without the `.git` folder).
  - `specificFile` – Downloads a specific file directly.

- **Automated Extraction:**  
  Automatically extracts ZIP archives when applicable.

- **External YAML Configuration:**  
  ToolFetcher now loads its tool configuration from an external YAML file rather than a hard-coded array. This offers several benefits:
  - **Ease of Maintenance:**  
    Update your list of tools without modifying the script.
  - **Customization:**  
    Easily add, remove, or modify tool definitions in a human-friendly format.
  - **Remote Updates:**  
    Point to a remote YAML file (such as one hosted on GitHub) to always fetch the latest configuration.
  - **Separation of Concerns & Version Control:**  
    Keep the script logic and configuration separate and manage changes independently.

- **Marker Files & File Manifest:**  
  Creates a `.downloaded.json` marker file in each tool’s output folder that contains metadata and a file manifest (with MD5 hashes). This improves download management and allows for selective removal of managed files during updates.

- **Enhanced Logging & Debugging:**  
  Provides detailed debug output when enabled, making troubleshooting easier.

- **Force Download & Update Options:**  
  - **Force Download:**  
    Use the `-ForceDownload` switch to overwrite existing tool directories completely.
  - **Update Mode:**  
    Use the new `-Update` switch to refresh already downloaded tools by removing only managed files (as tracked in the marker file), while preserving any user modifications.

- **GitHub PAT Validation & Rate Limit Handling:**  
  - Supply a GitHub Personal Access Token (PAT) to avoid API rate limit issues.
  - The script now validates the provided PAT to ensure smooth API operations.

## Requirements

- **PowerShell:** Version 5.1 or later (or PowerShell Core).
- **powershell-yaml Module:**  
  This module is required to parse the external YAML configuration file. The script automatically checks for and installs it if necessary.

## Configuration & Parameters

In v1.2.0, ToolFetcher has shifted from internal variable configuration to a robust parameter-based approach for greater flexibility. The key parameters are:

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

- **`-ForceDownload` (alias `-fd`):**  
  Forces a complete re-download of a tool by overwriting its existing directory.

- **`-Update` (alias `-up`):**  
  Updates tools that have already been downloaded by removing only managed files (as defined in the marker file), while leaving any user-added files intact.

- **`-VerboseOutput` (alias `-v`):**  
  Enables detailed debug output for troubleshooting.

- **`-GitHubPAT` (alias `-gh`):**  
  Optionally provide your GitHub Personal Access Token to avoid API rate limits. The script validates the token before proceeding.

## External YAML Configuration

ToolFetcher now leverages an external YAML file to define tool settings instead of using an embedded array. This approach provides:

- **Separation of Concerns:**  
  Keeps configuration data separate from the script logic.

- **Dynamic Updates:**  
  Easily update your tools list by modifying the YAML file (local or remote).

- **User-Friendly Format:**  
  YAML is straightforward to edit—even for those less familiar with code.

- **Independent Version Control:**  
  Manage the tools list as its own file, tracking changes separately from the script.

For example, you can run the script as follows:

```powershell
.\ToolFetcher.ps1 -ToolsFile "tools.yaml" -ToolsDirectory "C:\tools" -ForceDownload -VerboseOutput -GitHubPAT "your_pat_here"
```

## Usage

1. **Configure the Script:**  
   Provide the necessary parameters when running the script. There is no need to modify internal variables. For instance:

   ```powershell
   .\ToolFetcher.ps1 -ToolsFile "tools.yaml" -ToolsDirectory "C:\tools" -Update -VerboseOutput
   ```

2. **Run the Script:**  
   Execute the script in your PowerShell terminal. If the `-ToolsDirectory` parameter is omitted, you will be prompted to enter a directory.

3. **Monitor the Process:**  
   The script logs progress and debug information for each tool. Each tool’s output folder will include a `.downloaded.json` file containing metadata and the file manifest.

## Future Considerations

- **Parallel Downloading:**  
  Separate download and extraction processes for improved performance.
  
- **Additional Archive Formats:**  
  Expand support beyond ZIP archives to include other formats.

- **Enhanced Multi-Platform Support:**  
  Consider additional features for managing tools in WSL and Linux environments.

## Limitations

- **Non-GitHub Support:**  
  The focus is primarily on GitHub-based downloads.

- **Archive Extraction:**  
  Currently supports only ZIP archives for automatic extraction.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.

## Author

Kevin Stokes

[Blog write-up](https://dfir-kev.medium.com/tool-fetcher-499c99aaa9fa) · [LinkedIn Profile](https://www.linkedin.com/in/dfir-kev/)
