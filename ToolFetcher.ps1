# =====================================================
# ToolFetcher
#
# A tool for fetching DFIR and other GitHub tools.
#
# Author: Kevin Stokes
# Version: 1.2.3
# License: MIT
# =====================================================

# Enable advanced functions with cmdlet binding.
[CmdletBinding()]
param (
    [Parameter(HelpMessage = 'Path to the YAML file containing tool definitions.')]
    [Alias('f')]
    [string]$ToolsFile = "tools.yaml",
    
    [Parameter(HelpMessage = 'Directory where tools will be downloaded.')]
    [Alias('d')]
    [string]$ToolsDirectory = "",
    
    [Parameter(HelpMessage = 'Force re-download and overwrite any existing tool output directories.')]
    [Alias('force')]
    [switch]$ForceDownload = $false,
    
    [Parameter(HelpMessage = 'Update tools. If you supply one or more tool names (comma-separated), then only those tools will be updated.')]
    [Alias('u')]
    [string[]]$Update,
    
    [Parameter(HelpMessage = 'Show debug-level output')]
    [Alias('v')]
    [switch]$VerboseOutput = $false,
    
    [Parameter(HelpMessage = 'Show trace-level output (most detailed)')]
    [Alias('vv')]
    [switch]$TraceOutput = $false,
    
    [Parameter(HelpMessage = 'Enable logging to a file. Specify a path or leave empty for default log file.')]
    [Alias('log')]
    [string]$LogFile = "",
    
    [Parameter(HelpMessage = 'GitHub Personal Access Token - to avoid rate limits, if needed.')]
    [Alias('pat')]
    [string]$GitHubPAT = "",
    
    [Parameter(HelpMessage = 'List all available tools in the configuration file')]
    [Alias('list')]
    [switch]$ListTools = $false
)

# Initialize logging
if ($TraceOutput) {
    $script:LoggingLevel = [LogLevel]::Trace
}
elseif ($VerboseOutput) {
    $script:LoggingLevel = [LogLevel]::Debug
}

# Enable file logging if requested
if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
    Enable-FileLogging -LogPath $LogFile
}

Log-Info "ToolFetcher v1.2.3 started"
Log-Info "Log level set to: $($script:LoggingLevel)"

