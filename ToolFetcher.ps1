# =====================================================
# ToolFetcher
#
# A tool for fetching DFIR and other GitHub tools.
#
# Author: Kevin Stokes
# Version: See $script:Version variable below
# License: MIT
# =====================================================

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

    Each tool's configuration is defined in a YAML file that supports:
    - Multiple download methods
    - Custom output folders
    - Asset type filtering (win64, win32, linux64, etc.)
    - Skip download options
    - Extraction control
    - Branch selection

.PARAMETER ToolsFile
    Path to the YAML file containing tool definitions.
    Can be a local file path or a URL to a remote YAML file.
    Default: "tools.yaml" in the same directory as the script.

.PARAMETER ToolsDirectory
    Directory where tools will be downloaded and extracted.
    If not specified, the value from the YAML file will be used.
    If neither is specified, you will be prompted to enter a directory.

.PARAMETER ForceDownload
    Force download of all tools, even if they have been previously downloaded.
    This will overwrite existing tool directories completely.
    When used with -UpdateAll, it will update all downloaded tools, bypassing the skipdownload setting.

.PARAMETER UpdateAll
    Update all previously downloaded tools that have downloads enabled (skipdownload: false).
    Updates preserve user modifications by only removing managed files (tracked in .downloaded.json).

.PARAMETER UpdateTools
    Specify tool names to update. You can provide multiple tools in several ways:
    1. Comma-separated list: -UpdateTools "tool1,tool2,tool3"
    2. Multiple parameters: -UpdateTools tool1 -UpdateTools tool2
    3. Array syntax: -UpdateTools @("tool1","tool2")

    If a tool is not already downloaded, it will be downloaded.
    Updates preserve user modifications by only removing managed files (tracked in .downloaded.json).

.PARAMETER VerboseOutput
    Show detailed debug information during execution.
    Includes additional details about download operations, file processing, and configuration.

.PARAMETER TraceOutput
    Show very detailed trace information during execution (most verbose).
    Includes low-level details about file operations, API calls, and internal processing.

.PARAMETER Log
    Enable logging to a file. When specified, a log file will be automatically created in the tools directory
    with a timestamp in the filename. All operations will be logged regardless of console output level.

.PARAMETER GitHubPAT
    GitHub Personal Access Token to use for API requests to avoid rate limiting.
    WARNING: This method exposes your token in command history and process listings.
    For better security, use -PromptForPAT instead.

.PARAMETER PromptForPAT
    Prompt for GitHub Personal Access Token securely. The token will not be visible when typing
    and will not be stored in command history. Recommended over -GitHubPAT for security.

.PARAMETER ListTools
    Lists all available tools defined in the YAML configuration file.
    Use with -VerboseOutput to see detailed information about each tool.
    This option only displays the tools and exits without downloading anything.

.EXAMPLE
    PS> .\ToolFetcher.ps1

    Runs the script with default parameters, using tools.yaml in the current directory
    and downloading tools to the directory specified in the YAML file.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -tf "my_tools.yaml" -td "D:\DFIR\Tools"

    Uses a custom YAML configuration file and downloads tools to the specified directory.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -upall

    Updates all previously downloaded tools that are not marked with SkipDownload.
    Preserves any user modifications to the tools.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -uptools "LECmd","KStrike"

    Updates only the specified tools (LECmd and JLECmd), ignoring their SkipDownload setting.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -uptools LECmd -uptools KStrike

    Another way to update specific tools using multiple parameter instances.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -list

    Lists all tools defined in the configuration file with basic information.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -list -vo

    Lists all tools with detailed information including URLs, branches, and other settings.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -l

    Runs with logging enabled and saves all output to a timestamped log file in the tools directory.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -GitHubPAT "ghp_1234567890abcdef"

    Uses a GitHub Personal Access Token to avoid API rate limiting when downloading from GitHub.
    Note: This method exposes your token in command history and process listings.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -tf "https://raw.githubusercontent.com/kev365/ToolFetcher/main/tools.yaml"

    Uses a remote YAML configuration file instead of a local one.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -PromptForPAT

    Prompts for a GitHub Personal Access Token securely. The token will not be visible when typing
    and will not be stored in command history.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -vo -l

    Runs with both verbose output and logging enabled for maximum debugging information.

.NOTES
    Author: Kevin Stokes
    See the $script:Version variable below for the current version.

    Requirements:
    - PowerShell 5.1 or higher
    - Internet connection
    - PowerShell-yaml module (will be installed if missing)

    Features:
    - Automatic module installation
    - YAML configuration support
    - Multiple download methods
    - Update management
    - File manifest tracking
    - Detailed logging
    - GitHub API rate limit handling
    - Secure token input
    - Cross-platform asset support

    For more information, visit:
    https://github.com/kev365/ToolFetcher
    https://dfir-kev.medium.com/tool-fetcher-499c99aaa9fa
#>

# Enable advanced functions with cmdlet binding.
[CmdletBinding()]
param (
    [Parameter(HelpMessage = 'Path(s) to YAML files containing tool definitions. Can be local paths or remote URLs. Accepts a comma-separated list to merge multiple tool groups (tools arrays are concatenated; the first file''s tooldirectory wins).')]
    [Alias('tf')]
    [string[]]$ToolsFile = @("tools.yaml"),

    [Parameter(HelpMessage = 'Filter the merged tools list to only entries whose Category field matches one of the given tags (case-insensitive). Tools without a Category are excluded when this is set.')]
    [string[]]$Tag = @(),
    
    [Parameter(HelpMessage = 'Directory where tools will be downloaded and extracted.')]
    [Alias('td')]
    [string]$ToolsDirectory = "",
    
    [Parameter(HelpMessage = 'Force re-download and overwrite any existing tool output directories.')]
    [Alias('force')]
    [switch]$ForceDownload = $false,

    [Parameter(HelpMessage = 'Show what would be downloaded/updated without writing anything. No network downloads, no file changes; useful for previewing -UpdateAll.')]
    [Alias('dry')]
    [switch]$DryRun = $false,

    [Parameter(HelpMessage = 'Run downloads in parallel (PowerShell 7+ only). On PS 5.1 a warning is shown and execution falls back to sequential. Use -ThrottleLimit to tune concurrency.')]
    [switch]$Parallel = $false,

    [Parameter(HelpMessage = 'Launch the interactive TUI picker (PowerShell 7+ only). Requires Microsoft.PowerShell.ConsoleGuiTools. Loads the merged tools list, queries GitHub for remote versions, and lets you multi-select tools to download.')]
    [Alias('i')]
    [switch]$Interactive = $false,

    [Parameter(HelpMessage = 'Maximum concurrent downloads when -Parallel is set. Default: 4.')]
    [int]$ThrottleLimit = 4,

    [Parameter(DontShow = $true)]
    [switch]$SourceOnly = $false,
    
    [Parameter(HelpMessage = 'Update all previously downloaded tools that have downloads enabled (skipdownload: false). Updates preserve user modifications by only removing managed files (tracked in .downloaded.json).')]
    [Alias('upall')]
    [switch]$UpdateAll,
    
    [Parameter(HelpMessage = 'Specify tool names to update. You can provide multiple tools in several ways: 1. Comma-separated list: -UpdateTools "tool1,tool2,tool3" 2. Multiple parameters: -UpdateTools tool1 -UpdateTools tool2 3. Array syntax: -UpdateTools @("tool1","tool2")')]
    [Alias('uptools')]
    [string[]]$UpdateTools = @(),
    
    [Parameter(HelpMessage = 'Show detailed debug information during execution. Includes additional details about download operations, file processing, and configuration.')]
    [Alias('vo')]
    [switch]$VerboseOutput = $false,
    
    [Parameter(HelpMessage = 'Show trace-level output (most detailed)')]
    [Alias('to')]
    [switch]$TraceOutput = $false,
    
    [Parameter(HelpMessage = 'Enable logging to a file. A log file will be created in the tools directory.')]
    [Alias('l')]
    [switch]$Log = $false,
    
    [Parameter(HelpMessage = 'GitHub Personal Access Token - to avoid rate limits, if needed. NOTE: This is visible in command history and process listings. Use -PromptForPAT for better security.')]
    [Alias('pat')]
    [string]$GitHubPAT = "",
    
    [Parameter(HelpMessage = 'Prompt for GitHub Personal Access Token securely (token will not be visible or stored in command history)')]
    [Alias('ppat')]
    [switch]$PromptForPAT = $false,
    
    [Parameter(HelpMessage = 'List all available tools in the configuration file')]
    [Alias('list')]
    [switch]$ListTools = $false
)

# Pin TLS to 1.2+ early. PowerShell 5.1 on older Windows builds defaults to
# TLS 1.0/1.1 which many GitHub endpoints now reject. PS 7+ already negotiates
# TLS 1.2+ by default but the bitwise-or is a no-op there.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Script version - centralized for easy updates
$script:Version = "3.0.0"

# Pin powershell-yaml to a known-good version. PSGallery is the trusted
# default, but pinning protects against supply-chain compromise of the module.
$script:RequiredYamlVersion = "0.4.7"

