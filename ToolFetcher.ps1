# =====================================================
# ToolFetcher
#
# A tool for fetching DFIR and other GitHub tools.
#
# Author: Kevin Stokes (https://www.linkedin.com/in/dfir-kev/)
# Version: 1.1.0
# License: MIT
# =====================================================

# =====================================================
# User Configurable Variables
# =====================================================

[CmdletBinding()]
param(
    # Supply a local file (e.g., "tools.yaml") or a URL (e.g., a GitHub raw URL).
    [Parameter(Mandatory=$false)]
    [string]$ToolsFile = "https://raw.githubusercontent.com/kev365/ToolFetcher/refs/heads/main/tools.yaml"
)

# Folder where all tools will be stored.
# If you leave this variable empty, the script will prompt you for a folder location.
$toolsFolder = ""  	# <-- Change this as needed.

# Set this to $true to force re-download and overwrite any existing tool output directories.
$ForceDownload = $false  	# <-- Set to $true to force re-download.

# Set this to $true to show detailed debug output.
$VerboseOutput = $false

# GitHub Personal Access Token – recommended to avoid rate limits.
# If you leave this empty, the script will work unauthenticated.
$GitHubPAT = ""          	# Only needed if you have rate limit issues, probably rare.

# =====================================================
# Asset Pattern Mapping
# =====================================================
# Global mapping for asset types to regex patterns.
$AssetPatterns = @{
    win64 = '(?i)win(?:dows)?[-_](x64|amd64)(?![-_](live|aarch64))'  	# Matches "Windows_x64", "win64", or even just "amd64"
    win32 = '(?i)(win(dows)?).*?(32|x86)'            					# Matches "Windows_x86", "win32", etc.
    linux = '(?i)(linux|lin)'                        					# Matches "linux", "Linux", "lin", "Lin"
    macos = '(?i)(mac|osx|darwin)'                  					# Matches "mac", "OSX", "darwin"
}

# =====================================================
# Global Logging Setup
# =====================================================
function Log-Debug {
    param([string]$Message)
    if ($VerboseOutput) { Write-Host "[DEBUG] $Message" -ForegroundColor DarkGray }
}
function Log-Info {
    param([string]$Message)
    Write-Host "[INFO]  $Message" -ForegroundColor Cyan
}
function Log-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}
function Log-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# =====================================================
# Tools Configuration: Load from YAML File
# =====================================================
# This block replaces the hard-coded $tools array.
# The YAML file is expected to contain the same structure as your previous tools configuration.
# It can either be a top-level array or an object with a "tools" key.
if ($ToolsFile -match '^https?://') {
    Log-Info "Fetching tools configuration from URL: $ToolsFile"
    try {
        $yamlContent = (Invoke-WebRequest -Uri $ToolsFile -UseBasicParsing).Content
    }
    catch {
        Log-Error "Failed to fetch YAML from URL: $ToolsFile. Exception: $_"
        exit 1
    }
}
else {
    # If not an absolute path, try the same folder as the script.
    if (-not (Test-Path $ToolsFile)) {
        if ($PSScriptRoot) {
            $localPath = Join-Path $PSScriptRoot $ToolsFile
        }
        else {
            $localPath = $ToolsFile
        }
        if (Test-Path $localPath) {
            $ToolsFile = $localPath
        }
        else {
            Log-Error "YAML configuration file not found: $ToolsFile"
            exit 1
        }
    }
    try {
        $yamlContent = Get-Content -Path $ToolsFile -Raw
    }
    catch {
        Log-Error "Failed to read YAML file at: $ToolsFile. Exception: $_"
        exit 1
    }
}

# Check for the powershell-yaml module and install if not found.
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host "[INFO] The 'powershell-yaml' module is not installed. Attempting to install it..." -ForegroundColor Cyan
    try {
        # Install the module for the current user to avoid permission issues.
        Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowClobber
        Write-Host "[INFO] Successfully installed the 'powershell-yaml' module." -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to install the 'powershell-yaml' module. Please install it manually using: Install-Module powershell-yaml" -ForegroundColor Red
        exit 1
    }
}