# -----------------------------------------------
# Failsafe for ToolsFile
# -----------------------------------------------
$defaultToolsFileUrl = "https://raw.githubusercontent.com/kev365/ToolFetcher/refs/heads/main/tools.yaml"
if ($ToolsFile -match '^https?://') {
    try {
        $response = Invoke-WebRequest -Uri $ToolsFile -Method Head -UseBasicParsing -ErrorAction Stop
        Write-Host "[INFO] Using user-specified URL for tools file: $ToolsFile" -ForegroundColor Cyan
    }
    catch {
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
    if ([System.IO.Path]::IsPathRooted($ToolsFile)) {
        if (Test-Path -Path $ToolsFile) {
            Write-Host "[INFO] Using user-specified local tools file: $ToolsFile" -ForegroundColor Cyan
        }
        else {
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
        $localToolsFile = Join-Path $PSScriptRoot $ToolsFile
        if (Test-Path -Path $localToolsFile) {
            Write-Host "[INFO] Using local tools file: $localToolsFile" -ForegroundColor Cyan
            $ToolsFile = $localToolsFile
        }
        else {
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
# Logging Configuration
# -----------------------------------------------

# Define log levels
enum LogLevel {
    Error = 0    # Critical errors that prevent operation
    Warning = 1  # Issues that don't stop execution but may cause problems
    Info = 2     # Normal operational information
    Debug = 3    # Detailed information for troubleshooting
    Trace = 4    # Very detailed tracing information
}

# Default log level
[LogLevel]$script:LoggingLevel = [LogLevel]::Info

# Log file path (optional)
$script:LogFilePath = $null

# Set log level based on parameters
if ($VerboseOutput) {
    $script:LoggingLevel = [LogLevel]::Debug
}
if ($TraceOutput) {
    $script:LoggingLevel = [LogLevel]::Trace
}

# Main logging function that handles different log levels, console output, and file logging
function Write-ToolLog {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][LogLevel]$Level = [LogLevel]::Info,
        [Parameter(Mandatory=$false)][switch]$NoConsole = $false,
        [Parameter(Mandatory=$false)][ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    
    # Skip if message level is higher than current logging level
    if ([int]$Level -gt [int]$script:LoggingLevel) {
        return
    }
    
    # Format timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Format log level prefix
    $levelPrefix = switch ($Level) {
        ([LogLevel]::Error)   { "[ERROR]  " }
        ([LogLevel]::Warning) { "[WARNING]" }
        ([LogLevel]::Info)    { "[INFO]   " }
        ([LogLevel]::Debug)   { "[DEBUG]  " }
        ([LogLevel]::Trace)   { "[TRACE]  " }
        default               { "[INFO]   " }
    }
    
    # Format full message
    $fullMessage = "$timestamp $levelPrefix $Message"
    
    # Write to console if not suppressed
    if (-not $NoConsole) {
        $originalColor = $host.UI.RawUI.ForegroundColor
        
        # Set color based on level if not explicitly specified
        if ($PSBoundParameters.ContainsKey('ForegroundColor') -eq $false) {
            $ForegroundColor = switch ($Level) {
                ([LogLevel]::Error)   { [ConsoleColor]::Red }
                ([LogLevel]::Warning) { [ConsoleColor]::Yellow }
                ([LogLevel]::Info)    { [ConsoleColor]::White }
                ([LogLevel]::Debug)   { [ConsoleColor]::Cyan }
                ([LogLevel]::Trace)   { [ConsoleColor]::Gray }
                default               { [ConsoleColor]::White }
            }
        }
        
        $host.UI.RawUI.ForegroundColor = $ForegroundColor
        Write-Host $fullMessage
        $host.UI.RawUI.ForegroundColor = $originalColor
    }
    
    # Write to log file if configured
    if ($script:LogFilePath) {
        try {
            Add-Content -Path $script:LogFilePath -Value $fullMessage -ErrorAction SilentlyContinue
        }
        catch {
            # If we can't write to the log file, output a console warning
            # but only if we haven't already suppressed console output
            if (-not $NoConsole) {
                $originalColor = $host.UI.RawUI.ForegroundColor
                $host.UI.RawUI.ForegroundColor = [ConsoleColor]::Yellow
                Write-Host "Failed to write to log file: $_"
                $host.UI.RawUI.ForegroundColor = $originalColor
            }
        }
    }
}

# Create convenience functions for backward compatibility
function Log-Error {
    param ([string]$Message)
    Write-ToolLog -Message $Message -Level ([LogLevel]::Error)
}

function Log-Warning {
    param ([string]$Message)
    Write-ToolLog -Message $Message -Level ([LogLevel]::Warning)
}

function Log-Info {
    param ([string]$Message)
    Write-ToolLog -Message $Message -Level ([LogLevel]::Info)
}

function Log-Debug {
    param ([string]$Message)
    Write-ToolLog -Message $Message -Level ([LogLevel]::Debug)
}

function Log-Trace {
    param ([string]$Message)
    Write-ToolLog -Message $Message -Level ([LogLevel]::Trace)
}

function Enable-FileLogging {
    param (
        [Parameter(Mandatory=$false)][string]$LogPath = "",
        [Parameter(Mandatory=$false)][switch]$AppendToExisting = $false
    )
    
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = Join-Path $PSScriptRoot "ToolFetcher_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    }
    
    try {
        # Create directory if it doesn't exist
        $logDir = Split-Path -Path $LogPath -Parent
        if (-not (Test-Path -Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        # Create or clear the log file
        if (-not $AppendToExisting -and (Test-Path -Path $LogPath)) {
            Remove-Item -Path $LogPath -Force
        }
        
        # Test if we can write to the file
        Add-Content -Path $LogPath -Value "Log started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ErrorAction Stop
        
        $script:LogFilePath = $LogPath
        Log-Info "File logging enabled: $LogPath"
        return $true
    }
    catch {
        Write-Host "Failed to enable file logging: $_" -ForegroundColor Yellow
        return $false
    }
}

# -----------------------------------------------
# Global Logging Setup
# -----------------------------------------------
function Log-Debug { param ([string]$Message) if ($VerboseOutput) { Write-Host "[DEBUG] $Message" -ForegroundColor DarkGray } }
function Log-Info  { param ([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Log-Warning { param ([string]$Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Log-Error { param ([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# -----------------------------------------------
# Function: Validate GitHub Personal Access Token
# -----------------------------------------------
function Validate-GitHubPAT {
    param ([Parameter(Mandatory = $true)][string]$Token)
    $headers = @{ "Authorization" = "token $Token"; "User-Agent" = "PowerShell" }
    try {
        $response = Invoke-WebRequest -Uri "https://api.github.com/user" -Headers $headers -ErrorAction Stop
        Log-Debug "GitHub PAT validated for user: $($response.login)"
        return $true
    }
    catch {
        Log-Error "GitHub PAT validation failed: $_"
        return $false
    }
}

# -----------------------------------------------
# Helper Function: Build File Manifest
# -----------------------------------------------
function Get-FileManifest {
    param ([Parameter(Mandatory = $true)][string]$Folder)
    $manifest = @{}
    $files = Get-ChildItem -Recurse -File -Path $Folder
    foreach ($file in $files) {
        if ($file.Name -eq ".downloaded.json") { continue }
        $relativePath = $file.FullName.Substring($Folder.Length + 1)
        $hash = (Get-FileHash -Algorithm MD5 -Path $file.FullName).Hash
        $manifest[$relativePath] = $hash
    }
    return $manifest
}

# -----------------------------------------------
# Helper Function: Write Marker File with Metadata
# -----------------------------------------------
function Write-MarkerFile {
    param (
        [Parameter(Mandatory)]$OutputFolder,
        [Parameter(Mandatory)]$ToolName,
        [Parameter(Mandatory)]$DownloadMethod,
        [Parameter(Mandatory)]$DownloadURL,
        [Parameter()]$Version = "",
        [Parameter()]$CommitHash = "",
        [Parameter()]$DownloadedFile = "",
        [Parameter()]$ExtractionLocation = "",
        [Parameter()]$Manifest = $null
    )
    $markerFile = Join-Path $OutputFolder ".downloaded.json"
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
    $metadata | ConvertTo-Json -Depth 5 | Out-File -FilePath $markerFile -Force
    Log-Debug "Marker file created at $markerFile"
}

# -----------------------------------------------
# Helper Function: Remove Managed Files Using Marker File
# -----------------------------------------------
function Remove-ManagedFiles {
    param ([Parameter(Mandatory=$true)][string]$OutputFolder)
    $markerFile = Join-Path $OutputFolder ".downloaded.json"
    if (Test-Path $markerFile) {
        try {
            $metadata = Get-Content -Path $markerFile | ConvertFrom-Json
            if ($metadata.Manifest) {
                foreach ($relativePath in $metadata.Manifest.Keys) {
                    $fileToRemove = Join-Path $OutputFolder $relativePath
                    if (Test-Path $fileToRemove) {
                        Remove-Item -Path $fileToRemove -Force -Recurse -ErrorAction SilentlyContinue
                        Log-Debug "Removed managed file: $fileToRemove"
                    }
                }
            }
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
# Global Staging Helper for ZIP Archives
# -----------------------------------------------
function Process-ZipStaging {
    param (
        [Parameter(Mandatory=$true)][string]$ZipUrl,
        [Parameter(Mandatory=$true)][string]$ToolName,
        [Parameter(Mandatory=$true)][string]$Version
    )
    
    Log-Trace "Starting ZIP staging process for $ToolName from $ZipUrl"
    $stagingFolder = Join-Path $PSScriptRoot "tmp"
    if (-not (Test-Path $stagingFolder)) { 
        Log-Debug "Creating staging folder: $stagingFolder"
        New-Item -Path $stagingFolder -ItemType Directory | Out-Null 
    }
    
    # Use the original filename from the URL without renaming.
    $fileName = Split-Path $ZipUrl -Leaf
    $tempZip = Join-Path $stagingFolder $fileName
    Log-Debug "Temporary ZIP file: $tempZip"
    
    # For extraction, create a folder using the original base name.
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $tempExtract = Join-Path $stagingFolder $baseName
    Log-Debug "Temporary extraction folder: $tempExtract"
    
    try {
        Log-Trace "Downloading ZIP from $ZipUrl"
        Invoke-WebRequest -Uri $ZipUrl -OutFile $tempZip -ErrorAction Stop
        $fileSize = (Get-Item $tempZip).Length
        Log-Debug "Downloaded ZIP to temporary file: $tempZip (Size: $fileSize bytes)"
    }
    catch {
        Log-Error "Failed to download ZIP from $ZipUrl. Exception: $_"
        return @{
            Success = $false
            ErrorCode = "DOWNLOAD_FAILED"
            ErrorMessage = "Failed to download ZIP from $ZipUrl. Exception: $_"
            TempFiles = @($tempZip)
        }
    }
    
    Log-Trace "Creating extraction directory: $tempExtract"
    New-Item -Path $tempExtract -ItemType Directory -Force | Out-Null
    try {
        Log-Trace "Extracting ZIP file: $tempZip to $tempExtract"
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
        $extractedItemCount = (Get-ChildItem -Path $tempExtract -Recurse).Count
        Log-Debug "Extracted ZIP to temporary folder: $tempExtract (Items: $extractedItemCount)"
    }
    catch {
        Log-Error "Extraction failed for $tempZip. Exception: $_"
        return @{
            Success = $false
            ErrorCode = "EXTRACTION_FAILED"
            ErrorMessage = "Extraction failed for $tempZip. Exception: $_"
            TempFiles = @($tempZip, $tempExtract)
        }
    }
    
    Log-Trace "ZIP staging completed successfully"
    return @{ 
        Success = $true
        TempZip = $tempZip
        TempExtract = $tempExtract 
    }
}

# -----------------------------------------------
# Tools Configuration: Load from YAML File
# -----------------------------------------------
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
    try {
        $yamlContent = Get-Content -Path $ToolsFile -Raw
    }
    catch {
        Log-Error "Failed to read YAML file at: $ToolsFile. Exception: $_"
        exit 1
    }
}

if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host "[INFO] The 'powershell-yaml' module is not installed. Attempting to install it..." -ForegroundColor Cyan
    try {
        Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowClobber
    }
    catch {
        Log-Error "Failed to install the 'powershell-yaml' module. Exception: $_"
        exit 1
    }
}

try {
    Import-Module -Name powershell-yaml -ErrorAction Stop
    $config = ConvertFrom-Yaml -Yaml $yamlContent -ErrorAction Stop
    
    # Validate configuration
    $validationResult = Test-ToolConfiguration -Config $config
    if (-not $validationResult.IsValid) {
        Log-Error "Invalid configuration in ${ToolsFile}:"
        foreach ($error in $validationResult.Errors) {
            Log-Error "  - $error"
        }
        exit 1
    }
    
    # Apply defaults
    $config = Add-ConfigurationDefaults -Config $config
    
    # Extract configuration values
    $ToolsDirectory = if ($PSBoundParameters.ContainsKey('ToolsDirectory') -and -not [string]::IsNullOrWhiteSpace($ToolsDirectory)) { 
        $ToolsDirectory 
    } else { 
        $config.tooldirectory 
    }
    $tools = $config.tools

    # Check if we should just list the tools and exit
    if ($ListTools) {
        # Add parameter to show detailed info
        $detailedParam = $VerboseOutput -or $TraceOutput
        
        # Show the tools
        Show-AvailableTools -Tools $config.tools -Detailed:$detailedParam
        
        # Exit after showing tools
        exit 0
    }
}
catch {
    Log-Error "Failed to parse YAML configuration from $ToolsFile. Exception: $_"
    exit 1
}

# -----------------------------------------------
# Determine update mode based on the -Update parameter.
# -----------------------------------------------
$updateMode = $null
if ($PSBoundParameters.ContainsKey('Update')) {
    if ($Update -and $Update.Count -gt 0) {
         $updateMode = "specific"
         $updateToolList = $Update | ForEach-Object { $_.ToLower() }
         $allToolNames = $tools | ForEach-Object { $_.Name.ToLower() }
         foreach ($req in $updateToolList) {
              if ($allToolNames -notcontains $req) {
                  Log-Warning "Requested update for tool '$req' not found in the YAML configuration."
              }
         }
    }
    else { $updateMode = "general" }
}

# -----------------------------------------------
# Validate GitHub Personal Access Token (if provided)
# -----------------------------------------------
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
    else { Log-Info "GitHub PAT validated successfully." }
}

# -----------------------------------------------
# Ensure the Tools Directory Exists
# -----------------------------------------------
if ([string]::IsNullOrEmpty($ToolsDirectory)) {
    if ($toolsConfig.tooldirectory) {
         $ToolsDirectory = $toolsConfig.tooldirectory
         Log-Info "Using ToolsDirectory from YAML: $ToolsDirectory"
    }
    else { $ToolsDirectory = (Read-Host "The 'ToolsDirectory' parameter is empty. Please provide a location for the tools folder") }
}
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
# Helper Functions for Download Operations
# -----------------------------------------------

# Helper function to download a file to a temporary location
function Download-FileToTemp {
    param (
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutputPath,
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = "PowerShell" },
        [Parameter(Mandatory=$false)][string]$ToolName = ""
    )
    
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -Headers $Headers -ErrorAction Stop
        Log-Debug "Downloaded file from $Url to $OutputPath"
        return $true
    }
    catch {
        Log-Error "Failed to download file for $ToolName from $Url. Exception: $_"
        return $false
    }
}

# Helper function to process non-ZIP files
function Process-NonZipFile {
    param (
        [Parameter(Mandatory=$true)][string]$FileUrl,
        [Parameter(Mandatory=$true)][string]$OutputFolder,
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$false)][string]$Version = "",
        [Parameter(Mandatory=$false)][string]$CommitHash = "",
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = "PowerShell" }
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Value $FileUrl -ParameterName "FileUrl" -FunctionName "Process-NonZipFile")) { return $false }
    if (-not (Test-RequiredParameter -Value $OutputFolder -ParameterName "OutputFolder" -FunctionName "Process-NonZipFile")) { return $false }
    if (-not (Test-RequiredParameter -Value $ToolConfig -ParameterName "ToolConfig" -FunctionName "Process-NonZipFile")) { return $false }
    
    $stagingFolder = Join-Path $PSScriptRoot "tmp"
    if (-not (Test-Path $stagingFolder)) { New-Item -Path $stagingFolder -ItemType Directory | Out-Null }
    
    $fileName = Split-Path $FileUrl -Leaf
    $tempFile = Join-Path $stagingFolder $fileName
    
    try {
        try {
            if (-not (Download-FileToTemp -Url $FileUrl -OutputPath $tempFile -Headers $Headers -ToolName $ToolConfig.Name)) {
                throw "Download failed"
            }
            
            $hash = (Get-FileHash -Algorithm MD5 -Path $tempFile).Hash
            $newManifest = @{ $fileName = $hash }
            
            if (Test-Path (Join-Path $OutputFolder ".downloaded.json")) {
                Remove-ManagedFiles -OutputFolder $OutputFolder
            }
            
            $destinationPath = Join-Path $OutputFolder -ChildPath $fileName
            Copy-Item -Path $tempFile -Destination $destinationPath -Force
            Log-Debug "Copied file from temp to output folder: $destinationPath"
            
            Write-MarkerFile -OutputFolder $OutputFolder `
                            -ToolName $ToolConfig.Name `
                            -DownloadMethod $ToolConfig.DownloadMethod `
                            -DownloadURL $FileUrl `
                            -Version $Version `
                            -CommitHash $CommitHash `
                            -DownloadedFile $destinationPath `
                            -ExtractionLocation $OutputFolder `
                            -Manifest $newManifest
                            
            return $true
        }
        catch {
            Log-Error "Failed to process file for $($ToolConfig.Name). Exception: $_"
            return $false
        }
    }
    finally {
        # Always clean up the temp file
        if (Test-Path $tempFile) {
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            Log-Debug "Cleaned up temporary file: $tempFile"
        }
    }
}

# Helper function for processing ZIP files without extraction
function Process-ZipFileNoExtract {
    param (
        [Parameter(Mandatory=$true)][string]$ZipUrl,
        [Parameter(Mandatory=$true)][string]$OutputFolder,
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$false)][string]$Version = "",
        [Parameter(Mandatory=$false)][string]$CommitHash = "",
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = "PowerShell" }
    )
    
    # This is essentially the same as Process-NonZipFile but with specific naming for ZIP files
    return Process-NonZipFile -FileUrl $ZipUrl -OutputFolder $OutputFolder -ToolConfig $ToolConfig -Version $Version -CommitHash $CommitHash -Headers $Headers
}

# Helper function to set up the output folder
function Initialize-OutputFolder {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory
    )
    
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
    
    return $outputFolder
}

# Helper function to get GitHub API headers
function Get-GitHubHeaders {
    param (
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )
    
    $headers = @{ "User-Agent" = "PowerShell" }
    if (-not [string]::IsNullOrEmpty($GitHubPAT)) {
        $headers["Authorization"] = "token $GitHubPAT"
    }
    
    return $headers
}

# Helper function to process extracted ZIP files
function Process-ExtractedZip {
    param (
        [Parameter(Mandatory=$true)]$Staging,
        [Parameter(Mandatory=$true)][string]$OutputFolder,
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$DownloadUrl,
        [Parameter(Mandatory=$false)][string]$Version = ""
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Value $Staging -ParameterName "Staging" -FunctionName "Process-ExtractedZip")) { return $false }
    if (-not (Test-RequiredParameter -Value $OutputFolder -ParameterName "OutputFolder" -FunctionName "Process-ExtractedZip")) { return $false }
    if (-not (Test-RequiredParameter -Value $ToolConfig -ParameterName "ToolConfig" -FunctionName "Process-ExtractedZip")) { return $false }
    if (-not (Test-RequiredParameter -Value $DownloadUrl -ParameterName "DownloadUrl" -FunctionName "Process-ExtractedZip")) { return $false }
    
    $tempExtract = $Staging.TempExtract
    $newManifest = Get-FileManifest -Folder $tempExtract
    
    if (Test-Path (Join-Path $OutputFolder ".downloaded.json")) {
        Remove-ManagedFiles -OutputFolder $OutputFolder
    }
    
    Copy-Item -Path (Join-Path $tempExtract "*") -Destination $OutputFolder -Recurse -Force
    Log-Debug "Copied extracted files to output folder: $OutputFolder"
    
    Write-MarkerFile -OutputFolder $OutputFolder `
                     -ToolName $ToolConfig.Name `
                     -DownloadMethod $ToolConfig.DownloadMethod `
                     -DownloadURL $DownloadUrl `
                     -Version $Version `
                     -CommitHash "" `
                     -DownloadedFile "" `
                     -ExtractionLocation $OutputFolder `
                     -Manifest $newManifest
                     
    # Clean up staging files
    Remove-Item -Path $Staging.TempExtract -Recurse -Force
    Remove-Item -Path $Staging.TempZip -Force
    
    return $true
}

# -----------------------------------------------
# Dispatcher: Loop Through Tools and Process
# -----------------------------------------------
foreach ($tool in $tools) {
    if (-not [string]::IsNullOrEmpty($tool.OutputFolder)) {
        $toolOutputFolder = Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $tool.OutputFolder $tool.Name)
    }
    else {
        $toolOutputFolder = Join-Path -Path $ToolsDirectory -ChildPath $tool.Name
    }
    $markerFile = Join-Path $toolOutputFolder ".downloaded.json"
    
    $processTool = $false

    if ($PSBoundParameters.ContainsKey('Update')) {
        if ($updateMode -eq "specific") {
            if ($updateToolList -contains $tool.Name.ToLower()) {
                $processTool = $true
                Write-Host "===========================================" -ForegroundColor White
                Log-Info "Updating tool: $($tool.Name)"
                if ((Test-Path $toolOutputFolder) -and (Test-Path $markerFile)) {
                    Log-Info "Update: Removing previous files for $($tool.Name)."
                    Remove-ManagedFiles -OutputFolder $toolOutputFolder
                }
            }
        }
        else {
            if ($ForceDownload -or (-not $tool.skipdownload)) {
                $processTool = $true
                Write-Host "===========================================" -ForegroundColor White
                Log-Info "Downloading tool: $($tool.Name)"
                if ((Test-Path $toolOutputFolder) -and (Test-Path $markerFile)) {
                    Log-Info "Update: Removing previous files for $($tool.Name)."
                    Remove-ManagedFiles -OutputFolder $toolOutputFolder
                }
                else {
                    Log-Info "Update: No marker file found for $($tool.Name); preserving user files."
                }
            }
        }
    }
    else {
        if ($ForceDownload) {
            $processTool = $true
            Write-Host "===========================================" -ForegroundColor White
            Log-Info "Force downloading $($tool.Name)..."
        }
        else {
            if ($tool.skipdownload) {
                Log-Info "Skipping $($tool.Name) -- skipdownload is enabled."
            }
            elseif (Test-Path $markerFile) {
                Log-Info "Skipping $($tool.Name) -- already downloaded."
            }
            else {
                $processTool = $true
                Write-Host "===========================================" -ForegroundColor White
                Log-Info "Started working on $($tool.Name)..."
            }
        }
    }
    
    if (-not $processTool) { continue }
    
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
            Download-SpecificFileTool -ToolConfig $tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT
        }
        default {
            Log-Error "Download method '$($tool.DownloadMethod)' not recognized for $($tool.Name)."
        }
    }
    Log-Info "Finished working on $($tool.Name)."
    Write-Host "===========================================" -ForegroundColor White
}

function Download-SpecificFileTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Value $ToolConfig -ParameterName "ToolConfig" -FunctionName "Download-SpecificFileTool")) { return }
    if (-not (Test-RequiredParameter -Value $ToolsDirectory -ParameterName "ToolsDirectory" -FunctionName "Download-SpecificFileTool")) { return }
    
    # Handle optional parameters with defaults
    $extract = Get-DefaultValue -Value $ToolConfig.Extract -DefaultValue $true -ParameterName "Extract"
    
    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    
    # Construct the file URL
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
    
    $ext = [System.IO.Path]::GetExtension($downloadName)
    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT
    
    if ($ext -ieq ".zip") {
        if ($extract) {
            $staging = Process-ZipStaging -ZipUrl $fileUrl -ToolName $ToolConfig.Name -Version "latest"
            if (-not $staging.Success) {
                # Clean up any temporary files
                foreach ($tempFile in $staging.TempFiles) {
                    if (Test-Path $tempFile) {
                        Remove-Item -Path $tempFile -Force -Recurse -ErrorAction SilentlyContinue
                        Log-Debug "Cleaned up temporary file/folder: $tempFile"
                    }
                }
                Log-Error "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
                return
            }
            
            Process-ExtractedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $fileUrl
        }
        else {
            Process-ZipFileNoExtract -ZipUrl $fileUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Headers $headers
        }
    }
    else {
        Process-NonZipFile -FileUrl $fileUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Headers $headers
    }
}

