# =====================================================
# ToolFetcher
#
# A tool for fetching DFIR and other GitHub tools.
#
# Author: Kevin Stokes
# Version: 1.2.1
# License: MIT
# =====================================================

# Enable advanced functions with cmdlet binding.
[CmdletBinding()]
param (
    # The first parameter allows a local file (such as "tools.yaml") or a URL (e.g., a GitHub raw URL).
    [Parameter(Mandatory = $false,
               Position = 1,
               HelpMessage = 'Supply a local file (e.g., "tools.yaml") or a URL (e.g., a GitHub raw URL).')]
    [Alias('tf')]
    [string]$ToolsFile = "tools.yaml",

    [Parameter(Mandatory = $false,
               Position = 2,
               HelpMessage = 'Supply a folder where all tools will be stored when downloaded.')]
    [Alias('td')]
    [string]$ToolsDirectory = "",

    # A switch that forces a re-download and overwrites any existing tool directories.
    [Parameter(HelpMessage = 'Force re-download and overwrite any existing tool output directories. Ignores the skipdownload flag.')]
    [Alias('fd')]
    [switch]$ForceDownload = $false,

    # A switch to update tools that have already been downloaded. It respects the skipdownload flag.
    [Parameter(HelpMessage = 'Update tools that are already downloaded. This forces an update like ForceDownload but respects the skipdownload flag.')]
    [Alias('up')]
    [switch]$Update = $false,

    # A switch to enable verbose output.
    [Parameter(HelpMessage = 'Show detailed output')]
    [Alias('v')]
    [switch]$VerboseOutput = $false,

    # An optional GitHub Personal Access Token (PAT) to avoid rate limits when using GitHub API.
    [Parameter(HelpMessage = 'GitHub Personal Access Token - to avoid rate limits, if needed.')]
    [Alias('gh')]
    [string]$GitHubPAT
)

# -----------------------------------------------
# Failsafe for ToolsFile
# -----------------------------------------------
# Define a default URL to use in case the provided ToolsFile is unavailable.
$defaultToolsFileUrl = "https://raw.githubusercontent.com/kev365/ToolFetcher/refs/heads/main/tools.yaml"

# Check if the provided ToolsFile is a URL.
if ($ToolsFile -match '^https?://') {
    try {
        # Make a HEAD request to verify that the URL is reachable.
        $response = Invoke-WebRequest -Uri $ToolsFile -Method Head -UseBasicParsing -ErrorAction Stop
        Write-Host "[INFO] Using user-specified URL for tools file: $ToolsFile" -ForegroundColor Cyan
    }
    catch {
        # If the URL is not reachable, warn the user and ask if they want to use the default URL.
        Write-Host "[WARNING] The user-specified URL '$ToolsFile' is not available." -ForegroundColor Yellow
        $choice = Read-Host "Do you want to use the default URL ($defaultToolsFileUrl)? (Y/N)"
        if ($choice -match '^(?i:Y(es)?)$') {
            $ToolsFile = $defaultToolsFileUrl
            Write-Host "[INFO] Using default URL: $ToolsFile" -ForegroundColor Cyan
        }
        else {
            Write-Host "Exiting script." -ForegroundColor Red
            exit 1
        }
    }
}
else {
    # If the provided ToolsFile is not a URL, then treat it as a local file.
    if ([System.IO.Path]::IsPathRooted($ToolsFile)) {
        # If the path is absolute, check if the file exists.
        if (Test-Path -Path $ToolsFile) {
            Write-Host "[INFO] Using user-specified local tools file: $ToolsFile" -ForegroundColor Cyan
        }
        else {
            # Warn the user if the file isn't found and offer to use the default URL.
            Write-Host "[WARNING] The local tools file specified ($ToolsFile) was not found." -ForegroundColor Yellow
            $choice = Read-Host "Do you want to use the default URL ($defaultToolsFileUrl)? (Y/N)"
            if ($choice -match '^(?i:Y(es)?)$') {
                $ToolsFile = $defaultToolsFileUrl
                Write-Host "[INFO] Using default URL: $ToolsFile" -ForegroundColor Cyan
            }
            else {
                Write-Host "Exiting script." -ForegroundColor Red
                exit 1
            }
        }
    }
    else {
        # For a relative path, resolve it relative to the script's location.
        $localToolsFile = Join-Path $PSScriptRoot $ToolsFile
        if (Test-Path -Path $localToolsFile) {
            Write-Host "[INFO] Using local tools file: $localToolsFile" -ForegroundColor Cyan
            $ToolsFile = $localToolsFile
        }
        else {
            # Warn if not found and offer the default URL.
            Write-Host "[WARNING] Local tools file '$ToolsFile' not found at '$localToolsFile'." -ForegroundColor Yellow
            $choice = Read-Host "Do you want to use the default URL ($defaultToolsFileUrl)? (Y/N)"
            if ($choice -match '^(?i:Y(es)?)$') {
                $ToolsFile = $defaultToolsFileUrl
                Write-Host "[INFO] Using default URL: $ToolsFile" -ForegroundColor Cyan
            }
            else {
                Write-Host "Exiting script." -ForegroundColor Red
                exit 1
            }
        }
    }
}