# Stick Letters ASCII banner shown at startup.
$script:Banner = @'
___  __   __           ___  ___ ___  __        ___  __
 |  /  \ /  \ |       |__  |__   |  /  ` |__| |__  |__)
 |  \__/ \__/ |___    |    |___  |  \__, |  | |___ |  \
'@

function Show-Banner {
    Write-Host ""
    foreach ($line in $script:Banner -split "`r?`n") {
        Write-Host $line -ForegroundColor Cyan
    }
    Write-Host ("                                                  v$script:Version") -ForegroundColor DarkCyan
    Write-Host ""
}

# Per-process staging folder under the system temp path. Each download writes
# transient files here, then copies the final result into $ToolsDirectory.
# Lives outside $PSScriptRoot so the script can run from a read-only location,
# and embeds the PID so concurrent invocations don't collide.
$script:StagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ToolFetcher_$PID"

# Asset filename patterns for the latestRelease download method's AssetType filter.
# Built once at script load rather than on every Save-LatestReleaseTool call.
$script:AssetPatterns = @{
    "win64"   = "(?i)(win64|windows[-_]?64|win[-_]?x64|x64|x86_64|amd64|64[-_]?bit)"
    "win32"   = "(?i)(win32|windows[-_]?32|win[-_]?x86|x86|i386|386|32[-_]?bit)"
    "linux64" = "(?i)(linux[-_]?64|linux[-_]?amd64|linux[-_]?x64|linux[-_]?x86_64|linuxx86_64|linux64|x86_64|amd64|x64)"
    "linux32" = "(?i)(linux[-_]?32|linux[-_]?386|linuxx86|linuxi386|x86|i386|386|32[-_]?bit)"
    "macos64" = "(?i)(macos[-_]?64|darwin[-_]?64|osx[-_]?64|macos[-_]?x64|darwin[-_]?x64|osx[-_]?x64|macos[-_]?x86_64|darwin[-_]?x86_64|osx[-_]?x86_64|x64|x86_64|arm64|aarch64)"
    "macos32" = "(?i)(macos[-_]?32|darwin[-_]?32|osx[-_]?32|macos[-_]?x86|darwin[-_]?x86|osx[-_]?x86|x86|i386|386|32[-_]?bit)"
    "arm64"   = "(?i)(arm64|aarch64|armv8)"
    "arm32"   = "(?i)(arm32|armv7|armv6|armhf)"
}

# -----------------------------------------------
# Define Logging Functions First
# -----------------------------------------------
# Define log levels enum
if (-not ([System.Management.Automation.PSTypeName]'LogLevel').Type) {
    Add-Type -TypeDefinition @"
    public enum LogLevel {
        Error = 0,
        Warning = 1,
        Info = 2,
        Debug = 3,
        Trace = 4
    }
"@
}

$script:LogFile = $null
$script:LoggingEnabled = $false

# Patterns used to redact secrets from log output. Catches GitHub PATs in
# 'token <pat>', 'Authorization: token <pat>', and 'Bearer <pat>' forms,
# plus the new fine-grained PAT prefix (github_pat_).
$script:SecretRedactPatterns = @(
    '(?i)(token\s+)(gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|[A-Fa-f0-9]{40,})'
    '(?i)(Bearer\s+)(gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|[A-Fa-f0-9]{40,})'
)

function Format-RedactedMessage {
    param ([Parameter(Mandatory=$true)][string]$Text)
    foreach ($pattern in $script:SecretRedactPatterns) {
        $Text = [regex]::Replace($Text, $pattern, '$1<REDACTED>')
    }
    return $Text
}

# Main logging function that handles different log levels, console output, and file logging
function Write-ToolLog {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][LogLevel]$Level = [LogLevel]::Info,
        [Parameter(Mandatory=$false)][switch]$NoConsole = $false,
        [Parameter(Mandatory=$false)][ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )

    # Redact secrets before any output
    $Message = Format-RedactedMessage -Text $Message

    # Format timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Format log level
    $levelStr = switch ($Level) {
        ([LogLevel]::Error)   { "ERROR" }
        ([LogLevel]::Warning) { "WARNING" }
        ([LogLevel]::Info)    { "INFO" }
        ([LogLevel]::Debug)   { "DEBUG" }
        ([LogLevel]::Trace)   { "TRACE" }
        default               { "INFO" }
    }
    
    # Format log message
    $logMessage = "[$timestamp] [$levelStr] $Message"
    
    # Write to console if not suppressed and level is appropriate for console
    if (-not $NoConsole) {
        # Only show Debug/Trace messages on console if VerboseOutput/TraceOutput is enabled
        $showOnConsole = $true
        if ($Level -eq [LogLevel]::Debug -and -not $VerboseOutput) { $showOnConsole = $false }
        if ($Level -eq [LogLevel]::Trace -and -not $TraceOutput) { $showOnConsole = $false }
        
        if ($showOnConsole) {
            Write-Host $logMessage -ForegroundColor $ForegroundColor
        }
    }
    
    # Write to log file if enabled - always write all levels to log file
    if ($script:LoggingEnabled -and $script:LogFile -and (Test-Path $script:LogFile)) {
        try {
            Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction Stop
        }
        catch {
            # If we fail to write to the log file, disable logging to prevent further errors
            Write-Host "Failed to write to log file: $_" -ForegroundColor Red
            $script:LoggingEnabled = $false
            
            # Try to re-enable logging once
            try {
                $script:LogFile = Join-Path -Path (Split-Path -Path $script:LogFile -Parent) -ChildPath "ToolFetcher_recovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
                $null = New-Item -Path $script:LogFile -ItemType File -Force
                Add-Content -Path $script:LogFile -Value "[$timestamp] [WARNING] Previous log file became inaccessible, created recovery log" -ErrorAction Stop
                Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction Stop
                $script:LoggingEnabled = $true
                Write-Host "Created recovery log file: $($script:LogFile)" -ForegroundColor Yellow
            }
            catch {
                Write-Host "Failed to create recovery log file: $_" -ForegroundColor Red
                $script:LoggingEnabled = $false
                $script:LogFile = $null
            }
        }
    }
}

function Write-LogError {
    param ([string]$Message)
    Write-ToolLog -Message $Message -Level ([LogLevel]::Error) -ForegroundColor Red
}

function Write-LogWarning {
    param ([string]$Message)
    Write-ToolLog -Message $Message -Level ([LogLevel]::Warning) -ForegroundColor Yellow
}

function Write-LogInfo {
    param ([string]$Message)
    Write-ToolLog -Message $Message -Level ([LogLevel]::Info) -ForegroundColor Cyan
}

function Write-LogDebug {
    param ([string]$Message)
    # Always log debug messages to file, but only show on console if VerboseOutput is enabled
    Write-ToolLog -Message $Message -Level ([LogLevel]::Debug) -ForegroundColor DarkGray
}

function Write-LogTrace {
    param ([string]$Message)
    # Always log trace messages to file, but only show on console if TraceOutput is enabled
    Write-ToolLog -Message $Message -Level ([LogLevel]::Trace) -ForegroundColor DarkGray
}

function Enable-FileLogging {
    param ([string]$LogPath)
    
    try {
        # Create directory if it doesn't exist
        $logDir = Split-Path -Path $LogPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($logDir) -and -not (Test-Path -Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            Write-LogDebug "Created log directory: $logDir"
        }
        
        # Test if we can write to the log file
        $null = New-Item -Path $LogPath -ItemType File -Force
        $script:LogFile = $LogPath
        $script:LoggingEnabled = $true
        
        Write-LogInfo "Logging enabled to file: $LogPath"
        
        # Write a test entry to verify we can write to the file
        # Use Write-ToolLog instead of direct Add-Content to ensure consistent formatting
        Write-LogInfo "Logging initialized"
        Write-LogDebug "Successfully wrote test entry to log file"
    }
    catch {
        Write-Host "Failed to enable logging to file: $_" -ForegroundColor Red
        $script:LoggingEnabled = $false
        $script:LogFile = $null
    }
}

# -----------------------------------------------
# Function: Display Available Tools
# -----------------------------------------------
function Show-AvailableTools {
    param (
        [Parameter(Mandatory=$true)]$Tools,
        [Parameter(Mandatory=$false)][switch]$Detailed = $false
    )
    
    Write-Host "`nAvailable Tools in Configuration:" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    
    foreach ($tool in $Tools) {
        $methodLabel = if ([string]::IsNullOrWhiteSpace($tool.DownloadMethod)) { "PLACEHOLDER" } else { $tool.DownloadMethod }
        Write-Host "`n[$methodLabel]" -NoNewline -ForegroundColor Yellow
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

# -----------------------------------------------
# Function: Validate GitHub Personal Access Token
# -----------------------------------------------
function Test-GitHubPAT {
    param ([Parameter(Mandatory = $true)][string]$Token)
    $headers = @{ "Authorization" = "token $Token"; "User-Agent" = "PowerShell" }
    try {
        $user = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -ErrorAction Stop
        Write-LogDebug "GitHub PAT validated for user: $($user.login)"
        return $true
    }
    catch {
        Write-LogError "GitHub PAT validation failed: $_"
        return $false
    }
}

# -----------------------------------------------
# Function: Test Tool Configuration
# -----------------------------------------------
function Test-ToolConfiguration {
    param ([Parameter(Mandatory = $true)]$Config)
    
    $isValid = $true
    $errors = @()
    
    # Check if tooldirectory exists - but don't require a value
    if (-not $Config.ContainsKey("tooldirectory")) {
        $errors += "Missing required field: tooldirectory"
        $isValid = $false
    }
    # Remove the check for empty tooldirectory
    
    # Check if tools array exists
    if (-not $Config.ContainsKey("tools") -or $null -eq $Config.tools -or $Config.tools.Count -eq 0) {
        $isValid = $false
        $errors += "Missing or empty 'tools' array in configuration"
    }
    else {
        # Check each tool entry
        foreach ($tool in $Config.tools) {
            $toolValidation = Test-ToolEntry -Tool $tool
            if (-not $toolValidation.IsValid) {
                $isValid = $false
                foreach ($entryError in $toolValidation.Errors) {
                    $errors += "Tool '$($tool.name)': $entryError"
                }
            }
        }
    }
    
    return @{
        IsValid = $isValid
        Errors = $errors
    }
}

# -----------------------------------------------
# Function: Test Tool Entry
# -----------------------------------------------
function Test-ToolEntry {
    param ([Parameter(Mandatory = $true)]$Tool)

    $isValid = $true
    $errors = @()

    # Name is required for every entry, including placeholders
    if (-not (Test-RequiredParameter -Tool $Tool -Parameter "name")) {
        $isValid = $false
        $errors += "Missing required parameter 'name'"
    }
    else {
        # Reject path-traversal attempts in Name. Name becomes a directory under
        # $ToolsDirectory; '..' or absolute path components could escape it.
        if ($Tool.name -match '(\.\.[/\\]|^[/\\]|^[A-Za-z]:)' -or $Tool.name -match '[/\\]') {
            $isValid = $false
            $errors += "Name '$($Tool.name)' contains path separators or traversal sequences (must be a single folder name)"
        }
    }

    if ($Tool.ContainsKey("OutputFolder") -and -not [string]::IsNullOrWhiteSpace($Tool.OutputFolder)) {
        $of = $Tool.OutputFolder
        # OutputFolder is appended to $ToolsDirectory, so reject absolute paths
        # and any path components that would escape via '..'.
        if ($of -match '(^[/\\]|^[A-Za-z]:)' -or ($of -split '[/\\]') -contains '..') {
            $isValid = $false
            $errors += "OutputFolder '$of' must be a relative path under the tools directory (no '..' or drive prefix)"
        }
    }

    # Warn (don't fail) on plaintext HTTP RepoUrl - downloads should use HTTPS.
    if ($Tool.ContainsKey("RepoUrl") -and $Tool.RepoUrl -match '^http://') {
        Write-LogWarning "Tool '$($Tool.name)' uses plaintext HTTP RepoUrl '$($Tool.RepoUrl)' - content can be tampered with in transit. Switch to HTTPS if available."
    }

    # Placeholder entries (Name set, RepoUrl + DownloadMethod both empty) are
    # treated as wishlist items and skipped by the dispatcher. They pass
    # validation so users can keep TODO entries in their YAML files.
    $hasRepoUrl = Test-RequiredParameter -Tool $Tool -Parameter "RepoUrl"
    $hasMethod  = Test-RequiredParameter -Tool $Tool -Parameter "DownloadMethod"
    if (-not $hasRepoUrl -and -not $hasMethod) {
        return @{ IsValid = $isValid; Errors = $errors }
    }

    if (-not $hasRepoUrl) {
        $isValid = $false
        $errors += "Missing required parameter 'RepoUrl'"
    }

    if (-not $hasMethod) {
        $isValid = $false
        $errors += "Missing required parameter 'DownloadMethod'"
    }
    else {
        # Check download method-specific parameters
        switch ($Tool.DownloadMethod) {
            "gitClone" {
                # No additional required parameters for gitClone
            }
            "branchZip" {
                # Branch is optional, defaults to master/main
            }
            "latestRelease" {
                # AssetType or AssetFilename is recommended but not required
            }
            "specificFile" {
                # Don't require SpecificFilePath or DownloadName if SkipDownload is true
                # or if RepoUrl is a direct file URL (not a GitHub repository URL)
                # or if RepoUrl is a GitHub URL that points directly to a file in the releases section
                if (-not $Tool.SkipDownload -and 
                    -not (Test-RequiredParameter -Tool $Tool -Parameter "SpecificFilePath") -and 
                    -not (Test-RequiredParameter -Tool $Tool -Parameter "DownloadName") -and
                    ($Tool.RepoUrl -like "https://github.com/*") -and
                    (-not ($Tool.RepoUrl -like "https://github.com/*/releases/*"))) {
                    $isValid = $false
                    $errors += "For 'specificFile' method with GitHub repositories, either 'SpecificFilePath' or 'DownloadName' must be specified when SkipDownload is not true"
                }
            }
            default {
                $isValid = $false
                $errors += "Invalid DownloadMethod: '$($Tool.DownloadMethod)'. Must be one of: gitClone, branchZip, latestRelease, specificFile"
            }
        }
    }
    
    return @{
        IsValid = $isValid
        Errors = $errors
    }
}

# -----------------------------------------------
# Function: Test Required Parameter
# -----------------------------------------------
function Test-RequiredParameter {
    param (
        [Parameter(Mandatory = $true)]$Tool,
        [Parameter(Mandatory = $true)][string]$Parameter
    )
    
    return $Tool.ContainsKey($Parameter) -and -not [string]::IsNullOrWhiteSpace($Tool[$Parameter])
}

# -----------------------------------------------
# Function: Get Default Value
# -----------------------------------------------
function Get-DefaultValue {
    param (
        [Parameter(Mandatory = $true)]$Tool,
        [Parameter(Mandatory = $true)][string]$Parameter,
        [Parameter(Mandatory = $false)]$DefaultValue = $null
    )
    
    if ($Tool.ContainsKey($Parameter) -and -not [string]::IsNullOrWhiteSpace($Tool[$Parameter])) {
        return $Tool[$Parameter]
    }
    else {
        return $DefaultValue
    }
}

# Returns the resolved local file path for a tools-file argument, or $null
# if the argument is a URL or doesn't exist on disk. Used to identify
# which YAML file (if any) the engine can write back to (e.g. to persist
# a newly-set tooldirectory).
function Get-LocalToolsFilePath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ($Path -match '^https?://') { return $null }
    $resolved = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $PSScriptRoot $Path }
    if (Test-Path -Path $resolved -PathType Leaf) { return $resolved }
    return $null
}