function Download-BranchZipTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Value $ToolConfig -ParameterName "ToolConfig" -FunctionName "Download-BranchZipTool")) { return }
    if (-not (Test-RequiredParameter -Value $ToolsDirectory -ParameterName "ToolsDirectory" -FunctionName "Download-BranchZipTool")) { return }
    
    # Handle optional parameters with defaults
    $extract = Get-DefaultValue -Value $ToolConfig.Extract -DefaultValue $true -ParameterName "Extract"
    $branch = Get-DefaultValue -Value $ToolConfig.Branch -DefaultValue "master" -ParameterName "Branch"
    
    $zipUrl = "$($ToolConfig.RepoUrl)/archive/refs/heads/$branch.zip"
    Log-Info "Downloading branch zip for $($ToolConfig.Name)..."
    
    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT
    
    if ($extract) {
        $staging = Process-ZipStaging -ZipUrl $zipUrl -ToolName $ToolConfig.Name -Version $branch
        if (-not $staging.Success) {
            # Clean up any temporary files
            foreach ($tempFile in $staging.TempFiles) {
                if (Test-Path $tempFile) {
                    Remove-Item -Path $tempFile -Force -Recurse -ErrorAction SilentlyContinue
                    Log-Debug "Cleaned up temporary file/folder: $tempFile"
                }
            }
            Log-Error "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
            return
        }
        
        Process-ExtractedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $zipUrl -Version $branch
    }
    else {
        Process-ZipFileNoExtract -ZipUrl $zipUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Version $branch -Headers $headers
    }
}