# -----------------------------------------------
# Global Logging Setup
# -----------------------------------------------
# Define simple logging functions for debugging and info messages.
function Log-Debug {
    param ([string]$Message)
    # Only display debug messages if VerboseOutput is enabled.
    if ($VerboseOutput) { Write-Host "[DEBUG] $Message" -ForegroundColor DarkGray }
}
function Log-Info {
    param ([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}
function Log-Warning {
    param ([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}
function Log-Error {
    param ([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# -----------------------------------------------
# Function: Validate GitHub Personal Access Token
# -----------------------------------------------
# This function validates the provided GitHub PAT by making a call to GitHub's /user endpoint.
function Validate-GitHubPAT {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Token
    )
    # Set up HTTP headers with the token and a user agent.
    $headers = @{
        "Authorization" = "token $Token"
        "User-Agent"    = "PowerShell"
    }
    try {
        # Make the API call. If successful, the token is valid.
        $response = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -ErrorAction Stop
        Log-Debug "GitHub PAT validated for user: $($response.login)"
        return $true
    }
    catch {
        # If the call fails, the token is not valid.
        Log-Error "GitHub PAT validation failed: $_"
        return $false
    }
}

# -----------------------------------------------
# Helper Function: Build File Manifest
# -----------------------------------------------
# Scans a folder recursively to build a list (manifest) of files along with their MD5 hash.
function Get-FileManifest {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Folder
    )
    $manifest = @{}
    # Recursively get all files in the folder.
    $files = Get-ChildItem -Recurse -File -Path $Folder
    foreach ($file in $files) {
        # Skip the marker file that stores the manifest.
        if ($file.Name -eq ".downloaded.json") { continue }
        # Create a relative path for the file (so that the full folder path is not stored).
        $relativePath = $file.FullName.Substring($Folder.Length + 1)
        # Generate an MD5 hash of the file.
        $hash = (Get-FileHash -Algorithm MD5 -Path $file.FullName).Hash
        $manifest[$relativePath] = $hash
    }
    return $manifest
}

# -----------------------------------------------
# Helper Function: Write Marker File with Metadata
# -----------------------------------------------
# Writes out a JSON file (".downloaded.json") to record the details of the download.
function Write-MarkerFile {
    param (
        [Parameter(Mandatory)]
        $OutputFolder,
        [Parameter(Mandatory)]
        $ToolName,
        [Parameter(Mandatory)]
        $DownloadMethod,
        [Parameter(Mandatory)]
        $DownloadURL,
        [Parameter()]
        $Version = "",
        [Parameter()]
        $CommitHash = "",
        [Parameter()]
        $DownloadedFile = "",
        [Parameter()]
        $ExtractionLocation = "",
        [Parameter()]
        $Manifest = $null
    )
    # Define the path for the marker file.
    $markerFile = Join-Path $OutputFolder ".downloaded.json"
    # Build a hashtable with metadata for this download.
    $metadata = @{
        Tool               = $ToolName
        Timestamp          = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
        DownloadMethod     = $DownloadMethod
        DownloadURL        = $DownloadURL
        Version            = $Version
        CommitHash         = $CommitHash
        DownloadedFile     = $DownloadedFile
        ExtractionLocation = $ExtractionLocation
        Manifest           = $Manifest
    }
    # Convert the metadata to JSON and write it to the marker file.
    $metadata | ConvertTo-Json -Depth 5 | Out-File -FilePath $markerFile -Force
    Log-Debug "Marker file created at $markerFile"
}

# -----------------------------------------------
# Helper Function: Remove Managed Files Using Marker File
# -----------------------------------------------
# Reads the marker file and removes only those files that were downloaded, preserving any user-added files.
function Remove-ManagedFiles {
    param (
        [Parameter(Mandatory=$true)]
        [string]$OutputFolder
    )
    # Define the marker file path.
    $markerFile = Join-Path $OutputFolder ".downloaded.json"
    if (Test-Path $markerFile) {
        try {
            # Load the metadata from the marker file.
            $metadata = Get-Content -Path $markerFile | ConvertFrom-Json
            if ($metadata.Manifest) {
                # Loop through each file in the manifest and remove it.
                foreach ($relativePath in $metadata.Manifest.Keys) {
                    $fileToRemove = Join-Path $OutputFolder $relativePath
                    if (Test-Path $fileToRemove) {
                        Remove-Item -Path $fileToRemove -Force -Recurse -ErrorAction SilentlyContinue
                        Log-Debug "Removed managed file: $fileToRemove"
                    }
                }
            }
            # Remove the marker file once cleanup is complete.
            Remove-Item -Path $markerFile -Force -ErrorAction SilentlyContinue
            Log-Debug "Removed marker file: $markerFile"
        }
        catch {
            Log-Warning "Failed to remove managed files in $OutputFolder. Exception: $_"
        }
    }
    else {
        Log-Debug "No marker file found in $OutputFolder. No managed files to remove."
    }
}

# -----------------------------------------------
# Tools Configuration: Load from YAML File
# -----------------------------------------------
# Determine whether the tools configuration comes from a URL or a local file.
if ($ToolsFile -match '^https?://') {
    Log-Info "Fetching tools configuration from URL: $ToolsFile"
    try {
        # Get the YAML content from the URL.
        $yamlContent = (Invoke-WebRequest -Uri $ToolsFile -UseBasicParsing).Content
    }
    catch {
        Log-Error "Failed to fetch YAML from URL: $ToolsFile. Exception: $_"
        exit 1
    }
}
else {
    try {
        # Read the YAML configuration from a local file.
        $yamlContent = Get-Content -Path $ToolsFile -Raw
    }
    catch {
        Log-Error "Failed to read YAML file at: $ToolsFile. Exception: $_"
        exit 1
    }
}

# Ensure the powershell-yaml module is available. Install it if not.
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host "[INFO] The 'powershell-yaml' module is not installed. Attempting to install it..." -ForegroundColor Cyan
    try {
        Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowClobber
        Write-Host "[INFO] Successfully installed the 'powershell-yaml' module." -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to install the 'powershell-yaml' module. Please install it manually using: Install-Module powershell-yaml" -ForegroundColor Red
        exit 1
    }
}
# Import the module for YAML parsing.
Import-Module powershell-yaml -ErrorAction Stop

try {
    # Convert the YAML configuration into PowerShell objects.
    $toolsConfig = $yamlContent | ConvertFrom-Yaml
    # Check if the YAML contains a "tools" property.
    if ($toolsConfig.tools) {
        $tools = $toolsConfig.tools
    }
    else {
        $tools = $toolsConfig
    }
    Log-Debug "Loaded $($tools.Count) tools from configuration file."
}
catch {
    Log-Error "Failed to parse YAML configuration. Exception: $_"
    exit 1
}

# -----------------------------------------------
# Validate GitHub Personal Access Token (if provided)
# -----------------------------------------------
# If a GitHub PAT is provided, verify that it is valid.
if (-not [string]::IsNullOrEmpty($GitHubPAT)) {
    if (-not (Validate-GitHubPAT -Token $GitHubPAT)) {
        $choice = Read-Host "The provided GitHub PAT appears to be invalid. Would you like to enter a new token? (Y/N)"
        if ($choice -match '^(?i:Y(es)?)$') {
            $GitHubPAT = Read-Host "Please enter a valid GitHub Personal Access Token"
            if (-not (Validate-GitHubPAT -Token $GitHubPAT)) {
                Write-Host "The provided token is still invalid. Exiting." -ForegroundColor Red
                exit 1
            }
        }
        else {
            Write-Host "Exiting script due to invalid GitHub PAT." -ForegroundColor Red
            exit 1
        }
    }
    else {
        Log-Info "GitHub PAT validated successfully."
    }
}

# -----------------------------------------------
# Ensure the Tools Directory Exists
# -----------------------------------------------
# If the ToolsDirectory parameter is empty, prompt the user.
if ([string]::IsNullOrEmpty($ToolsDirectory)) {
    if ($toolsConfig.tooldirectory) {
         $ToolsDirectory = $toolsConfig.tooldirectory
         Log-Info "Using ToolsDirectory from YAML: $ToolsDirectory"
    }
    else {
         $ToolsDirectory = (Read-Host "The 'ToolsDirectory' parameter is empty. Please provide a location for the tools folder")
    }
}
# Create the directory if it doesn't exist.
if (-not (Test-Path -Path $ToolsDirectory)) {
    try {
        New-Item -Path $ToolsDirectory -ItemType Directory -Force | Out-Null
        Log-Info "Created tools directory: $ToolsDirectory"
    }
    catch {
        Log-Error "Failed to create tools directory at '$ToolsDirectory'. Exception: $_"
        exit 1
    }
}

# -----------------------------------------------
# Functions for Download Methods
# -----------------------------------------------
# These functions implement different download strategies based on the tool's configuration.

function Download-GitCloneTool {
    param (
        [Parameter(Mandatory)]
        $ToolConfig,
        [Parameter(Mandatory)]
        [string]$ToolsDirectory
    )
    # Determine the output folder for the tool. Use the OutputFolder property if defined.
    if (-not [string]::IsNullOrEmpty($ToolConfig.OutputFolder)) {
        $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $ToolConfig.OutputFolder $ToolConfig.Name)
    }
    else {
        $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath $ToolConfig.Name
    }
    Log-Info "Cloning $($ToolConfig.Name)..."
    # Create the output folder if it doesn't exist.
    if (-not (Test-Path -Path $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
        Log-Debug "Created output folder: $outputFolder"
    }
    # Clone the repository using git.
    git clone $ToolConfig.RepoUrl --branch $ToolConfig.Branch $outputFolder
    Log-Debug "Clone complete for $($ToolConfig.Name)."
    
    $commitHash = ""
    try {
        # Retrieve the commit hash from the cloned repository.
        $commitHash = (& git -C $outputFolder rev-parse HEAD).Trim()
    }
    catch {
        Log-Warning "Could not retrieve commit hash for $($ToolConfig.Name)."
    }
    
    # Build a file manifest of the downloaded content.
    $manifest = Get-FileManifest -Folder $outputFolder
    # Write out the marker file containing metadata and the file manifest.
    Write-MarkerFile -OutputFolder $outputFolder `
                     -ToolName $ToolConfig.Name `
                     -DownloadMethod $ToolConfig.DownloadMethod `
                     -DownloadURL $ToolConfig.RepoUrl `
                     -Version $ToolConfig.Branch `
                     -CommitHash $commitHash `
                     -DownloadedFile "" `
                     -ExtractionLocation $outputFolder `
                     -Manifest $manifest
}

function Download-LatestReleaseTool {
    param (
        [Parameter(Mandatory)]
        $ToolConfig,
        [Parameter(Mandatory)]
        [string]$ToolsDirectory,
        [Parameter(Mandatory)]
        $GitHubPAT,
        [Parameter(Mandatory)]
        $AssetPatterns
    )
    # Convert the GitHub repository URL to the corresponding API URL.
    $apiRepoUrl = $ToolConfig.RepoUrl -replace "https://github.com/", "https://api.github.com/repos/"
    $releaseUri = "$apiRepoUrl/releases/latest"
    Log-Debug "Using API endpoint: $releaseUri for $($ToolConfig.Name)"
    
    # Build the HTTP headers for the API call.
    $headers = @{ "User-Agent" = "PowerShell" }
    if (-not [string]::IsNullOrEmpty($GitHubPAT)) { $headers["Authorization"] = "token $GitHubPAT" }
    
    try {
        # Retrieve the latest release information.
        $releaseInfo = Invoke-RestMethod -Uri $releaseUri -Headers $headers
        Log-Debug "Retrieved release info. Assets count: $($releaseInfo.assets.Count)"
    }
    catch {
        Log-Error "Failed to get release info for $($ToolConfig.Name). Exception: $_"
        return
    }
    
    # Filter the assets using the properties specified in the tool configuration.
    $assets = $releaseInfo.assets
    if (-not [string]::IsNullOrEmpty($ToolConfig.DownloadName)) {
        $assets = $assets | Where-Object { $_.name -eq $ToolConfig.DownloadName }
    }
    elseif (-not [string]::IsNullOrEmpty($ToolConfig.AssetFilename)) {
        $assets = $assets | Where-Object { $_.name -eq $ToolConfig.AssetFilename }
    }
    elseif (-not [string]::IsNullOrEmpty($ToolConfig.AssetType)) {
        if ($AssetPatterns.ContainsKey($ToolConfig.AssetType)) {
            $pattern = $AssetPatterns[$ToolConfig.AssetType]
            $assets = $assets | Where-Object { $_.name -match $pattern }
        }
        else {
            Log-Warning "No pattern defined for AssetType '$($ToolConfig.AssetType)' for $($ToolConfig.Name)."
        }
    }
    
    # Select the first matching asset.
    $asset = $assets | Select-Object -First 1
    if ($asset) {
        # Determine the output folder.
        if (-not [string]::IsNullOrEmpty($ToolConfig.OutputFolder)) {
            $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $ToolConfig.OutputFolder $ToolConfig.Name)
        }
        else {
            $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath $ToolConfig.Name
        }
        if (-not (Test-Path -Path $outputFolder)) {
            New-Item -Path $outputFolder -ItemType Directory | Out-Null
            Log-Debug "Created output folder: $outputFolder"
        }
        # Define the download path for the asset.
        $downloadPath = Join-Path -Path $outputFolder -ChildPath $asset.name
        Log-Info "Downloading $($ToolConfig.Name)..."
        try {
            # Download the asset.
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -Headers $headers
            Log-Debug "Downloaded to $downloadPath"
        }
        catch {
            Log-Error "Failed to download asset for $($ToolConfig.Name). Exception: $_"
            return
        }
        
        $archiveHash = $null
        $extract = $true
        # Determine if extraction should occur (based on configuration).
        if (($ToolConfig.ContainsKey("Extract")) -and ($ToolConfig.Extract -eq $false)) { $extract = $false }
        if ($extract -and ($downloadPath -like "*.zip")) {
            Log-Info "Extracting $($ToolConfig.Name)..."
            try {
                $archiveHash = (Get-FileHash -Algorithm MD5 -Path $downloadPath).Hash
                # Extract the downloaded ZIP archive.
                Expand-Archive -Path $downloadPath -DestinationPath $outputFolder -Force
                Remove-Item -Path $downloadPath
                Log-Debug "Extraction complete."
            }
            catch {
                Log-Error "Extraction failed for $downloadPath. Exception: $_"
            }
        }
        # Build a manifest of the files present in the output folder.
        $manifest = Get-FileManifest -Folder $outputFolder
        if ($archiveHash) {
            $manifest[[System.IO.Path]::GetFileName($downloadPath)] = $archiveHash
        }
        $downloadedFileParam = $downloadPath
        if ($extract -and ($downloadPath -like "*.zip")) { $downloadedFileParam = "" }
        
        $version = $releaseInfo.tag_name
        # Write out the marker file with metadata.
        Write-MarkerFile -OutputFolder $outputFolder `
                         -ToolName $ToolConfig.Name `
                         -DownloadMethod $ToolConfig.DownloadMethod `
                         -DownloadURL $asset.browser_download_url `
                         -Version $version `
                         -CommitHash "" `
                         -DownloadedFile $downloadedFileParam `
                         -ExtractionLocation $outputFolder `
                         -Manifest $manifest
    }
    else {
        Log-Warning "No matching asset found for $($ToolConfig.Name)."
    }
}

function Download-BranchZipTool {
    param (
        [Parameter(Mandatory)]
        $ToolConfig,
        [Parameter(Mandatory)]
        [string]$ToolsDirectory,
        [Parameter(Mandatory)]
        $GitHubPAT
    )
    # Determine which branch to download; default to "master" if not specified.
    $branch = if (-not [string]::IsNullOrEmpty($ToolConfig.Branch)) { $ToolConfig.Branch } else { "master" }
    # Construct the URL for the ZIP archive of the branch.
    $zipUrl = "$($ToolConfig.RepoUrl)/archive/refs/heads/$branch.zip"
    Log-Info "Downloading branch zip for $($ToolConfig.Name)..."
    
    # Determine the output folder.
    if (-not [string]::IsNullOrEmpty($ToolConfig.OutputFolder)) {
        $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $ToolConfig.OutputFolder $ToolConfig.Name)
    }
    else {
        $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath $ToolConfig.Name
    }
    if (-not (Test-Path -Path $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory | Out-Null
        Log-Debug "Created output folder: $outputFolder"
    }
    $fileName = "$($ToolConfig.Name)-$branch.zip"
    $downloadPath = Join-Path -Path $outputFolder -ChildPath $fileName
    Log-Debug "Downloading branch zip to $downloadPath"
    
    # Set up HTTP headers.
    $headers = @{ "User-Agent" = "PowerShell" }
    if (-not [string]::IsNullOrEmpty($GitHubPAT)) { $headers["Authorization"] = "token $GitHubPAT" }
    try {
        # Download the ZIP file.
        Invoke-WebRequest -Uri $zipUrl -OutFile $downloadPath -Headers $headers
        Log-Debug "Downloaded branch zip to $downloadPath"
    }
    catch {
        Log-Error "Failed to download branch zip for $($ToolConfig.Name). Exception: $_"
        return
    }
    
    $archiveHash = $null
    $extract = $true
    # Check if extraction is desired.
    if (($ToolConfig.ContainsKey("Extract")) -and ($ToolConfig.Extract -eq $false)) { $extract = $false }
    if ($extract -and ($downloadPath -like "*.zip")) {
        Log-Info "Extracting $($ToolConfig.Name)..."
        try {
            $archiveHash = (Get-FileHash -Algorithm MD5 -Path $downloadPath).Hash
            Expand-Archive -Path $downloadPath -DestinationPath $outputFolder -Force
            Remove-Item -Path $downloadPath
            Log-Debug "Extraction complete."
        }
        catch {
            Log-Error "Extraction failed for $downloadPath. Exception: $_"
        }
    }
    $manifest = Get-FileManifest -Folder $outputFolder
    if ($archiveHash) {
        $manifest[[System.IO.Path]::GetFileName($downloadPath)] = $archiveHash
    }
    $downloadedFileParam = $downloadPath
    if ($extract -and ($downloadPath -like "*.zip")) { $downloadedFileParam = "" }
    
    # Write the marker file for the downloaded branch ZIP.
    Write-MarkerFile -OutputFolder $outputFolder `
                     -ToolName $ToolConfig.Name `
                     -DownloadMethod $ToolConfig.DownloadMethod `
                     -DownloadURL $zipUrl `
                     -Version $branch `
                     -CommitHash "" `
                     -DownloadedFile $downloadedFileParam `
                     -ExtractionLocation $outputFolder `
                     -Manifest $manifest
}

function Download-SpecificFileTool {
    param (
        [Parameter(Mandatory)]
        $ToolConfig,
        [Parameter(Mandatory)]
        [string]$ToolsDirectory
    )
    # Determine the output folder for the specific file.
    if (-not [string]::IsNullOrEmpty($ToolConfig.OutputFolder)) {
        $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $ToolConfig.OutputFolder $ToolConfig.Name)
    }
    else {
        $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath $ToolConfig.Name
    }
    if (-not (Test-Path -Path $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory | Out-Null
        Log-Debug "Created output folder: $outputFolder"
    }
    
    # Construct the URL for the specific file to download.
    if ($ToolConfig.ContainsKey("SpecificFilePath") -and -not [string]::IsNullOrEmpty($ToolConfig.SpecificFilePath)) {
        if ($ToolConfig.RepoUrl -like "https://github.com/*") {
            # Convert the GitHub URL to its raw counterpart.
            $rawRepoUrl = $ToolConfig.RepoUrl -replace "https://github.com/", "https://raw.githubusercontent.com/"
            $cleanPath = $ToolConfig.SpecificFilePath -replace "^/raw", ""
            $fileUrl = "$rawRepoUrl$cleanPath"
        }
        else {
            $fileUrl = "$($ToolConfig.RepoUrl)$($ToolConfig.SpecificFilePath)"
        }
        # Get the filename from the specified file path.
        $downloadName = [System.IO.Path]::GetFileName($ToolConfig.SpecificFilePath)
    }
    else {
        # If no specific file path is given, use the RepoUrl.
        $fileUrl = $ToolConfig.RepoUrl
        $downloadName = [System.IO.Path]::GetFileName($ToolConfig.RepoUrl)
    }
    
    Log-Debug "Constructed URL: $fileUrl"
    $downloadPath = Join-Path -Path $outputFolder -ChildPath $downloadName
    Log-Info "Downloading $($ToolConfig.Name)..."
    $headers = @{ "User-Agent" = "PowerShell" }
    if (-not [string]::IsNullOrEmpty($GitHubPAT)) { $headers["Authorization"] = "token $GitHubPAT" }
    try {
        # Download the specific file.
        Invoke-WebRequest -Uri $fileUrl -OutFile $downloadPath -Headers $headers
        Log-Debug "Downloaded to $downloadPath"
    }
    catch {
        Log-Error "Failed to download file for $($ToolConfig.Name). Exception: $_"
        return
    }
    
    $archiveHash = $null
    $extract = $true
    # Check if extraction is desired.
    if (($ToolConfig.ContainsKey("Extract")) -and ($ToolConfig.Extract -eq $false)) { $extract = $false }
    if ($extract -and ($downloadPath -like "*.zip")) {
        Log-Info "Extracting $($ToolConfig.Name)..."
        try {
            $archiveHash = (Get-FileHash -Algorithm MD5 -Path $downloadPath).Hash
            Expand-Archive -Path $downloadPath -DestinationPath $outputFolder -Force
            Remove-Item -Path $downloadPath
            Log-Debug "Extraction complete."
        }
        catch {
            Log-Error "Extraction failed for $downloadPath. Exception: $_"
        }
    }
    # Build the manifest and write the marker file.
    $manifest = Get-FileManifest -Folder $outputFolder
    if ($archiveHash) {
        $manifest[[System.IO.Path]::GetFileName($downloadPath)] = $archiveHash
    }
    $downloadedFileParam = $downloadPath
    if ($extract -and ($downloadPath -like "*.zip")) { $downloadedFileParam = "" }
    
    Write-MarkerFile -OutputFolder $outputFolder `
                     -ToolName $ToolConfig.Name `
                     -DownloadMethod $ToolConfig.DownloadMethod `
                     -DownloadURL $fileUrl `
                     -Version "" `
                     -CommitHash "" `
                     -DownloadedFile $downloadedFileParam `
                     -ExtractionLocation $outputFolder `
                     -Manifest $manifest
}

$AssetPatterns = @{
    win64 = '(?i)win(?:dows)?[-_](x64|amd64)(?![-_](live|aarch64))'
    win32 = '(?i)(win(dows)?).*?(32|x86)'
    linux = '(?i)(linux|lin)'
    macos = '(?i)(mac|osx|darwin)'
}

# -----------------------------------------------
# Dispatcher: Loop Through Tools and Download
# -----------------------------------------------
# Loop through each tool defined in the YAML configuration and process it.
foreach ($tool in $tools) {
    Write-Host "===========================================" -ForegroundColor White
    Log-Info "Working on tool: $($tool.Name)"
    
    # Determine the output folder for this tool.
    if (-not [string]::IsNullOrEmpty($tool.OutputFolder)) {
        $toolOutputFolder = Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $tool.OutputFolder $tool.Name)
    }
    else {
        $toolOutputFolder = Join-Path -Path $ToolsDirectory -ChildPath $tool.Name
    }
    
    # Define the path to the marker file for this tool.
    $markerFile = Join-Path $toolOutputFolder ".downloaded.json"
    
    # Decide on action based on ForceDownload, Update, or normal mode.
    if ($ForceDownload) {
        # In ForceDownload mode, remove managed files if the marker file exists.
        if (Test-Path $toolOutputFolder) {
            if (Test-Path $markerFile) {
                Log-Info "Force download: Removing managed files for $($tool.Name)."
                Remove-ManagedFiles -OutputFolder $toolOutputFolder
            }
            else {
                Log-Info "Force download: No marker file found for $($tool.Name); preserving user files."
            }
        }
    }
    elseif ($Update) {
        # In Update mode, respect the skipdownload flag.
        if ($tool.skipdownload) {
            Log-Info "Skipping $($tool.Name) because skipdownload flag is set."
            continue
        }
        if (Test-Path $toolOutputFolder) {
            if (Test-Path $markerFile) {
                Log-Info "Update mode: Removing managed files for $($tool.Name) to update."
                Remove-ManagedFiles -OutputFolder $toolOutputFolder
            }
            else {
                Log-Info "Update mode: No marker file found for $($tool.Name); preserving user files."
            }
        }
    }
    else {
        # In normal mode, if skipdownload is set or the marker file exists, skip processing.
        if ($tool.skipdownload) {
            Log-Info "Skipping $($tool.Name) (skipdownload flag set)."
            continue
        }
        if (Test-Path $markerFile) {
            Log-Info "$($tool.Name) is already downloaded, skipping."
            continue
        }
    }
    
    # Dispatch to the correct download method based on the tool's configuration.
    switch ($tool.DownloadMethod) {
        "gitClone" {
            Download-GitCloneTool -ToolConfig $tool -ToolsDirectory $ToolsDirectory
        }
        "latestRelease" {
            Download-LatestReleaseTool -ToolConfig $tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT -AssetPatterns $AssetPatterns
        }
        "branchZip" {
            Download-BranchZipTool -ToolConfig $tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT
        }
        "specificFile" {
            Download-SpecificFileTool -ToolConfig $tool -ToolsDirectory $ToolsDirectory
        }
        default {
            Log-Error "Download method '$($tool.DownloadMethod)' not recognized for $($tool.Name)."
        }
    }
    Log-Info "Finished working on $($tool.Name)."
}
