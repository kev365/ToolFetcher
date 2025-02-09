# ToolFetcher (v1.1.0)

ToolFetcher is a PowerShell tool designed to fetch and manage a collection of DFIR and other GitHub tools. It streamlines the process of downloading, extracting, and organizing forensic utilities from various sources—whether by cloning Git repositories, downloading the latest releases via the GitHub API, or pulling specific files directly.

## Features

- **Multiple Download Methods:**  
  Supports various methods including:
  - `gitClone` – Clones Git repositories.
  - `latestRelease` – Downloads the latest release assets via the GitHub API.
  - `branchZip` – Downloads a branch ZIP archive (without the `.git` folder).
  - `specificFile` – Downloads a specific file directly.

- **Automated Extraction:**  
  Automatically extracts ZIP archives if applicable.

- **External YAML Configuration:**  
  **Now powered by an external YAML file!** Instead of a hard-coded tools array, ToolFetcher loads its tool configuration from a separate YAML file. This offers several benefits:
  - **Ease of Maintenance:**  
    Update your list of tools without modifying the script code.
  - **Customization:**  
    Users can easily add, remove, or modify tool definitions in a human-friendly format.
  - **Remote Updates:**  
    Specify a GitHub URL to automatically fetch the latest configuration—ensuring everyone always uses an up-to-date tool list.
  - **Separation of Concerns:**  
    Keeps the script logic separate from configuration data, making it cleaner and more modular.
  - **Version Control:**  
    Manage your tools list independently and track changes over time using Git.

- **Marker Files:**  
  Creates a `.downloaded.json` marker file in each tool’s output folder containing metadata about the download (e.g., timestamp, download method, version). Helpful for download management.

- **Verbose Debug Logging:**  
  Optionally display detailed debug output to help with troubleshooting.

- **Force Download Option:**  
  Use the `$ForceDownload` option to overwrite existing tool directories if needed.

- **GitHub Rate Limit Handling:**  
  Optionally supply a GitHub Personal Access Token (PAT) to mitigate API rate limit issues.

## Requirements

- **PowerShell:** Version 5.1 or later (or PowerShell Core).
- **powershell-yaml Module:**  
  This module is required to parse the external YAML configuration file. The script automatically checks for and installs it (if necessary).

## Configuration

Before running the script, adjust a few variables at the top of the file:

- **`$toolsFolder`**  
  The folder where all tools will be stored.  
  *Example:* `C:\tools` (change as needed).

- **`$ForceDownload`**  
  Set to `$true` to force re-download and overwrite any existing tool directories.

- **`$VerboseOutput`**  
  Set to `$true` to enable detailed debug output.

- **`$GitHubPAT`**  
  (Optional) Provide your GitHub Personal Access Token if you encounter rate limit issues when using GitHub APIs.

### External YAML Configuration

ToolFetcher now loads its tool definitions from an external YAML file rather than an embedded array. You can specify the YAML file location using the `-ToolsFile` parameter when running the script. For example:

```powershell
.\ToolFetcher.ps1 -ToolsFile "tools.yaml"
```

By default, the script fetches the configuration from:

```
https://raw.githubusercontent.com/kev365/ToolFetcher/refs/heads/main/tools.yaml
```

**Benefits of Using a Separate YAML File:**

- **Separation of Concerns:**  
  Keeps your script’s logic separate from its configuration. This makes the code easier to read, manage, and maintain.

- **Dynamic and Remote Updates:**  
  Easily update your tools list without changing the script. Point to a remote YAML file (such as one hosted on GitHub) to always fetch the latest configuration.

- **User-Friendly Format:**  
  YAML is intuitive and simple to edit—even for non-developers—making it accessible for customizing tool settings.

- **Version Control:**  
  Manage changes to your configuration file independently, allowing you to track modifications over time without cluttering the main script.

## Usage

1. **Configure the Script:**  
   Adjust the user-configurable variables at the top of the script and update the YAML file to include or modify the list of tools.

2. **Run the Script:**  
   Execute the script in your PowerShell terminal. If `$toolsFolder` is empty, you’ll be prompted to enter a location.

3. **Monitor the Process:**  
   The script logs progress information and debug output (if enabled) for each tool. Check the output folder for a `.downloaded.json` file, which contains details about the download and extraction.

## Future Considerations

- **Parallel Downloading:**  
  Consider separating download and extraction processes for improved performance.
  
- **Support for Additional Archive Formats:**  
  Expand beyond ZIP archives to include other formats.

- **Support for downloading tools to WSL instance:**  
  Adding the ability to use the host PowerShell console to manage both your Windows and WSL tools.

- **Linux version:**  
  Adding a linux script to perform similar functions for your linux tools.

## Limitations

- **GitHub API Rate Limits:**  
  Downloads using the GitHub API (`latestRelease`) may be rate limited unless a GitHub PAT is provided. Likely rare.

- **Error Handling:**  
  While basic error handling is implemented, network issues or extraction errors may not always be fully recoverable.

- **Archive Extraction Assumptions:**  
  The script currently supports ZIP archives for automatic extraction. Additional handling may be required for other formats.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.

## Author

Kevin Stokes  
[LinkedIn Profile](https://www.linkedin.com/in/dfir-kev/)