function Download-LatestReleaseTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = "",
        [Parameter(Mandatory=$true)]$AssetPatterns
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Value $ToolConfig -ParameterName "ToolConfig" -FunctionName "Download-LatestReleaseTool")) { return }
    if (-not (Test-RequiredParameter -Value $ToolsDirectory -ParameterName "ToolsDirectory" -FunctionName "Download-LatestReleaseTool")) { return }
    if (-not (Test-RequiredParameter -Value $AssetPatterns -ParameterName "AssetPatterns" -FunctionName "Download-LatestReleaseTool")) { return }
    
    # Handle optional parameters with defaults
    $extract = Get-DefaultValue -Value $ToolConfig.Extract -DefaultValue $true -ParameterName "Extract"
    
    $apiRepoUrl = $ToolConfig.RepoUrl -replace "https://github.com/", "https://api.github.com/repos/"
    $releaseUri = "$apiRepoUrl/releases/latest"
    Log-Debug "Using API endpoint: $releaseUri for $($ToolConfig.Name)"
    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT
    
    try {
        $releaseInfo = Invoke-RestMethod -Uri $releaseUri -Headers $headers
        Log-Debug "Retrieved release info. Assets count: $($releaseInfo.assets.Count)"
    }
    catch {
        Log-Error "Failed to get release info for $($ToolConfig.Name). Exception: $_"
        return
    }
    
    # Filter assets based on configuration
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
        $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
        
        $downloadUrl = $asset.browser_download_url
        $fileName = Split-Path $downloadUrl -Leaf
        $ext = [System.IO.Path]::GetExtension($fileName)
        
        if ($ext -ieq ".zip") {
            if ($extract) {
                $staging = Process-ZipStaging -ZipUrl $downloadUrl -ToolName $ToolConfig.Name -Version $releaseInfo.tag_name
                if (-not $staging.Success) {
                    # Clean up any temporary files
                    foreach ($tempFile in $staging.TempFiles) {
                        if (Test-Path $tempFile) {
                            Remove-Item -Path $tempFile -Force -Recurse -ErrorAction SilentlyContinue
                            Log-Debug "Cleaned up temporary file/folder: $tempFile"
                        }
                    }
                    Log-Error "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
                    return
                }
                
                Process-ExtractedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $downloadUrl -Version $releaseInfo.tag_name
            }
            else {
                Process-ZipFileNoExtract -ZipUrl $downloadUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Version $releaseInfo.tag_name -Headers $headers
            }
        }
        else {
            Process-NonZipFile -FileUrl $downloadUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Version $releaseInfo.tag_name -Headers $headers
        }
    }
    else {
        Log-Warning "No matching asset found for $($ToolConfig.Name)."
    }
}