# Persist a tooldirectory value into a local YAML file. If the file
# already has a 'tooldirectory:' line, replace its value (preserving
# inline comments). Otherwise prepend a new line at the top.
function Save-ToolDirectoryToConfig {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory
    )
    try {
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        # YAML double-quoted strings need each '\' written as '\\'. Note that
        # PowerShell's -replace does NOT interpret '\\' as an escape in the
        # replacement string, so the RHS here is literally two backslashes.
        $yamlValue = $ToolsDirectory -replace '\\', '\\'
        $line = "tooldirectory: `"$yamlValue`""

        if ($content -match '(?m)^tooldirectory:[^\r\n]*') {
            # Replace existing value, preserve any trailing inline comment if it's
            # a fresh write (we just rebuild the line).
            $newContent = [regex]::Replace($content, '(?m)^tooldirectory:[^\r\n]*', $line, 1)
        }
        else {
            $newContent = "$line`r`n" + $content
        }

        # Preserve UTF-8 (no BOM) - matches what Get-Content -Raw + Set-Content -Encoding UTF8 expect.
        Set-Content -Path $Path -Value $newContent -NoNewline -Encoding UTF8 -ErrorAction Stop
        Write-LogInfo "Saved tooldirectory '$ToolsDirectory' to $Path"
        return $true
    }
    catch {
        Write-LogError "Failed to save tooldirectory to '$Path': $_"
        return $false
    }
}

# -----------------------------------------------
# Function: Resolve and load a single tools-file path/URL
# -----------------------------------------------
function Resolve-ToolsFileContent {
    param (
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$DefaultUrl
    )

    # Returns the YAML content string for $Path, or $null if it can't be loaded
    # and the user declines the default-URL fallback.

    if ($Path -match '^https?://') {
        if ($Path -match '^http://') {
            Write-LogWarning "ToolsFile URL '$Path' uses plaintext HTTP. The remote YAML controls all subsequent downloads - switch to HTTPS to prevent tampering."
        }
        $sourceUrl = $Path
        try {
            $null = Invoke-WebRequest -Uri $Path -Method Head -UseBasicParsing -ErrorAction Stop
            Write-LogInfo "Fetching tools configuration from URL: $Path"
        }
        catch {
            Write-LogWarning "URL '$Path' is not available."
            $choice = Read-Host "Use the default URL ($DefaultUrl) instead? (Y/N)"
            if ($choice -match '^(?i:Y(es)?)$') { $sourceUrl = $DefaultUrl }
            else { return $null }
        }
        try {
            return (Invoke-WebRequest -Uri $sourceUrl -UseBasicParsing).Content
        }
        catch {
            Write-LogError "Failed to fetch YAML from URL: $sourceUrl. Exception: $_"
            return $null
        }
    }

    $resolved = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $PSScriptRoot $Path }
    if (-not (Test-Path -Path $resolved)) {
        Write-LogWarning "Local tools file '$Path' not found at '$resolved'."
        $choice = Read-Host "Use the default URL ($DefaultUrl) instead? (Y/N)"
        if ($choice -notmatch '^(?i:Y(es)?)$') { return $null }
        try {
            return (Invoke-WebRequest -Uri $DefaultUrl -UseBasicParsing).Content
        }
        catch {
            Write-LogError "Failed to fetch default URL: $_"
            return $null
        }
    }

    Write-LogInfo "Using local yaml file: $resolved"
    try {
        return Get-Content -Path $resolved -Raw
    }
    catch {
        Write-LogError "Failed to read YAML file at: $resolved. Exception: $_"
        return $null
    }
}

function Add-ConfigurationDefaults {
    param ([Parameter(Mandatory = $true)]$Config)
    
    $updatedConfig = $Config.Clone()

    # Canonical casing for DownloadMethod values. PowerShell switch/-contains/-eq
    # are case-insensitive by default so the script accepts mixed casing, but we
    # normalize here so -list output is consistent and any future case-sensitive
    # comparison (JSON keys, hashtable lookups) won't surprise us.
    $methodCanonical = @{
        "gitclone"      = "gitClone"
        "branchzip"     = "branchZip"
        "latestrelease" = "latestRelease"
        "specificfile"  = "specificFile"
    }

    # Add default values to each tool
    if ($updatedConfig.ContainsKey("tools") -and $null -ne $updatedConfig.tools) {
        for ($i = 0; $i -lt $updatedConfig.tools.Count; $i++) {
            $tool = $updatedConfig.tools[$i]

            if ($tool.ContainsKey("DownloadMethod") -and -not [string]::IsNullOrWhiteSpace($tool.DownloadMethod)) {
                $key = $tool.DownloadMethod.ToLower()
                if ($methodCanonical.ContainsKey($key)) {
                    $tool.DownloadMethod = $methodCanonical[$key]
                }
            }

            # Add default values based on download method.
            # Branch is intentionally left unset when missing; download functions
            # query the repo's default_branch via the GitHub API at runtime.
            switch ($tool.DownloadMethod) {
                "branchZip" {
                    if (-not $tool.ContainsKey("Extract")) {
                        $tool.Extract = $true
                    }
                }
                "specificFile" {
                    # Default Extract to true for zip files if not specified
                    if (-not $tool.ContainsKey("Extract") -and
                        ($tool.DownloadName -match '\.zip$' -or $tool.SpecificFilePath -match '\.zip$')) {
                        $tool.Extract = $true
                    }
                }
            }
            
            # Default SkipDownload to false if not specified
            if (-not $tool.ContainsKey("SkipDownload")) {
                $tool.SkipDownload = $false
            }
            
            $updatedConfig.tools[$i] = $tool
        }
    }
    
    return $updatedConfig
}

# When dot-sourced with -SourceOnly (used by parallel runspaces to import
# functions/state without re-running the main flow), skip both main-flow
# blocks. Function defs above and below this gate still execute so the
# parent caller has the engine available.
if (-not $SourceOnly) {

Show-Banner

# Enable file logging only if explicitly requested
if ($Log) {
    $script:LoggingEnabled = $true
    Write-LogDebug "Logging to file is enabled by user request"
}
else {
    $script:LoggingEnabled = $false
    Write-LogDebug "Logging to file is disabled (use -l to enable)"
}

Write-LogInfo "ToolFetcher v$script:Version started"


$defaultToolsFileUrl = "https://raw.githubusercontent.com/kev365/ToolFetcher/refs/heads/main/tools.yaml"

# -----------------------------------------------
# Tools Configuration: Load and merge YAML file(s)
# -----------------------------------------------
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-LogInfo "The 'powershell-yaml' module is required to parse YAML configuration files."
    $choice = Read-Host "Would you like to install the 'powershell-yaml' module? (Y/N)"
    if ($choice -match '^(?i:Y(es)?)$') {
        Write-LogInfo "Attempting to install the 'powershell-yaml' module (pinned to $script:RequiredYamlVersion)..."
        try {
            Install-Module -Name powershell-yaml -RequiredVersion $script:RequiredYamlVersion -Scope CurrentUser -Force -AllowClobber
        }
        catch {
            Write-LogError "Failed to install the 'powershell-yaml' module. Exception: $_"
            exit 1
        }
    }
    else {
        Write-LogError "The 'powershell-yaml' module is required to continue. Exiting script."
        exit 1
    }
}
Import-Module -Name powershell-yaml -ErrorAction Stop

$mergedTools     = @()
$mergedToolDir   = ""
$primarySource   = $null
# First local YAML we can write back to (e.g. to persist tooldirectory). $null
# if every -ToolsFile entry was a URL.
$writableSource  = $null

foreach ($tfPath in $ToolsFile) {
    $yamlContent = Resolve-ToolsFileContent -Path $tfPath -DefaultUrl $defaultToolsFileUrl
    if ($null -eq $yamlContent) {
        Write-LogError "Could not load tools file '$tfPath'. Exiting."
        exit 1
    }

    try {
        $cfg = ConvertFrom-Yaml -Yaml $yamlContent -ErrorAction Stop
    }
    catch {
        Write-LogError "Failed to parse YAML configuration from '$tfPath'. Exception: $_"
        Write-LogError "Please check your YAML file for syntax errors such as:"
        Write-LogError "  - Missing or mismatched quotes"
        Write-LogError "  - Incorrect indentation"
        Write-LogError "  - Missing colons after property names"
        Write-LogError "  - Invalid characters in property names"
        exit 1
    }

    if ($null -eq $cfg -or $null -eq $cfg.tools) {
        Write-LogWarning "Tools file '$tfPath' has no 'tools' array; skipping."
        continue
    }

    $mergedTools += $cfg.tools

    if ([string]::IsNullOrWhiteSpace($mergedToolDir) -and $cfg.ContainsKey("tooldirectory") -and -not [string]::IsNullOrWhiteSpace($cfg.tooldirectory)) {
        $mergedToolDir = $cfg.tooldirectory
        $primarySource = $tfPath
    }
    elseif ($cfg.ContainsKey("tooldirectory") -and -not [string]::IsNullOrWhiteSpace($cfg.tooldirectory) -and $cfg.tooldirectory -ne $mergedToolDir) {
        Write-LogWarning "tooldirectory in '$tfPath' ('$($cfg.tooldirectory)') differs from '$primarySource' ('$mergedToolDir'); using the first."
    }

    if ($null -eq $writableSource) {
        $local = Get-LocalToolsFilePath -Path $tfPath
        if ($local) { $writableSource = $local }
    }
}

$config = @{ tooldirectory = $mergedToolDir; tools = $mergedTools }

# Validate the merged configuration
$validationResult = Test-ToolConfiguration -Config $config
if (-not $validationResult.IsValid) {
    Write-LogError "Invalid merged tools configuration:"
    foreach ($validationError in $validationResult.Errors) {
        Write-LogError "  - $validationError"
    }
    exit 1
}

$config = Add-ConfigurationDefaults -Config $config

# Apply -Tag filter (operates on the Category field of each tool entry)
if ($Tag.Count -gt 0) {
    $tagSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($t in $Tag) { [void]$tagSet.Add($t) }

    $beforeCount = $config.tools.Count
    $config.tools = @($config.tools | Where-Object {
        $_.ContainsKey("Category") -and -not [string]::IsNullOrWhiteSpace($_.Category) -and $tagSet.Contains($_.Category)
    })
    Write-LogInfo "Tag filter ($($Tag -join ', ')) reduced tool list from $beforeCount to $($config.tools.Count)."
    if ($config.tools.Count -eq 0) {
        Write-LogError "No tools matched the requested tags. Either no entries have a matching Category field, or the YAML files don't define one yet."
        exit 1
    }
}

if ($ListTools) {
    $detailedParam = $VerboseOutput -or $TraceOutput
    Show-AvailableTools -Tools $config.tools -Detailed:$detailedParam
    exit 0
}

# Resolve the tools directory. Order: -ToolsDirectory param > YAML
# tooldirectory > the script's own folder ($PSScriptRoot). The directory
# itself is created lazily by Initialize-OutputFolder when the first
# download lands - this lets -list / -DryRun run without side effects.
$tools = $config.tools

if ($PSBoundParameters.ContainsKey('ToolsDirectory') -and -not [string]::IsNullOrWhiteSpace($ToolsDirectory)) {
    # User passed -ToolsDirectory explicitly; use it as-is.
}
elseif (-not [string]::IsNullOrWhiteSpace($config.tooldirectory)) {
    $ToolsDirectory = $config.tooldirectory
}
else {
    $ToolsDirectory = $PSScriptRoot
    Write-LogInfo "No tools directory configured; defaulting to the script's folder: $ToolsDirectory"
    Write-LogInfo "  (set 'tooldirectory:' in your YAML or use -ToolsDirectory to change this.)"
}

if ($Log -and -not [string]::IsNullOrWhiteSpace($ToolsDirectory)) {
    $logFilePath = Join-Path -Path $ToolsDirectory -ChildPath "ToolFetcher_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Enable-FileLogging -LogPath $logFilePath
}

# -----------------------------------------------
# Determine update mode based on the parameters.
# -----------------------------------------------
$updateMode = $null
if ($UpdateTools.Count -gt 0) {
    $updateMode = "specific"
    
    # Process each item in UpdateTools, splitting by comma if needed
    $expandedToolList = @()
    foreach ($item in $UpdateTools) {
        # Split by comma and add each part to the expanded list
        $expandedToolList += $item.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)
    }
    
    # Process the expanded list
    $updateToolList = $expandedToolList | ForEach-Object { $_.ToLower().Trim() }
    $allToolNames = $tools | ForEach-Object { $_.Name.ToLower() }
    
    # Check if each requested tool exists in the YAML configuration
    $validTools = @()
    $invalidTools = @()
    foreach ($req in $updateToolList) {
        if ($allToolNames -contains $req) {
            $validTools += $req
        } else {
            $invalidTools += $req
            Write-LogWarning "Requested update for tool '$req' not found in the YAML configuration."
        }
    }
    
    # If no valid tools were found, exit with an error
    if ($validTools.Count -eq 0 -and $updateToolList.Count -gt 0) {
        Write-LogError "None of the requested tools were found in the YAML configuration. Please check tool names and try again."
        exit 1
    }
    
    # Update the list to only include valid tools
    $updateToolList = $validTools
}
elseif ($UpdateAll) {
    $updateMode = "general"
}

# -----------------------------------------------
# Validate GitHub Personal Access Token (if provided)
# -----------------------------------------------
if ($PromptForPAT) {
    Write-LogInfo "Prompting for GitHub Personal Access Token..."
    $secureString = Read-Host "Enter your GitHub Personal Access Token" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    try {
        $GitHubPAT = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
}

if (-not [string]::IsNullOrEmpty($GitHubPAT)) {
    if (-not (Test-GitHubPAT -Token $GitHubPAT)) {
        $choice = Read-Host "The provided GitHub PAT appears to be invalid. Would you like to enter a new token? (Y/N)"
        if ($choice -match '^(?i:Y(es)?)$') {
            $secureString = Read-Host "Please enter a valid GitHub Personal Access Token" -AsSecureString
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
            try {
                $GitHubPAT = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            } finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            }
            
            if (-not (Test-GitHubPAT -Token $GitHubPAT)) {
                Write-Host "The provided token is still invalid. Exiting." -ForegroundColor Red
                exit 1
            }
            else {
                Write-LogInfo "GitHub PAT validated successfully."
            }
        }
        else {
            Write-Host "Exiting script due to invalid GitHub PAT." -ForegroundColor Red
            exit 1
        }
    }
    else { Write-LogInfo "GitHub PAT validated successfully." }
}

} # end: if (-not $SourceOnly) for main-flow-A

# -----------------------------------------------
# Function: Process ZIP Staging
# -----------------------------------------------
function Invoke-ZipStaging {
    param (
        [Parameter(Mandatory=$true)][string]$ZipUrl,
        [Parameter(Mandatory=$true)][string]$ToolName,
        [Parameter(Mandatory=$true)][string]$Version,
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = "PowerShell" },
        [Parameter(Mandatory=$false)][string]$ExpectedSha256 = ""
    )

    Write-LogTrace "Starting ZIP staging process for $ToolName from $ZipUrl"
    # Per-tool subfolder so parallel downloads with the same URL filename don't collide.
    $safeName = ($ToolName -replace '[^A-Za-z0-9_.-]', '_')
    $stagingFolder = Join-Path $script:StagingRoot $safeName
    if (-not (Test-Path $stagingFolder)) {
        Write-LogDebug "Creating staging folder: $stagingFolder"
        New-Item -Path $stagingFolder -ItemType Directory -Force | Out-Null
    }

    # Use the original filename from the URL without renaming.
    $fileName = Split-Path $ZipUrl -Leaf
    $tempZip = Join-Path $stagingFolder $fileName
    Write-LogDebug "Temporary ZIP file: $tempZip"

    # For extraction, create a folder using the original base name.
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $tempExtract = Join-Path $stagingFolder $baseName
    Write-LogDebug "Temporary extraction folder: $tempExtract"

    try {
        Write-LogInfo "Downloading $ToolName from $ZipUrl"
        Invoke-WithRetry -Description "ZIP download for $ToolName" -ScriptBlock {
            Invoke-WebRequest -Uri $ZipUrl -OutFile $tempZip -Headers $Headers -ErrorAction Stop
        }
        $fileSize = (Get-Item $tempZip).Length
        Write-LogInfo ("Downloaded {0} ({1:N1} MB)" -f $ToolName, ($fileSize / 1MB))

        if (-not (Test-ExpectedHash -FilePath $tempZip -ExpectedSha256 $ExpectedSha256)) {
            return @{
                Success = $false
                ErrorCode = "HASH_MISMATCH"
                ErrorMessage = "SHA256 mismatch for $ToolName"
                TempFiles = @($tempZip)
            }
        }
    }
    catch {
        Write-LogError "Failed to download ZIP from $ZipUrl. Exception: $_"
        return @{
            Success = $false
            ErrorCode = "DOWNLOAD_FAILED"
            ErrorMessage = "Failed to download ZIP from $ZipUrl. Exception: $_"
            TempFiles = @($tempZip)
        }
    }
    
    Write-LogTrace "Creating extraction directory: $tempExtract"
    New-Item -Path $tempExtract -ItemType Directory -Force | Out-Null
    try {
        Write-LogTrace "Extracting ZIP file: $tempZip to $tempExtract"
        Expand-ZipSafely -ZipPath $tempZip -DestinationPath $tempExtract
        $extractedItemCount = (Get-ChildItem -Path $tempExtract -Recurse).Count
        Write-LogDebug "Extracted ZIP to temporary folder: $tempExtract (Items: $extractedItemCount)"
    }
    catch {
        Write-LogError "Extraction failed for $tempZip. Exception: $_"
        return @{
            Success = $false
            ErrorCode = "EXTRACTION_FAILED"
            ErrorMessage = "Extraction failed for $tempZip. Exception: $_"
            TempFiles = @($tempZip, $tempExtract)
        }
    }
    
    Write-LogTrace "ZIP staging completed successfully"
    return @{ 
        Success = $true
        TempZip = $tempZip
        TempExtract = $tempExtract 
    }
}

# -----------------------------------------------
# Function: Get File Manifest
# -----------------------------------------------
function Get-FileManifest {
    param ([Parameter(Mandatory = $true)][string]$Folder)
    $manifest = @{}
    $files = Get-ChildItem -Recurse -File -Path $Folder
    foreach ($file in $files) {
        if ($file.Name -eq ".downloaded.json") { continue }
        $relativePath = $file.FullName.Substring($Folder.Length + 1)
        try {
            $hash = (Get-FileHash -Algorithm SHA256 -Path $file.FullName -ErrorAction Stop).Hash
            $manifest[$relativePath] = $hash
        }
        catch {
            Write-LogWarning "Could not calculate hash for file: $($file.FullName). Error: $_"
            # Still include the file in the manifest with a placeholder hash
            $manifest[$relativePath] = "FILE_HASH_ERROR"
        }
    }
    return $manifest
}

# -----------------------------------------------
# Function: Test Expected Hash
# -----------------------------------------------
# Returns $true if the file's SHA256 matches the expected hash (or if no
# expected hash was supplied - i.e. the user opted out). $false on mismatch
# or read failure. Comparison is case-insensitive and tolerant of whitespace.
function Test-ExpectedHash {
    param (
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$false)][string]$ExpectedSha256 = ""
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) { return $true }

    try {
        $actual = (Get-FileHash -Algorithm SHA256 -Path $FilePath -ErrorAction Stop).Hash
    }
    catch {
        Write-LogError "Could not compute SHA256 for '$FilePath' to verify ExpectedSha256: $_"
        return $false
    }

    $expected = $ExpectedSha256.Trim()
    if ($actual -ieq $expected) {
        Write-LogDebug "SHA256 verified for '$FilePath' ($actual)"
        return $true
    }

    Write-LogError "SHA256 mismatch for '$FilePath': expected $expected, got $actual"
    return $false
}

# -----------------------------------------------
# Function: Get Tool Marker
# -----------------------------------------------
# Reads the .downloaded.json marker file and returns its parsed metadata,
# or $null if no marker exists. Used by both the dispatcher (to decide
# whether to skip up-to-date tools) and any TUI/inspection code.
function Get-ToolMarker {
    param ([Parameter(Mandatory=$true)][string]$OutputFolder)

    $markerFile = Join-Path $OutputFolder ".downloaded.json"
    if (-not (Test-Path $markerFile)) { return $null }
    try {
        return Get-Content -Path $markerFile -Raw | ConvertFrom-Json
    }
    catch {
        Write-LogWarning "Failed to read marker file at $markerFile : $_"
        return $null
    }
}

# -----------------------------------------------
# Function: Write Marker File
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
    Write-LogDebug "Marker file created at $markerFile"
}

# -----------------------------------------------
# Function: Remove Managed Files
# -----------------------------------------------
function Remove-ManagedFiles {
    param ([Parameter(Mandatory=$true)][string]$OutputFolder)
    $markerFile = Join-Path $OutputFolder ".downloaded.json"
    Write-LogDebug "Checking for marker file at: $markerFile"
    
    if (Test-Path $markerFile) {
        Write-LogDebug "Marker file found, attempting to process it"
        try {
            $metadata = Get-Content -Path $markerFile | ConvertFrom-Json
            Write-LogDebug "Marker file loaded successfully"
            
            if ($metadata.Manifest) {
                Write-LogDebug "Manifest found in marker file with type: $($metadata.Manifest.GetType().FullName)"
                
                # Create a hashtable to track files by hash
                $managedHashes = @{}
                
                # Handle PSCustomObject or Hashtable for Manifest
                if ($metadata.Manifest -is [System.Management.Automation.PSCustomObject]) {
                    Write-LogDebug "Processing PSCustomObject manifest"
                    # Convert PSCustomObject properties to hashtable entries
                    $propertyCount = ($metadata.Manifest.PSObject.Properties | Measure-Object).Count
                    Write-LogDebug "Found $propertyCount properties in PSCustomObject manifest"
                    
                    $metadata.Manifest.PSObject.Properties | ForEach-Object {
                        if ($null -ne $_.Value) {
                            $managedHashes[$_.Value] = $_.Name
                            Write-LogDebug "Added hash mapping: $($_.Value) -> $($_.Name)"
                        }
                        else {
                            Write-LogWarning "Skipping null hash value for path: $($_.Name)"
                        }
                    }
                } 
                else {
                    Write-LogDebug "Processing hashtable manifest"
                    # Original code for hashtable
                    $keyCount = ($metadata.Manifest.Keys | Measure-Object).Count
                    Write-LogDebug "Found $keyCount keys in hashtable manifest"
                    
                    foreach ($relativePath in $metadata.Manifest.Keys) {
                        $hash = $metadata.Manifest.$relativePath
                        if ($null -ne $hash) {
                            $managedHashes[$hash] = $relativePath
                            Write-LogDebug "Added hash mapping: $hash -> $relativePath"
                        }
                        else {
                            Write-LogWarning "Skipping null hash value for path: $relativePath"
                        }
                    }
                }
                
                # Get all files in the directory
                $currentFiles = Get-ChildItem -Path $OutputFolder -Recurse -File | 
                    Where-Object { $_.Name -ne ".downloaded.json" -and -not ($_.Name -match "\.save\d+$") }
                $fileCount = ($currentFiles | Measure-Object).Count
                Write-LogDebug "Found $fileCount files in output folder (excluding .downloaded.json and .save# files)"
                
                foreach ($file in $currentFiles) {
                    $relativePath = $file.FullName.Substring($OutputFolder.Length + 1)
                    Write-LogDebug "Processing file: $relativePath"
                    
                    # Calculate the hash of the current file
                    try {
                        $currentHash = (Get-FileHash -Algorithm SHA256 -Path $file.FullName -ErrorAction Stop).Hash
                        Write-LogDebug "File hash: $currentHash"
                        
                        # Check if this file is in our manifest (by hash)
                        if ($managedHashes.ContainsKey($currentHash)) {
                            # This is a managed file with unchanged content - remove it
                            Write-LogDebug "Hash match found, removing file: $($file.FullName)"
                            Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                            if (Test-Path $file.FullName) {
                                Write-LogWarning "Failed to remove file: $($file.FullName)"
                            } else {
                                Write-LogDebug "Successfully removed file: $($file.FullName)"
                            }
                        }
                        # Check if the relative path exists in the manifest
                        elseif (($metadata.Manifest -is [System.Management.Automation.PSCustomObject] -and 
                                $metadata.Manifest.PSObject.Properties.Name -contains $relativePath) -or
                                ($metadata.Manifest -is [System.Collections.IDictionary] -and 
                                $metadata.Manifest.ContainsKey($relativePath))) {
                            # This is a managed file with changed content - back it up
                            Write-LogDebug "Path match found, backing up modified file: $relativePath"
                            $backupNumber = 1
                            $backupPath = "$($file.FullName).save$backupNumber"
                            
                            # Find an available backup name
                            while (Test-Path $backupPath) {
                                $backupNumber++
                                $backupPath = "$($file.FullName).save$backupNumber"
                            }
                            
                            # Rename the file to the backup name
                            $newName = Split-Path $backupPath -Leaf
                            Write-LogInfo "Backing up modified file: $relativePath > $newName"
                            Rename-Item -Path $file.FullName -NewName $newName -Force
                            if (Test-Path $backupPath) {
                                Write-LogDebug "Successfully backed up file as: $newName"
                            } else {
                                Write-LogWarning "Failed to back up file: $($file.FullName)"
                            }
                        }
                        else {
                            Write-LogDebug "File not in manifest, leaving untouched: $relativePath"
                        }
                    }
                    catch {
                        Write-LogWarning "Could not process file: $($file.FullName). Error: $_"
                    }
                    # Files not in the manifest are left untouched (user-added files)
                }
                
                # Log count of .save# files if any exist
                $saveFiles = Get-ChildItem -Path $OutputFolder -Recurse -File | 
                    Where-Object { $_.Name -match "\.save\d+$" }
                $saveFileCount = ($saveFiles | Measure-Object).Count
                if ($saveFileCount -gt 0) {
                    Write-LogDebug "Found $saveFileCount backup (.save#) files in output folder. Skipping managed file removal for these files"
                }
            }
            else {
                Write-LogWarning "No manifest found in marker file"
            }
            
            # Always remove the marker file
            Write-LogDebug "Removing marker file: $markerFile"
            Remove-Item -Path $markerFile -Force -ErrorAction SilentlyContinue
            if (Test-Path $markerFile) {
                Write-LogWarning "Failed to remove marker file: $markerFile"
            } else {
                Write-LogDebug "Successfully removed marker file: $markerFile"
            }
        }
        catch {
            Write-LogWarning "Failed to remove managed files in $OutputFolder. Exception: $_"
        }
    }
    else {
        Write-LogDebug "No marker file found in $OutputFolder. No managed files to remove."
    }
}

# Helper function to download a file to a temporary location
function Save-FileToTemp {
    param (
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutputPath,
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = "PowerShell" },
        [Parameter(Mandatory=$false)][string]$ToolName = ""
    )
    
    try {
        $label = if ([string]::IsNullOrWhiteSpace($ToolName)) { "file" } else { $ToolName }
        Write-LogInfo "Downloading $label from $Url"
        Invoke-WithRetry -Description "file download for $label" -ScriptBlock {
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -Headers $Headers -ErrorAction Stop
        }
        $sizeMB = if (Test-Path $OutputPath) { (Get-Item $OutputPath).Length / 1MB } else { 0 }
        Write-LogInfo ("Downloaded {0} ({1:N1} MB)" -f $label, $sizeMB)
        return $true
    }
    catch {
        Write-LogError "Failed to download file for $ToolName from $Url. Exception: $_"
        return $false
    }
}

# Helper function to process non-ZIP files
function Save-NonZipFile {
    param (
        [Parameter(Mandatory=$true)][string]$FileUrl,
        [Parameter(Mandatory=$true)][string]$OutputFolder,
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$false)][string]$Version = "",
        [Parameter(Mandatory=$false)][string]$CommitHash = "",
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = "PowerShell" }
    )
    
    # Per-tool subfolder so parallel downloads with the same URL filename don't collide.
    $safeName = ($ToolConfig.Name -replace '[^A-Za-z0-9_.-]', '_')
    $stagingFolder = Join-Path $script:StagingRoot $safeName
    if (-not (Test-Path $stagingFolder)) { New-Item -Path $stagingFolder -ItemType Directory -Force | Out-Null }

    $fileName = Split-Path $FileUrl -Leaf
    $tempFile = Join-Path $stagingFolder $fileName
    
    try {
        try {
            if (-not (Save-FileToTemp -Url $FileUrl -OutputPath $tempFile -Headers $Headers -ToolName $ToolConfig.Name)) {
                throw "Download failed"
            }

            $expected = if ($ToolConfig.ContainsKey("ExpectedSha256")) { $ToolConfig.ExpectedSha256 } else { "" }
            if (-not (Test-ExpectedHash -FilePath $tempFile -ExpectedSha256 $expected)) {
                throw "SHA256 mismatch for $($ToolConfig.Name)"
            }

            $hash = (Get-FileHash -Algorithm SHA256 -Path $tempFile).Hash
            $newManifest = @{ $fileName = $hash }
            
            if (Test-Path (Join-Path $OutputFolder ".downloaded.json")) {
                Remove-ManagedFiles -OutputFolder $OutputFolder
            }
            
            $destinationPath = Join-Path $OutputFolder -ChildPath $fileName
            Copy-Item -Path $tempFile -Destination $destinationPath -Force
            Write-LogDebug "Copied file from temp to output folder: $destinationPath"
            
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
            Write-LogError "Failed to process file for $($ToolConfig.Name). Exception: $_"
            return $false
        }
    }
    finally {
        # Always clean up the temp file
        if (Test-Path $tempFile) {
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            Write-LogDebug "Cleaned up temporary file: $tempFile"
        }
    }
}

# Helper function to process extracted ZIP files
function Expand-StagedZip {
    param (
        [Parameter(Mandatory=$true)]$Staging,
        [Parameter(Mandatory=$true)][string]$OutputFolder,
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$DownloadUrl,
        [Parameter(Mandatory=$false)][string]$Version = ""
    )
    
    $tempExtract = $Staging.TempExtract
    
    # Check if the extraction contains a single folder
    $extractedItems = Get-ChildItem -Path $tempExtract
    $singleFolder = $null
    
    if ($extractedItems.Count -eq 1 -and $extractedItems[0].PSIsContainer) {
        $singleFolder = $extractedItems[0].FullName
        Write-LogDebug "Detected single folder in extraction: $($extractedItems[0].Name)"
        
        # Use the contents of the single folder for the manifest and copying
        $newManifest = Get-FileManifest -Folder $singleFolder
        
        if (Test-Path (Join-Path $OutputFolder ".downloaded.json")) {
            Remove-ManagedFiles -OutputFolder $OutputFolder
        }
        
        # Copy the contents of the single folder directly to the output folder
        Copy-Item -Path (Join-Path $singleFolder "*") -Destination $OutputFolder -Recurse -Force
        Write-LogDebug "Copied contents of single folder directly to output folder: $OutputFolder"
    }
    else {
        # Original behavior for multiple files/folders
        $newManifest = Get-FileManifest -Folder $tempExtract
        
        if (Test-Path (Join-Path $OutputFolder ".downloaded.json")) {
            Remove-ManagedFiles -OutputFolder $OutputFolder
        }
        
        Copy-Item -Path (Join-Path $tempExtract "*") -Destination $OutputFolder -Recurse -Force
        Write-LogDebug "Copied extracted files to output folder: $OutputFolder"
    }
    
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

# Helper function to set up the output folder
function Initialize-OutputFolder {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory
    )

    # Create the root tools directory on first use. Deferred from script
    # startup so -list and -DryRun don't have side effects.
    if (-not [System.IO.Directory]::Exists($ToolsDirectory)) {
        $drive = [System.IO.Path]::GetPathRoot($ToolsDirectory)
        if (-not [string]::IsNullOrEmpty($drive) -and -not [System.IO.Directory]::Exists($drive)) {
            Write-LogError "Drive '$drive' does not exist. Cannot create '$ToolsDirectory' for $($ToolConfig.Name)."
            return $null
        }
        try {
            New-Item -Path $ToolsDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-LogInfo "Created tools directory: $ToolsDirectory"
        }
        catch {
            Write-LogError "Failed to create tools directory '$ToolsDirectory' for $($ToolConfig.Name): $_"
            return $null
        }
    }

    try {
        if (-not [string]::IsNullOrEmpty($ToolConfig.OutputFolder)) {
            $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $ToolConfig.OutputFolder $ToolConfig.Name)
        }
        else {
            $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath $ToolConfig.Name
        }

        # Defense-in-depth: validation in Test-ToolEntry should prevent this,
        # but verify the resolved path stays within $ToolsDirectory before
        # creating it.
        $rootFull = [System.IO.Path]::GetFullPath($ToolsDirectory).TrimEnd([char]'\', [char]'/') + [System.IO.Path]::DirectorySeparatorChar
        $outFull  = [System.IO.Path]::GetFullPath($outputFolder)
        if (-not $outFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-LogError "Refusing to create output folder outside the tools directory: '$outFull' (root='$rootFull')"
            return $null
        }

        if (-not (Test-Path -Path $outputFolder)) {
            New-Item -Path $outputFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-LogDebug "Created output folder: $outputFolder"
        }

        return $outputFolder
    }
    catch {
        Write-LogError "Failed to create output folder for $($ToolConfig.Name). Exception: $_"
        return $null
    }
}

# Helper function to get GitHub API headers
function Invoke-WithRetry {
    <#
    .SYNOPSIS
    Run a script block with exponential backoff retries on transient failures.
    Skips retry for 4xx HTTP responses (those are usually permanent - bad URL,
    missing asset, auth failure).
    #>
    param (
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory=$false)][int]$MaxAttempts = 3,
        [Parameter(Mandatory=$false)][int[]]$DelaysSeconds = @(1, 2, 4),
        [Parameter(Mandatory=$false)][string]$Description = "operation"
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $ScriptBlock
        }
        catch {
            $isLast = $attempt -eq $MaxAttempts

            # Identify 4xx (don't retry) vs 5xx/network (retry).
            $statusCode = $null
            if ($_.Exception.Response) {
                try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
            }

            $isClientError = ($null -ne $statusCode -and $statusCode -ge 400 -and $statusCode -lt 500)
            if ($isClientError -or $isLast) { throw }

            $delay = $DelaysSeconds[[Math]::Min($attempt - 1, $DelaysSeconds.Length - 1)]
            Write-LogWarning "$Description failed (attempt $attempt/$MaxAttempts): $($_.Exception.Message). Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
}

function Expand-ZipSafely {
    <#
    .SYNOPSIS
    Extract a ZIP archive while validating each entry resolves under the
    destination - defends against Zip-Slip (entries with '..' or absolute
    paths that escape the target folder). PowerShell 5.1's Expand-Archive
    has had Zip-Slip vulnerabilities historically.
    #>
    param (
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [Parameter(Mandatory=$true)][string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    if (-not (Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }
    $destFull = [System.IO.Path]::GetFullPath($DestinationPath).TrimEnd([char]'\', [char]'/') + [System.IO.Path]::DirectorySeparatorChar

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $zip.Entries) {
            $target = [System.IO.Path]::GetFullPath((Join-Path $DestinationPath $entry.FullName))
            if (-not $target.StartsWith($destFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Zip-Slip detected: entry '$($entry.FullName)' would extract to '$target', outside '$destFull'"
            }

            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
                continue
            }

            $parent = [System.IO.Path]::GetDirectoryName($target)
            if ($parent -and -not (Test-Path $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
    }
    finally {
        $zip.Dispose()
    }
}

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

# Returns the repo's default branch (e.g. "main" or "master") via the GitHub API,
# or $null if the lookup fails. Used when a tool's YAML entry omits Branch.
function Get-GitHubDefaultBranch {
    param (
        [Parameter(Mandatory=$true)][string]$RepoUrl,
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = "PowerShell" }
    )

    if ($RepoUrl -notmatch "github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$") {
        Write-LogWarning "Cannot determine default branch: '$RepoUrl' is not a github.com URL"
        return $null
    }
    $owner = $matches[1]
    $repo  = $matches[2]

    try {
        $info = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo" -Headers $Headers -ErrorAction Stop
        Write-LogDebug "Default branch for $owner/${repo}: $($info.default_branch)"
        return $info.default_branch
    }
    catch {
        Write-LogWarning "Failed to query default branch for $owner/${repo}: $_"
        return $null
    }
}

# -----------------------------------------------
# Function: Download Specific File Tool
# -----------------------------------------------
function Save-SpecificFileTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "Name")) { return }
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "RepoUrl")) { return }
    
    # Handle optional parameters with defaults
    $extract = Get-DefaultValue -Tool $ToolConfig -Parameter "Extract" -DefaultValue $true
    
    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    if ($null -eq $outputFolder) {
        Write-LogError "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
        return
    }
    
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
    
    Write-LogDebug "Constructed URL: $fileUrl"
    
    $ext = [System.IO.Path]::GetExtension($downloadName)
    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT
    
    if ($ext -ieq ".zip") {
        if ($extract) {
            $expected = if ($ToolConfig.ContainsKey("ExpectedSha256")) { $ToolConfig.ExpectedSha256 } else { "" }
            $staging = Invoke-ZipStaging -ZipUrl $fileUrl -ToolName $ToolConfig.Name -Version "latest" -Headers $headers -ExpectedSha256 $expected
            if (-not $staging.Success) {
                # Clean up any temporary files
                foreach ($tempFile in $staging.TempFiles) {
                    if (Test-Path $tempFile) {
                        Remove-Item -Path $tempFile -Force -Recurse -ErrorAction SilentlyContinue
                        Write-LogDebug "Cleaned up temporary file/folder: $tempFile"
                    }
                }
                Write-LogError "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
                return
            }
            
            Expand-StagedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $fileUrl | Out-Null
        }
        else {
            Save-NonZipFile -FileUrl $fileUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Headers $headers | Out-Null
        }
    }
    else {
        Save-NonZipFile -FileUrl $fileUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Headers $headers | Out-Null
    }
}

# -----------------------------------------------
# Function: Download Branch Zip Tool
# -----------------------------------------------
function Save-BranchZipTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "Name")) { return }
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "RepoUrl")) { return }
    
    # Handle optional parameters with defaults
    $extract = Get-DefaultValue -Tool $ToolConfig -Parameter "Extract" -DefaultValue $true

    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    if ($null -eq $outputFolder) {
        Write-LogError "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
        return
    }

    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT

    # Resolve branch: use YAML-supplied value, or query default_branch from the API
    $branch = Get-DefaultValue -Tool $ToolConfig -Parameter "Branch"
    if ([string]::IsNullOrWhiteSpace($branch)) {
        $branch = Get-GitHubDefaultBranch -RepoUrl $ToolConfig.RepoUrl -Headers $headers
        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-LogError "Could not determine default branch for $($ToolConfig.Name); skipping."
            return
        }
    }

    $zipUrl = "$($ToolConfig.RepoUrl)/archive/refs/heads/$branch.zip"
    Write-LogInfo "Downloading branch zip for $($ToolConfig.Name) (branch: $branch)..."
    
    if ($extract) {
        $expected = if ($ToolConfig.ContainsKey("ExpectedSha256")) { $ToolConfig.ExpectedSha256 } else { "" }
        $staging = Invoke-ZipStaging -ZipUrl $zipUrl -ToolName $ToolConfig.Name -Version $branch -Headers $headers -ExpectedSha256 $expected
        if (-not $staging.Success) {
            # Clean up any temporary files
            foreach ($tempFile in $staging.TempFiles) {
                if (Test-Path $tempFile) {
                    Remove-Item -Path $tempFile -Force -Recurse -ErrorAction SilentlyContinue
                    Write-LogDebug "Cleaned up temporary file/folder: $tempFile"
                }
            }
            Write-LogError "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
            return
        }
        
        Expand-StagedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $zipUrl -Version $branch | Out-Null
    }
    else {
        Save-NonZipFile -FileUrl $zipUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Version $branch -Headers $headers | Out-Null
    }
}

# -----------------------------------------------
# Function: Download Latest Release Tool
# -----------------------------------------------
function Save-LatestReleaseTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "Name")) { return }
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "RepoUrl")) { return }
    
    # Handle optional parameters with defaults
    $extract = Get-DefaultValue -Tool $ToolConfig -Parameter "Extract" -DefaultValue $true
    
    $apiRepoUrl = $ToolConfig.RepoUrl -replace "https://github.com/", "https://api.github.com/repos/"
    $releaseUri = "$apiRepoUrl/releases/latest"
    Write-LogDebug "Using API endpoint: $releaseUri for $($ToolConfig.Name)"
    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT
    
    try {
        $releaseInfo = Invoke-RestMethod -Uri $releaseUri -Headers $headers
        Write-LogDebug "Retrieved release info. Assets count: $($releaseInfo.assets.Count)"
    }
    catch {
        Write-LogError "Failed to get release info for $($ToolConfig.Name). Exception: $_"
        return
    }

    # Skip if the local marker's Version matches the upstream tag (and the user
    # didn't pass -ForceDownload).
    if (-not $ForceDownload) {
        $existingFolder = if (-not [string]::IsNullOrEmpty($ToolConfig.OutputFolder)) {
            Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $ToolConfig.OutputFolder $ToolConfig.Name)
        } else {
            Join-Path -Path $ToolsDirectory -ChildPath $ToolConfig.Name
        }
        $marker = Get-ToolMarker -OutputFolder $existingFolder
        if ($marker -and $marker.Version -eq $releaseInfo.tag_name) {
            Write-LogInfo "$($ToolConfig.Name) is up to date (version $($releaseInfo.tag_name)); skipping."
            return
        }
    }

    # Filter assets based on configuration
    $assets = $releaseInfo.assets
    if (-not [string]::IsNullOrEmpty($ToolConfig.DownloadName)) {
        $assets = $assets | Where-Object { $_.name -eq $ToolConfig.DownloadName }
    }
    elseif (-not [string]::IsNullOrEmpty($ToolConfig.AssetFilename)) {
        $assets = $assets | Where-Object { $_.name -match $ToolConfig.AssetFilename }
    }
    elseif (-not [string]::IsNullOrEmpty($ToolConfig.AssetType)) {
        if ($script:AssetPatterns.ContainsKey($ToolConfig.AssetType)) {
            $pattern = $script:AssetPatterns[$ToolConfig.AssetType]
            $assets = $assets | Where-Object { $_.name -match $pattern }
        }
        else {
            Write-LogWarning "No pattern defined for AssetType '$($ToolConfig.AssetType)' for $($ToolConfig.Name)."
        }
    }
    
    $asset = $assets | Select-Object -First 1
    if ($asset) {
        $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
        if ($null -eq $outputFolder) {
            Write-LogError "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
            return
        }
        
        $downloadUrl = $asset.browser_download_url
        $fileName = Split-Path $downloadUrl -Leaf
        $ext = [System.IO.Path]::GetExtension($fileName)
        
        if ($ext -ieq ".zip") {
            if ($extract) {
                $expected = if ($ToolConfig.ContainsKey("ExpectedSha256")) { $ToolConfig.ExpectedSha256 } else { "" }
                $staging = Invoke-ZipStaging -ZipUrl $downloadUrl -ToolName $ToolConfig.Name -Version $releaseInfo.tag_name -Headers $headers -ExpectedSha256 $expected
                if (-not $staging.Success) {
                    # Clean up any temporary files
                    foreach ($tempFile in $staging.TempFiles) {
                        if (Test-Path $tempFile) {
                            Remove-Item -Path $tempFile -Force -Recurse -ErrorAction SilentlyContinue
                            Write-LogDebug "Cleaned up temporary file/folder: $tempFile"
                        }
                    }
                    Write-LogError "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
                    return
                }
                
                Expand-StagedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $downloadUrl -Version $releaseInfo.tag_name | Out-Null
            }
            else {
                Save-NonZipFile -FileUrl $downloadUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Version $releaseInfo.tag_name -Headers $headers | Out-Null
            }
        }
        else {
            Save-NonZipFile -FileUrl $downloadUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Version $releaseInfo.tag_name -Headers $headers | Out-Null
        }
    }
    else {
        Write-LogWarning "No matching asset found for $($ToolConfig.Name)."
    }
}

# -----------------------------------------------
# Function: Download Git Clone Tool
# -----------------------------------------------
function Save-GitCloneTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "Name")) { return }
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "RepoUrl")) { return }

    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    if ($null -eq $outputFolder) {
        Write-LogError "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
        return
    }

    # Extract owner and repo from URL
    Write-LogTrace "Extracting owner and repo from URL: $($ToolConfig.RepoUrl)"
    if ($ToolConfig.RepoUrl -match "github\.com/([^/]+)/([^/]+)") {
        $owner = $matches[1]
        $repo = $matches[2]
        $repo = $repo -replace "\.git$", ""
        Write-LogDebug "Extracted owner: $owner, repo: $repo"
    }
    else {
        Write-LogError "Invalid GitHub URL format for $($ToolConfig.Name): $($ToolConfig.RepoUrl)"
        return
    }

    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT

    # Resolve branch: use the YAML-supplied value, or query the repo's default_branch.
    $branch = Get-DefaultValue -Tool $ToolConfig -Parameter "Branch"
    if ([string]::IsNullOrWhiteSpace($branch)) {
        $branch = Get-GitHubDefaultBranch -RepoUrl $ToolConfig.RepoUrl -Headers $headers
        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-LogError "Could not determine default branch for $($ToolConfig.Name); skipping."
            return
        }
    }

    # Get the latest commit on the resolved branch
    $apiUrl = "https://api.github.com/repos/$owner/$repo/branches/$branch"
    Write-LogDebug "Querying GitHub API: $apiUrl"

    try {
        $branchInfo = Invoke-RestMethod -Uri $apiUrl -Headers $headers
        $commitHash = $branchInfo.commit.sha
        Write-LogDebug "Latest commit hash for ${branch}: ${commitHash}"
    }
    catch {
        Write-LogError "Failed to get branch info for $($ToolConfig.Name). Exception: $_"
        return
    }

    # Skip if the local marker's CommitHash matches HEAD on this branch.
    if (-not $ForceDownload) {
        $marker = Get-ToolMarker -OutputFolder $outputFolder
        if ($marker -and $marker.CommitHash -eq $commitHash) {
            Write-LogInfo "$($ToolConfig.Name) is up to date (commit $($commitHash.Substring(0,7))); skipping."
            return
        }
    }

    # Download ZIP archive of the branch
    $zipUrl = "https://github.com/$owner/$repo/archive/$commitHash.zip"
    Write-LogInfo "Downloading repository ZIP for $($ToolConfig.Name) from branch $branch (commit $commitHash)..."
    Write-LogDebug "ZIP URL: $zipUrl"
    
    $staging = Invoke-ZipStaging -ZipUrl $zipUrl -ToolName $ToolConfig.Name -Version $branch -Headers $headers
    if (-not $staging.Success) {
        # Clean up any temporary files
        foreach ($tempFile in $staging.TempFiles) {
            if (Test-Path $tempFile) {
                Remove-Item -Path $tempFile -Force -Recurse -ErrorAction SilentlyContinue
                Write-LogDebug "Cleaned up temporary file/folder: $tempFile"
            }
        }
        Write-LogError "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
        return
    }
    
    # Process the extracted files
    $tempExtract = $staging.TempExtract
    Write-LogTrace "Generating file manifest for extracted content"
    $newManifest = Get-FileManifest -Folder $tempExtract
    Write-LogDebug "Generated manifest with ${newManifest.Count} files"
    
    if (Test-Path (Join-Path $outputFolder ".downloaded.json")) {
        Write-LogDebug "Removing previously managed files from $outputFolder"
        Remove-ManagedFiles -OutputFolder $outputFolder
    }
    
    Write-LogDebug "Copying extracted files to output folder: $outputFolder"
    Copy-Item -Path (Join-Path $tempExtract "*") -Destination $outputFolder -Recurse -Force
    Write-LogDebug "Copied extracted files to output folder: $outputFolder"
    
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
    Write-LogTrace "Cleaning up temporary files"
    Remove-Item -Path $staging.TempExtract -Recurse -Force
    Remove-Item -Path $staging.TempZip -Force
    
    Write-LogInfo "Successfully downloaded and extracted $($ToolConfig.Name) from branch $branch (commit $commitHash)"
}

# -----------------------------------------------
# Function: Invoke Tool Work (one tool's full update + dispatch)
# -----------------------------------------------
# Encapsulates one iteration of the dispatcher loop so it can be invoked
# either sequentially (foreach) or in parallel (ForEach-Object -Parallel).
# All mutable state (Tool config, target dir, PAT, mode flags) is passed
# explicitly so the function works inside a fresh runspace.
function Invoke-ToolWork {
    param (
        [Parameter(Mandatory=$true)]$Tool,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = "",
        [Parameter(Mandatory=$false)][string]$UpdateMode = $null,
        [Parameter(Mandatory=$false)][string[]]$UpdateToolList = @(),
        [Parameter(Mandatory=$false)][switch]$ForceDownload,
        [Parameter(Mandatory=$false)][switch]$DryRun
    )

    try {
        # Skip placeholder entries (Name set, RepoUrl + DownloadMethod empty).
        if ([string]::IsNullOrWhiteSpace($Tool.RepoUrl) -and [string]::IsNullOrWhiteSpace($Tool.DownloadMethod)) {
            Write-LogDebug "Skipping placeholder entry: $($Tool.Name)"
            return
        }

        if (-not [string]::IsNullOrEmpty($Tool.OutputFolder)) {
            $toolOutputFolder = Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $Tool.OutputFolder $Tool.Name)
        }
        else {
            $toolOutputFolder = Join-Path -Path $ToolsDirectory -ChildPath $Tool.Name
        }
        $markerFile = Join-Path $toolOutputFolder ".downloaded.json"

        $processTool = $false

        if ($UpdateMode -eq "specific") {
            if ($UpdateToolList -contains $Tool.Name.ToLower()) {
                $processTool = $true
                Write-Host "===========================================" -ForegroundColor White
                if (Test-Path $toolOutputFolder) {
                    Write-LogInfo "Updating tool: $($Tool.Name)"
                    if (Test-Path $markerFile) {
                        if ($DryRun) {
                            Write-LogInfo "[DRY-RUN] Would remove managed files for $($Tool.Name)."
                        } else {
                            Write-LogDebug "Update: Removing previous files for $($Tool.Name)."
                            Remove-ManagedFiles -OutputFolder $toolOutputFolder
                        }
                    }
                }
                else {
                    Write-LogInfo "Tool $($Tool.Name) not found locally. Will download it."
                }
            }
        }
        elseif ($UpdateMode -eq "general") {
            if (Test-Path $toolOutputFolder) {
                if ($ForceDownload) {
                    $processTool = $true
                    Write-Host "===========================================" -ForegroundColor White
                    Write-LogInfo "Force updating tool: $($Tool.Name)"
                    if (Test-Path $markerFile) {
                        if ($DryRun) {
                            Write-LogInfo "[DRY-RUN] Would remove managed files for $($Tool.Name)."
                        } else {
                            Write-LogDebug "Update: Removing previous files for $($Tool.Name)."
                            Remove-ManagedFiles -OutputFolder $toolOutputFolder
                        }
                    }
                    else {
                        Write-LogDebug "Update: No marker file found for $($Tool.Name); preserving user files."
                    }
                }
                elseif (-not $Tool.skipdownload) {
                    $processTool = $true
                    Write-Host "===========================================" -ForegroundColor White
                    Write-LogInfo "Updating tool: $($Tool.Name)"
                    if (Test-Path $markerFile) {
                        if ($DryRun) {
                            Write-LogInfo "[DRY-RUN] Would remove managed files for $($Tool.Name)."
                        } else {
                            Write-LogDebug "Update: Removing previous files for $($Tool.Name)."
                            Remove-ManagedFiles -OutputFolder $toolOutputFolder
                        }
                    }
                    else {
                        Write-LogDebug "Update: No marker file found for $($Tool.Name); preserving user files."
                    }
                }
                else {
                    Write-LogInfo "Skipping update for $($Tool.Name) -- skipdownload is enabled. Use -force to override."
                }
            }
        }
        else {
            if ($ForceDownload) {
                $processTool = $true
                Write-Host "===========================================" -ForegroundColor White
                Write-LogInfo "Force downloading $($Tool.Name)..."
            }
            else {
                if ($Tool.skipdownload) {
                    Write-LogInfo "Skipping $($Tool.Name) -- skipdownload is enabled."
                }
                elseif (Test-Path $markerFile) {
                    Write-LogInfo "Skipping $($Tool.Name) -- already downloaded."
                }
                else {
                    $processTool = $true
                    Write-Host "===========================================" -ForegroundColor White
                    Write-LogInfo "Started working on $($Tool.Name)..."
                }
            }
        }

        if (-not $processTool) { return }

        if ($DryRun) {
            Write-LogInfo "[DRY-RUN] Would $($Tool.DownloadMethod) tool: $($Tool.Name) -> $toolOutputFolder"
            Write-Host "===========================================" -ForegroundColor White
            return
        }

        switch ($Tool.DownloadMethod) {
            "gitClone" {
                Save-GitCloneTool -ToolConfig $Tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT
            }
            "latestRelease" {
                Save-LatestReleaseTool -ToolConfig $Tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT
            }
            "branchZip" {
                Save-BranchZipTool -ToolConfig $Tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT
            }
            "specificFile" {
                Save-SpecificFileTool -ToolConfig $Tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT
            }
            default {
                Write-LogError "Download method '$($Tool.DownloadMethod)' not recognized for $($Tool.Name)."
            }
        }
        Write-LogInfo "Finished working on $($Tool.Name)."
        Write-Host "===========================================" -ForegroundColor White
    }
    catch {
        Write-LogError "Failed to process tool $($Tool.Name). Exception: $_"
    }
}

if (-not $SourceOnly) {

# Interactive mode short-circuits the dispatcher: it loads the TUI module,
# presents a picker, runs the user's selection, and exits. This branch is
# placed AFTER all engine function definitions so Show-ToolFetcherTUI can
# call Get-ToolMarker / Invoke-ToolWork / etc. directly.
if ($Interactive) {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-LogError "-Interactive requires PowerShell 7+ (you're on $($PSVersionTable.PSVersion))."
        exit 1
    }
    $uiPath = Join-Path $PSScriptRoot "ToolFetcherUI.ps1"
    if (-not (Test-Path $uiPath)) {
        Write-LogError "Could not find ToolFetcherUI.ps1 next to the engine ($uiPath)."
        exit 1
    }
    . $uiPath
    Show-ToolFetcherTUI -Tools $tools `
                        -ToolsDirectory $ToolsDirectory `
                        -GitHubPAT $GitHubPAT `
                        -ThrottleLimit $ThrottleLimit
    if (Test-Path $script:StagingRoot) {
        Remove-Item -Path $script:StagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

# -----------------------------------------------
# Dispatcher: Loop Through Tools and Process
# -----------------------------------------------
# The tools directory is created lazily by Initialize-OutputFolder when the
# first download lands - no need for an upfront existence check here.

# Decide between sequential and parallel dispatch.
$useParallel = $Parallel -and ($PSVersionTable.PSVersion.Major -ge 7)
if ($Parallel -and -not $useParallel) {
    Write-LogWarning "-Parallel requires PowerShell 7+ (you're on $($PSVersionTable.PSVersion)). Falling back to sequential."
}

if ($useParallel) {
    Write-LogInfo "Running with parallel dispatch (ThrottleLimit=$ThrottleLimit)."
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrEmpty($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }
    $logFileSnapshot     = $script:LogFile
    $logEnabledSnapshot  = $script:LoggingEnabled

    $tools | ForEach-Object -Parallel {
        # Each runspace dot-sources the script with -SourceOnly to import every
        # function and script-scope state. We then restore log settings from
        # the parent so file logging works across runspaces.
        . $using:scriptPath -SourceOnly
        $script:LogFile        = $using:logFileSnapshot
        $script:LoggingEnabled = $using:logEnabledSnapshot

        Invoke-ToolWork -Tool $_ `
                        -ToolsDirectory $using:ToolsDirectory `
                        -GitHubPAT $using:GitHubPAT `
                        -UpdateMode $using:updateMode `
                        -UpdateToolList $using:updateToolList `
                        -ForceDownload:$using:ForceDownload `
                        -DryRun:$using:DryRun
    } -ThrottleLimit $ThrottleLimit
}
else {
    foreach ($tool in $tools) {
        Invoke-ToolWork -Tool $tool `
                        -ToolsDirectory $ToolsDirectory `
                        -GitHubPAT $GitHubPAT `
                        -UpdateMode $updateMode `
                        -UpdateToolList $updateToolList `
                        -ForceDownload:$ForceDownload `
                        -DryRun:$DryRun
    }
}

# Best-effort cleanup of the per-process staging folder.
if (Test-Path $script:StagingRoot) {
    Remove-Item -Path $script:StagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}

} # end: if (-not $SourceOnly) for main-flow-B (dispatcher)