# Import the module
Import-Module powershell-yaml -ErrorAction Stop

try {
    $toolsConfig = $yamlContent | ConvertFrom-Yaml
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

# =====================================================
# Ensure the Tools Folder Exists
# =====================================================
if ([string]::IsNullOrEmpty($toolsFolder)) {
    $toolsFolder = Read-Host "The 'toolsFolder' variable is empty. Please provide a location for the tools folder"
}

if (-not (Test-Path -Path $toolsFolder)) {
    try {
        New-Item -Path $toolsFolder -ItemType Directory -Force | Out-Null
        Log-Info "Created tools folder: $toolsFolder"
    }
    catch {
        Log-Error "Failed to create tools folder at '$toolsFolder'. Exception: $_"
        exit 1
    }
}

# =====================================================
# Helper Function: Write Marker File with Metadata
# =====================================================
function Write-MarkerFile {
    param (
        [Parameter(Mandatory)] $OutputFolder,
        [Parameter(Mandatory)] $ToolName,
        [Parameter(Mandatory)] $DownloadMethod,
        [Parameter(Mandatory)] $DownloadURL,
        [Parameter()] $Version = "",
        [Parameter()] $CommitHash = "",
        [Parameter()] $DownloadedFile = "",
        [Parameter()] $ExtractionLocation = ""
    )
    $markerFile = Join-Path $OutputFolder ".downloaded.json"
    $metadata = @{
        Tool               = $ToolName
        Timestamp          = (Get-Date).ToString("o")   # ISO8601 format
        DownloadMethod     = $DownloadMethod
        DownloadURL        = $DownloadURL
        Version            = $Version
        CommitHash         = $CommitHash
        DownloadedFile     = $DownloadedFile
        ExtractionLocation = $ExtractionLocation
    }
    $metadata | ConvertTo-Json -Depth 3 | Out-File -FilePath $markerFile -Force
    Log-Debug "Marker file created at $markerFile"
}

# =====================================================
# Functions for Download Methods
# =====================================================
function Download-GitCloneTool {
    param (
        [Parameter(Mandatory)] $ToolConfig,
        [Parameter(Mandatory)] $ToolsFolder
    )
    # Determine the unique output folder for this tool.
    if (-not [string]::IsNullOrEmpty($ToolConfig.OutputFolder)) {
        $outputFolder = Join-Path -Path $ToolsFolder -ChildPath (Join-Path $ToolConfig.OutputFolder $ToolConfig.Name)
    }
    else {
        $outputFolder = Join-Path -Path $ToolsFolder -ChildPath $ToolConfig.Name
    }
    Log-Info "Cloning $($ToolConfig.Name)..."
    if (-not (Test-Path -Path $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
        Log-Debug "Created output folder: $outputFolder"
    }
    git clone $ToolConfig.RepoUrl --branch $ToolConfig.Branch $outputFolder
    Log-Debug "Clone complete for $($ToolConfig.Name)."
    
    # Attempt to retrieve commit hash.
    $commitHash = ""
    try {
        $commitHash = (& git -C $outputFolder rev-parse HEAD).Trim()
    }
    catch {
        Log-Warning "Could not retrieve commit hash for $($ToolConfig.Name)."
    }
    Write-MarkerFile -OutputFolder $outputFolder `
                     -ToolName $ToolConfig.Name `
                     -DownloadMethod $ToolConfig.DownloadMethod `
                     -DownloadURL $ToolConfig.RepoUrl `
                     -Version $ToolConfig.Branch `
                     -CommitHash $commitHash `
                     -DownloadedFile "" `
                     -ExtractionLocation $outputFolder
}

function Download-LatestReleaseTool {
    param (
        [Parameter(Mandatory)] $ToolConfig,
        [Parameter(Mandatory)] $ToolsFolder,
        [Parameter(Mandatory)] $GitHubPAT,
        [Parameter(Mandatory)] $AssetPatterns
    )
    $apiRepoUrl = $ToolConfig.RepoUrl -replace "https://github.com/", "https://api.github.com/repos/"
    $releaseUri = "$apiRepoUrl/releases/latest"
    Log-Debug "Using API endpoint: $releaseUri for $($ToolConfig.Name)"
    
    $headers = @{ "User-Agent" = "PowerShell" }
    if (-not [string]::IsNullOrEmpty($GitHubPAT)) { $headers["Authorization"] = "token $GitHubPAT" }
    
    try {
        $releaseInfo = Invoke-RestMethod -Uri $releaseUri -Headers $headers
        Log-Debug "Retrieved release info. Assets count: $($releaseInfo.assets.Count)"
    }
    catch {
        Log-Error "Failed to get release info for $($ToolConfig.Name). Exception: $_"
        return
    }
    
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
    
    $asset = $assets | Select-Object -First 1
    if ($asset) {
        if (-not [string]::IsNullOrEmpty($ToolConfig.OutputFolder)) {
            $outputFolder = Join-Path -Path $ToolsFolder -ChildPath (Join-Path $ToolConfig.OutputFolder $ToolConfig.Name)
        }
        else {
            $outputFolder = Join-Path -Path $ToolsFolder -ChildPath $ToolConfig.Name
        }
        if (-not (Test-Path -Path $outputFolder)) {
            New-Item -Path $outputFolder -ItemType Directory | Out-Null
            Log-Debug "Created output folder: $outputFolder"
        }
        $downloadPath = Join-Path -Path $outputFolder -ChildPath $asset.name
        Log-Info "Downloading $($ToolConfig.Name)..."
        try {
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -Headers $headers
            Log-Debug "Downloaded to $downloadPath"
        }
        catch {
            Log-Error "Failed to download asset for $($ToolConfig.Name). Exception: $_"
            return
        }
        
        $extract = $true
        if (($ToolConfig.ContainsKey("Extract")) -and ($ToolConfig.Extract -eq $false)) { $extract = $false }
        if ($extract -and ($downloadPath -like "*.zip")) {
            Log-Info "Extracting $($ToolConfig.Name)..."
            try {
                Expand-Archive -Path $downloadPath -DestinationPath $outputFolder -Force
                Remove-Item -Path $downloadPath
                Log-Debug "Extraction complete."
            }
            catch {
                Log-Error "Extraction failed for $downloadPath. Exception: $_"
            }
        }
        $version = $releaseInfo.tag_name
        Write-MarkerFile -OutputFolder $outputFolder `
                         -ToolName $ToolConfig.Name `
                         -DownloadMethod $ToolConfig.DownloadMethod `
                         -DownloadURL $asset.browser_download_url `
                         -Version $version `
                         -CommitHash "" `
                         -DownloadedFile $downloadPath `
                         -ExtractionLocation $outputFolder
    }
    else {
        Log-Warning "No matching asset found for $($ToolConfig.Name)."
    }
}

function Download-BranchZipTool {
    param (
        [Parameter(Mandatory)] $ToolConfig,
        [Parameter(Mandatory)] $ToolsFolder,
        [Parameter(Mandatory)] $GitHubPAT
    )
    $branch = if (-not [string]::IsNullOrEmpty($ToolConfig.Branch)) { $ToolConfig.Branch } else { "master" }
    $zipUrl = "$($ToolConfig.RepoUrl)/archive/refs/heads/$branch.zip"
    Log-Info "Downloading branch zip for $($ToolConfig.Name)..."
    
    if (-not [string]::IsNullOrEmpty($ToolConfig.OutputFolder)) {
        $outputFolder = Join-Path -Path $ToolsFolder -ChildPath (Join-Path $ToolConfig.OutputFolder $ToolConfig.Name)
    }
    else {
        $outputFolder = Join-Path -Path $ToolsFolder -ChildPath $ToolConfig.Name
    }
    if (-not (Test-Path -Path $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory | Out-Null
        Log-Debug "Created output folder: $outputFolder"
    }
    $fileName = "$($ToolConfig.Name)-$branch.zip"
    $downloadPath = Join-Path -Path $outputFolder -ChildPath $fileName
    Log-Debug "Downloading branch zip to $downloadPath"
    
    $headers = @{ "User-Agent" = "PowerShell" }
    if (-not [string]::IsNullOrEmpty($GitHubPAT)) { $headers["Authorization"] = "token $GitHubPAT" }
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $downloadPath -Headers $headers
        Log-Debug "Downloaded branch zip to $downloadPath"
    }
    catch {
        Log-Error "Failed to download branch zip for $($ToolConfig.Name). Exception: $_"
        return
    }
    
    $extract = $true
    if (($ToolConfig.ContainsKey("Extract")) -and ($ToolConfig.Extract -eq $false)) { $extract = $false }
    if ($extract -and ($downloadPath -like "*.zip")) {
        Log-Info "Extracting $($ToolConfig.Name)..."
        try {
            Expand-Archive -Path $downloadPath -DestinationPath $outputFolder -Force
            Remove-Item -Path $downloadPath
            Log-Debug "Extraction complete."
        }
        catch {
            Log-Error "Extraction failed for $downloadPath. Exception: $_"
        }
    }
    Write-MarkerFile -OutputFolder $outputFolder `
                     -ToolName $ToolConfig.Name `
                     -DownloadMethod $ToolConfig.DownloadMethod `
                     -DownloadURL $zipUrl `
                     -Version $branch `
                     -CommitHash "" `
                     -DownloadedFile $downloadPath `
                     -ExtractionLocation $outputFolder
}

function Download-SpecificFileTool {
    param (
        [Parameter(Mandatory)] $ToolConfig,
        [Parameter(Mandatory)] $ToolsFolder
    )
    if (-not [string]::IsNullOrEmpty($ToolConfig.OutputFolder)) {
        $outputFolder = Join-Path -Path $ToolsFolder -ChildPath (Join-Path $ToolConfig.OutputFolder $ToolConfig.Name)
    }
    else {
        $outputFolder = Join-Path -Path $ToolsFolder -ChildPath $ToolConfig.Name
    }
    if (-not (Test-Path -Path $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory | Out-Null
        Log-Debug "Created output folder: $outputFolder"
    }
    
    if ($ToolConfig.ContainsKey("SpecificFilePath") -and -not [string]::IsNullOrEmpty($ToolConfig.SpecificFilePath)) {
        if ($ToolConfig.RepoUrl -like "https://github.com/*") {
            $rawRepoUrl = $ToolConfig.RepoUrl -replace "https://github.com/", "https://raw.githubusercontent.com/"
            $cleanPath = $ToolConfig.SpecificFilePath -replace "^/raw", ""
            $fileUrl = "$rawRepoUrl$cleanPath"
        }
        else {
            $fileUrl = "$($ToolConfig.RepoUrl)$($ToolConfig.SpecificFilePath)"
        }
        $downloadName = [System.IO.Path]::GetFileName($ToolConfig.SpecificFilePath)
    }
    else {
        $fileUrl = $ToolConfig.RepoUrl
        $downloadName = [System.IO.Path]::GetFileName($ToolConfig.RepoUrl)
    }
    
    Log-Debug "Constructed URL: $fileUrl"
    $downloadPath = Join-Path -Path $outputFolder -ChildPath $downloadName
    Log-Info "Downloading $($ToolConfig.Name)..."
    $headers = @{ "User-Agent" = "PowerShell" }
    if (-not [string]::IsNullOrEmpty($GitHubPAT)) { $headers["Authorization"] = "token $GitHubPAT" }
    try {
        Invoke-WebRequest -Uri $fileUrl -OutFile $downloadPath -Headers $headers
        Log-Debug "Downloaded to $downloadPath"
    }
    catch {
        Log-Error "Failed to download file for $($ToolConfig.Name). Exception: $_"
        return
    }
    
    $extract = $true
    if (($ToolConfig.ContainsKey("Extract")) -and ($ToolConfig.Extract -eq $false)) { $extract = $false }
    if ($extract -and ($downloadPath -like "*.zip")) {
        Log-Info "Extracting $($ToolConfig.Name)..."
        try {
            Expand-Archive -Path $downloadPath -DestinationPath $outputFolder -Force
            Remove-Item -Path $downloadPath
            Log-Debug "Extraction complete."
        }
        catch {
            Log-Error "Extraction failed for $downloadPath. Exception: $_"
        }
    }
    Write-MarkerFile -OutputFolder $outputFolder `
                     -ToolName $ToolConfig.Name `
                     -DownloadMethod $ToolConfig.DownloadMethod `
                     -DownloadURL $fileUrl `
                     -Version "" `
                     -CommitHash "" `
                     -DownloadedFile $downloadPath `
                     -ExtractionLocation $outputFolder
}

# =====================================================
# Dispatcher: Loop Through Tools and Download
# =====================================================
foreach ($tool in $tools) {
    Write-Host "===========================================" -ForegroundColor White
    Log-Info "Processing tool: $($tool.Name)"
    
    # Skip download if the tool is marked to be skipped.
    if ($tool.skipdownload) {
        Log-Info "Skipping $($tool.Name) (skipdownload flag set)."
        continue
    }
    
    # Determine the unique folder for the tool.
    switch ($tool.DownloadMethod) {
        "gitClone" { 
            if (-not [string]::IsNullOrEmpty($tool.OutputFolder)) {
                $toolOutputFolder = Join-Path -Path $toolsFolder -ChildPath (Join-Path $tool.OutputFolder $tool.Name)
            }
            else {
                $toolOutputFolder = Join-Path -Path $toolsFolder -ChildPath $tool.Name
            }
        }
        "latestRelease" { 
            if (-not [string]::IsNullOrEmpty($tool.OutputFolder)) {
                $toolOutputFolder = Join-Path -Path $toolsFolder -ChildPath (Join-Path $tool.OutputFolder $tool.Name)
            }
            else {
                $toolOutputFolder = Join-Path -Path $toolsFolder -ChildPath $tool.Name
            }
        }
        "branchZip" {
            if (-not [string]::IsNullOrEmpty($tool.OutputFolder)) {
                $toolOutputFolder = Join-Path -Path $toolsFolder -ChildPath (Join-Path $tool.OutputFolder $tool.Name)
            }
            else {
                $toolOutputFolder = Join-Path -Path $toolsFolder -ChildPath $tool.Name
            }
        }
        "specificFile" {
            if (-not [string]::IsNullOrEmpty($tool.OutputFolder)) {
                $toolOutputFolder = Join-Path -Path $toolsFolder -ChildPath (Join-Path $tool.OutputFolder $tool.Name)
            }
            else {
                $toolOutputFolder = Join-Path -Path $toolsFolder -ChildPath $tool.Name
            }
        }
        default { $toolOutputFolder = $toolsFolder }
    }
    
    # Check for an existing marker file.
    $markerFile = Join-Path $toolOutputFolder ".downloaded.json"
    if ((Test-Path $markerFile) -and (-not $ForceDownload)) {
        Log-Info "$($tool.Name) is already downloaded. Skipping."
        continue
    }
    elseif ((Test-Path $toolOutputFolder) -and $ForceDownload) {
        Log-Info "Force download: Removing existing folder for $($tool.Name)."
        Remove-Item -Path $toolOutputFolder -Recurse -Force
    }
    
    switch ($tool.DownloadMethod) {
        "gitClone" {
            Download-GitCloneTool -ToolConfig $tool -ToolsFolder $toolsFolder
        }
        "latestRelease" {
            Download-LatestReleaseTool -ToolConfig $tool -ToolsFolder $toolsFolder -GitHubPAT $GitHubPAT -AssetPatterns $AssetPatterns
        }
        "branchZip" {
            Download-BranchZipTool -ToolConfig $tool -ToolsFolder $toolsFolder -GitHubPAT $GitHubPAT
        }
        "specificFile" {
            Download-SpecificFileTool -ToolConfig $tool -ToolsFolder $toolsFolder
        }
        default {
            Log-Error "Download method '$($tool.DownloadMethod)' not recognized for $($tool.Name)."
        }
    }
    Log-Info "Finished processing $($tool.Name)."
}