function Download-GitCloneTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Value $ToolConfig -ParameterName "ToolConfig" -FunctionName "Download-GitCloneTool")) { return }
    if (-not (Test-RequiredParameter -Value $ToolsDirectory -ParameterName "ToolsDirectory" -FunctionName "Download-GitCloneTool")) { return }
    
    # Handle optional parameters with defaults
    $branch = Get-DefaultValue -Value $ToolConfig.Branch -DefaultValue "master" -ParameterName "Branch"
    
    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    
    # Extract owner and repo from URL
    Log-Trace "Extracting owner and repo from URL: $($ToolConfig.RepoUrl)"
    if ($ToolConfig.RepoUrl -match "github\.com/([^/]+)/([^/]+)") {
        $owner = $matches[1]
        $repo = $matches[2]
        $repo = $repo -replace "\.git$", ""
        Log-Debug "Extracted owner: $owner, repo: $repo"
    }
    else {
        Log-Error "Invalid GitHub URL format for $($ToolConfig.Name): $($ToolConfig.RepoUrl)"
        return
    }
    
    # Get API info about the repo to get the latest commit
    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT
    $apiUrl = "https://api.github.com/repos/$owner/$repo/branches/$branch"
    Log-Debug "Querying GitHub API: $apiUrl"
    
    try {
        $branchInfo = Invoke-RestMethod -Uri $apiUrl -Headers $headers
        $commitHash = $branchInfo.commit.sha
        Log-Debug "Latest commit hash for ${branch}: ${commitHash}"
    }
    catch {
        # If master branch fails, try main branch
        if ($branch -eq "master") {
            Log-Warning "Failed to get info for 'master' branch, trying 'main' branch instead"
            try {
                $apiUrl = "https://api.github.com/repos/$owner/$repo/branches/main"
                Log-Debug "Querying GitHub API: $apiUrl"
                $branchInfo = Invoke-RestMethod -Uri $apiUrl -Headers $headers
                $commitHash = $branchInfo.commit.sha
                $branch = "main"
                Log-Debug "Latest commit hash for main: $commitHash"
            }
            catch {
                Log-Error "Failed to get branch info for $($ToolConfig.Name). Exception: $_"
                return
            }
        }
        else {
            Log-Error "Failed to get branch info for $($ToolConfig.Name). Exception: $_"
            return
        }
    }
    
    # Download ZIP archive of the branch
    $zipUrl = "https://github.com/$owner/$repo/archive/$commitHash.zip"
    Log-Info "Downloading repository ZIP for $($ToolConfig.Name) from branch $branch (commit $commitHash)..."
    Log-Debug "ZIP URL: $zipUrl"
    
    $staging = Process-ZipStaging -ZipUrl $zipUrl -ToolName $ToolConfig.Name -Version $branch
    if (-not $staging.Success) {
        # Clean up any temporary files
        foreach ($tempFile in $staging.TempFiles) {
            if (Test-Path $tempFile) {
                Remove-Item -Path $tempFile -Force -Recurse -ErrorAction SilentlyContinue
                Log-Debug "Cleaned up temporary file/folder: $tempFile"
            }
        }
        Log-Error "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
        return
    }
    
    # Process the extracted files
    $tempExtract = $staging.TempExtract
    Log-Trace "Generating file manifest for extracted content"
    $newManifest = Get-FileManifest -Folder $tempExtract
    Log-Debug "Generated manifest with ${newManifest.Count} files"
    
    if (Test-Path (Join-Path $outputFolder ".downloaded.json")) {
        Log-Debug "Removing previously managed files from $outputFolder"
        Remove-ManagedFiles -OutputFolder $outputFolder
    }
    
    Log-Debug "Copying extracted files to output folder: $outputFolder"
    Copy-Item -Path (Join-Path $tempExtract "*") -Destination $outputFolder -Recurse -Force
    Log-Debug "Copied extracted files to output folder: $outputFolder"
    
    Write-MarkerFile -OutputFolder $outputFolder `
                     -ToolName $ToolConfig.Name `
                     -DownloadMethod $ToolConfig.DownloadMethod `
                     -DownloadURL $zipUrl `
                     -Version $branch `
                     -CommitHash $commitHash `
                     -DownloadedFile "" `
                     -ExtractionLocation $outputFolder `
                     -Manifest $newManifest
    
    # Clean up staging files
    Log-Trace "Cleaning up temporary files"
    Remove-Item -Path $staging.TempExtract -Recurse -Force
    Remove-Item -Path $staging.TempZip -Force
    
    Log-Info "Successfully downloaded and extracted $($ToolConfig.Name) from branch $branch (commit $commitHash)"
}

