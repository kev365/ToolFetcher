# ToolFetcher

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

- **Customizable Configuration:**  
  Easily modify settings and the list of tools in the built-in configuration array.

- **Marker Files:**  
  Creates a `.downloaded.json` marker file in each tool’s output folder containing metadata about the download (e.g., timestamp, download method, version).

- **Verbose Debug Logging:**  
  Optionally display detailed debug output to help with troubleshooting.

- **Force Download Option:**  
  Use the `$ForceDownload` option to overwrite existing tool directories if needed.

- **GitHub Rate Limit Handling:**  
  Optionally supply a GitHub Personal Access Token (PAT) to mitigate API rate limit issues.

## Requirements

- **PowerShell:** Version 5.1 or later (or PowerShell Core).

## Configuration

Before running the script, you may need to adjust a few variables at the top of the file:

- **`$toolsFolder`**  
  The folder where all tools will be stored.  
  *Default:* `c:\tools`  
  *Note:* If left empty, the script will prompt you for a location.

- **`$ForceDownload`**  
  Set to `$true` to force re-download and overwrite any existing tool directories.

- **`$VerboseOutput`**  
  Set to `$true` to enable detailed debug output.

- **`$GitHubPAT`**  
  (Optional) Provide your GitHub Personal Access Token if you encounter rate limit issues when using GitHub APIs.

### Tool Configuration Array

The script includes a `$tools` array where each tool is defined with properties such as:

- **`Name`** – A friendly name for the tool.
- **`RepoUrl`** – The URL of the GitHub repository or direct file.
- **`DownloadMethod`** – How the tool should be downloaded. Valid methods include:
  - `gitClone`
  - `latestRelease`
  - `branchZip`
  - `specificFile`
- **Optional Properties:**  
  Depending on the download method, you can also specify:
  - `Branch` (for `gitClone` or `branchZip`)
  - `DownloadName`, `AssetType`, `AssetFilename`, `Extract` (for `latestRelease`)
  - `SpecificFilePath` (for `specificFile`)
  - `OutputFolder` – A custom subfolder under `$toolsFolder` to help organize your downloads.

## Usage

1. **Configure the Script:**  
   Adjust the user-configurable variables and modify the `$tools` array to add or change the tools you want to download.

2. **Run the Script:**  
   Execute the script in your PowerShell terminal. If `$toolsFolder` is empty, you’ll be prompted to enter a location.

3. **Monitor the Process:**  
   The script logs progress information and debug output (if enabled) for each tool. Check the output folder for a `.downloaded.json` file, which contains details about the download and extraction.

## Future considerations

- **tools.yml file**
  Use of a separate yaml file for tools list

## Limitations

- **GitHub API Rate Limits:**  
  Downloads using the GitHub API (`latestRelease`) may be rate limited unless a GitHub PAT is provided.

- **Error Handling:**  
  While basic error handling is in place, network issues or extraction errors may not always be fully recoverable.

- **ZIP Extraction Assumptions:**  
  The script currently supports ZIP archives for automatic extraction. If a tool is packaged in a different archive format, additional handling may be necessary.

- **Extraction Customization:**  
  The extraction process is relatively straightforward and may not handle complex archive structures or nested archives without modifications.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.

## Author

Kevin Stokes  
[LinkedIn Profile](https://www.linkedin.com/in/dfir-kev/)