# -----------------------------------------------
# Parameter Validation Helpers
# -----------------------------------------------

# Validates that a required parameter has a value
# Returns true if the parameter is valid, false otherwise
function Test-RequiredParameter {
    param (
        [Parameter(Mandatory=$true)]$Value,
        [Parameter(Mandatory=$true)][string]$ParameterName,
        [Parameter(Mandatory=$true)][string]$FunctionName
    )
    
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
        Log-Error "Required parameter '$ParameterName' is missing or empty in function '$FunctionName'"
        return $false
    }
    return $true
}

# Gets a default value for a parameter if the provided value is null
# Returns the provided value if not null, otherwise returns the default value
function Get-DefaultValue {
    param (
        $Value,
        $DefaultValue,
        [string]$ParameterName = ""
    )
    
    if ($null -eq $Value) {
        if ($ParameterName) {
            Log-Debug "Using default value for parameter '$ParameterName': $DefaultValue"
        }
        return $DefaultValue
    }
    return $Value
}

# -----------------------------------------------
# YAML Configuration Validation
# -----------------------------------------------

# Validates the YAML configuration
# Returns an object with IsValid and Errors properties
function Test-ToolConfiguration {
    param (
        [Parameter(Mandatory=$true)]$Config
    )
    
    $isValid = $true
    $errors = @()
    
    # Check if tooldirectory exists
    if (-not $Config.ContainsKey("tooldirectory")) {
        $errors += "Missing required field: tooldirectory"
        $isValid = $false
    }
    elseif ([string]::IsNullOrWhiteSpace($Config.tooldirectory)) {
        $errors += "tooldirectory cannot be empty"
        $isValid = $false
    }
    
    # Check if tools array exists
    if (-not $Config.ContainsKey("tools") -or $null -eq $Config.tools) {
        $errors += "Missing required field: tools"
        $isValid = $false
    }
    elseif (-not ($Config.tools -is [System.Collections.IList])) {
        $errors += "tools must be an array"
        $isValid = $false
    }
    elseif ($Config.tools.Count -eq 0) {
        $errors += "tools array cannot be empty"
        $isValid = $false
    }
    else {
        # Validate each tool in the array
        foreach ($tool in $Config.tools) {
            $toolErrors = Test-ToolEntry -Tool $tool
            if ($toolErrors.Count -gt 0) {
                $errors += $toolErrors
                $isValid = $false
            }
        }
    }
    
    return @{
        IsValid = $isValid
        Errors = $errors
    }
}

function Test-ToolEntry {
    param (
        [Parameter(Mandatory=$true)]$Tool
    )
    
    $errors = @()
    
    # Check required fields
    if (-not $Tool.ContainsKey("name") -or [string]::IsNullOrWhiteSpace($Tool.name)) {
        $errors += "Tool is missing required field: name"
    }
    
    if (-not $Tool.ContainsKey("RepoUrl") -or [string]::IsNullOrWhiteSpace($Tool.RepoUrl)) {
        $errors += "Tool '$($Tool.name)' is missing required field: RepoUrl"
    }
    
    if (-not $Tool.ContainsKey("DownloadMethod") -or [string]::IsNullOrWhiteSpace($Tool.DownloadMethod)) {
        $errors += "Tool '$($Tool.name)' is missing required field: DownloadMethod"
    }
    else {
        # Validate DownloadMethod
        $validMethods = @("gitClone", "latestRelease", "branchZip", "specificFile")
        if (-not ($validMethods -contains $Tool.DownloadMethod)) {
            $errors += "Tool '$($Tool.name)' has invalid DownloadMethod: $($Tool.DownloadMethod). Valid values are: $($validMethods -join ', ')"
        }
        
        # Validate method-specific required fields
        switch ($Tool.DownloadMethod) {
            "latestRelease" {
                if (-not $Tool.ContainsKey("AssetType") -and -not $Tool.ContainsKey("AssetFilename") -and -not $Tool.ContainsKey("DownloadName")) {
                    $errors += "Tool '$($Tool.name)' with DownloadMethod 'latestRelease' must specify either AssetType, AssetFilename, or DownloadName"
                }
            }
            "specificFile" {
                if (-not $Tool.ContainsKey("SpecificFilePath") -and $Tool.RepoUrl -like "https://github.com/*") {
                    $errors += "Tool '$($Tool.name)' with DownloadMethod 'specificFile' must specify SpecificFilePath for GitHub repositories"
                }
            }
            "branchZip" {
                # Branch is optional, defaults to master/main
            }
        }
    }
    
    return $errors
}

function Add-ConfigurationDefaults {
    param (
        [Parameter(Mandatory=$true)]$Config
    )
    
    $updatedConfig = $Config.Clone()
    
    # Add default values for tools
    if ($updatedConfig.ContainsKey("tools") -and $updatedConfig.tools -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $updatedConfig.tools.Count; $i++) {
            $tool = $updatedConfig.tools[$i]
            
            # Add default SkipDownload if missing
            if (-not $tool.ContainsKey("SkipDownload")) {
                $tool.SkipDownload = $false
                Log-Debug "Added default SkipDownload=false for tool '$($tool.name)'"
            }
            
            # Add default Extract if missing
            if (-not $tool.ContainsKey("Extract")) {
                $tool.Extract = $true
                Log-Debug "Added default Extract=true for tool '$($tool.name)'"
            }
            
            # Add method-specific defaults
            switch ($tool.DownloadMethod) {
                "branchZip" {
                    if (-not $tool.ContainsKey("Branch")) {
                        $tool.Branch = "master"
                        Log-Debug "Added default Branch=master for tool '$($tool.name)'"
                    }
                }
                "gitClone" {
                    if (-not $tool.ContainsKey("Branch")) {
                        $tool.Branch = "master"
                        Log-Debug "Added default Branch=master for tool '$($tool.name)'"
                    }
                }
            }
            
            $updatedConfig.tools[$i] = $tool
        }
    }
    
    return $updatedConfig
}

# Function to display available tools
function Show-AvailableTools {
    param (
        [Parameter(Mandatory=$true)]$Tools,
        [Parameter(Mandatory=$false)][switch]$Detailed = $false
    )
    
    Write-Host "`nAvailable Tools in Configuration:" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    
    foreach ($tool in $Tools) {
        # Display tool name with download method
        Write-Host "`n[$($tool.DownloadMethod)]" -NoNewline -ForegroundColor Yellow
        Write-Host " $($tool.Name)" -ForegroundColor Green
        
        # Display output folder if specified
        if (-not [string]::IsNullOrEmpty($tool.OutputFolder)) {
            Write-Host "  Location: $($tool.OutputFolder)\$($tool.Name)" -ForegroundColor Gray
        }
        
        # Display skip status if true
        if ($tool.SkipDownload) {
            Write-Host "  Status: " -NoNewline -ForegroundColor Gray
            Write-Host "SKIPPED" -ForegroundColor Red
        }
        
        # Display additional details if requested
        if ($Detailed) {
            Write-Host "  URL: $($tool.RepoUrl)" -ForegroundColor Gray
            
            # Display method-specific details
            switch ($tool.DownloadMethod) {
                "gitClone" {
                    if ($tool.Branch) {
                        Write-Host "  Branch: $($tool.Branch)" -ForegroundColor Gray
                    }
                }
                "branchZip" {
                    if ($tool.Branch) {
                        Write-Host "  Branch: $($tool.Branch)" -ForegroundColor Gray
                    }
                }
                "latestRelease" {
                    if ($tool.AssetType) {
                        Write-Host "  Asset Type: $($tool.AssetType)" -ForegroundColor Gray
                    }
                    if ($tool.AssetFilename -or $tool.DownloadName) {
                        $filename = if ($tool.DownloadName) { $tool.DownloadName } else { $tool.AssetFilename }
                        Write-Host "  Asset Filename: $filename" -ForegroundColor Gray
                    }
                }
                "specificFile" {
                    if ($tool.SpecificFilePath) {
                        Write-Host "  File Path: $($tool.SpecificFilePath)" -ForegroundColor Gray
                    }
                    if ($tool.DownloadName) {
                        Write-Host "  Download As: $($tool.DownloadName)" -ForegroundColor Gray
                    }
                }
            }
            
            # Display extract setting if specified
            if ($tool.ContainsKey("Extract")) {
                Write-Host "  Extract: $($tool.Extract)" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host "`nTotal Tools: $($Tools.Count)" -ForegroundColor Cyan
    Write-Host "=================================`n" -ForegroundColor Cyan
}

<#
.SYNOPSIS
    ToolFetcher - A PowerShell script to download and update digital forensics tools.

.DESCRIPTION
    ToolFetcher automates the process of downloading and updating digital forensics tools from
    various sources including GitHub repositories, direct downloads, and release pages.
    
    The script supports multiple download methods:
    - gitClone: Downloads a repository using GitHub API (no Git dependency)
    - latestRelease: Downloads the latest release asset from a GitHub repository
    - branchZip: Downloads a specific branch as a ZIP file
    - specificFile: Downloads a specific file from a URL

.PARAMETER ToolsFile
    Path to the YAML file containing tool definitions.
    Default: "tools.yaml" in the same directory as the script.

.PARAMETER ToolsDirectory
    Directory where tools will be downloaded and extracted.
    If not specified, the value from the YAML file will be used.

.PARAMETER ForceDownload
    Force download of all tools, even if they have been previously downloaded.

.PARAMETER Update
    Check for updates to previously downloaded tools and download newer versions if available.
    If you supply one or more tool names (comma-separated), then only those tools will be updated.

.PARAMETER VerboseOutput
    Show detailed debug information during execution.

.PARAMETER TraceOutput
    Show very detailed trace information during execution (most verbose).

.PARAMETER LogFile
    Path to a log file where all output will be saved. If not specified, logging to file is disabled.

.PARAMETER GitHubPAT
    GitHub Personal Access Token to use for API requests to avoid rate limiting.

.PARAMETER ListTools
    Lists all available tools defined in the YAML configuration file.
    Use with -VerboseOutput to see detailed information about each tool.

.EXAMPLE
    PS> .\ToolFetcher.ps1
    
    Runs the script with default parameters, using tools.yaml in the current directory
    and downloading tools to the directory specified in the YAML file.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -ToolsFile "my_tools.yaml" -ToolsDirectory "D:\DFIR\Tools"
    
    Uses a custom YAML configuration file and downloads tools to the specified directory.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -Update
    
    Updates all previously downloaded tools that are not marked with SkipDownload.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -Update "LECmd","JLECmd"
    
    Updates only the specified tools (LECmd and JLECmd), ignoring their SkipDownload setting.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -ForceDownload
    
    Forces re-download of all tools, overwriting existing directories.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -ListTools
    
    Lists all tools defined in the configuration file with basic information.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -ListTools -VerboseOutput
    
    Lists all tools with detailed information including URLs, branches, and other settings.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -VerboseOutput -LogFile "toolfetcher.log"
    
    Runs with detailed logging and saves all output to the specified log file.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -GitHubPAT "ghp_1234567890abcdef"
    
    Uses a GitHub Personal Access Token to avoid API rate limiting when downloading from GitHub.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -ToolsFile "https://raw.githubusercontent.com/kev365/ToolFetcher/main/tools.yaml"
    
    Uses a remote YAML configuration file instead of a local one.

.NOTES
    Author: Kevin Stokes
    Version: 1.2.3
    
    Requirements:
    - PowerShell 5.1 or higher
    - Internet connection
    - PowerShell-yaml module (will be installed if missing)
#>
