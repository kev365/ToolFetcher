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
    One or more YAML files containing tool definitions (local paths or URLs). Several files can
    be given as an array or as a comma-separated list; their tools arrays are merged and the
    first non-empty tooldirectory wins.
    Default: "tools.yaml" in the same directory as the script.

.PARAMETER ToolsDirectory
    Directory where tools will be downloaded and extracted. Relative paths are resolved against
    the current location. If not specified, the value from the YAML file will be used. If neither
    is specified, tools are downloaded next to the script and a warning says so. The directory
    is created on the first real download, so -ListTools and -DryRun leave nothing behind.

.PARAMETER Tag
    Only process entries whose Category matches one of the given tags. Each tool_groups file
    carries a file-level 'category:' (its file name); entries can set their own Category.

.PARAMETER DryRun
    Show what would be downloaded or updated without writing anything. In update mode the
    upstream is still asked whether a tool changed, so the preview is accurate.

.PARAMETER Parallel
    Download several tools at once (PowerShell 7+). Metadata is resolved serially first; only
    the downloads run in parallel. On Windows PowerShell 5.1 a warning is shown and the run is
    sequential.

.PARAMETER ThrottleLimit
    Maximum concurrent downloads when -Parallel is set. Default: 4.

.PARAMETER ForceDownload
    Re-download a tool even if it is installed and up to date. Managed files are replaced;
    modified managed files are kept as .saveN backups; user-added files are never touched.
    When used with -UpdateAll, it also updates tools that have skipdownload: true.

.PARAMETER UpdateAll
    Update all previously downloaded tools that have downloads enabled (skipdownload: false).
    Tools whose upstream has not changed and whose files are intact are skipped; modified or
    missing managed files trigger a fresh download. Updates preserve user modifications by only
    removing managed files (tracked in .downloaded.json). Use -ForceDownload to re-download all.

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
    - YAML configuration support (multiple files, categories, optional SHA256 pinning)
    - Multiple download methods
    - Update management with up-to-date detection (release tag, commit, upstream ETag)
    - File manifest tracking; a failed update never removes the previous version
    - Parallel downloads on PowerShell 7+
    - Detailed logging, run summary and exit code 1 when a tool fails
    - GitHub API rate limit handling (conditional requests, retries, clear diagnosis)
    - Secure token input and token scrubbing in logs
    - Cross-platform asset support

    For more information, visit:
    https://github.com/kev365/ToolFetcher
    https://dfir-kev.medium.com/tool-fetcher-499c99aaa9fa
#>

# PSScriptAnalyzer: Write-Host is the console UI by design (colours, separators); the plural
# nouns are established function names; the state-changing helpers are internal, not cmdlets.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Console UI by design')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Established function names')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal helpers, not cmdlets')]
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

# ZIP support: System.IO.Compression.FileSystem is not loaded by default on Windows PowerShell 5.1.
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

# Script version - centralized for easy updates
$script:Version = "2.2.0"

# Pin powershell-yaml to a known-good version. PSGallery is the trusted
# default, but pinning protects against supply-chain compromise of the module.
$script:RequiredYamlVersion = "0.4.7"

# Per-process staging folder under the system temp path. Each download writes
# transient files here, then copies the final result into $ToolsDirectory.
# Lives outside $PSScriptRoot so the script can run from a read-only location,
# and embeds the PID so concurrent invocations don't collide.
$script:StagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ToolFetcher_$PID"

# Folder the script lives in. Falls back to the current location when there is no script
# file (pasted into a console, Invoke-Expression), where $PSScriptRoot is empty.
$script:BaseDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:BaseDir)) { $script:BaseDir = (Get-Location).ProviderPath }

# Asset filename patterns for the latestRelease download method's AssetType filter.
# Built once at script load rather than on every Save-LatestReleaseTool call.
# Each OS pattern requires an OS marker in the asset name and rejects the other
# architectures, so "win64" can no longer pick a "linux-x64" or "win-arm64" asset
# when a release ships several platforms. Anchored with ^ so the lookaheads scan
# the whole name exactly once.
$script:AssetPatterns = @{
    "win64"   = "(?i)^(?=.*(?<!dar)win)(?!.*(linux|darwin|apple|macos|osx|arm64|aarch64|arm32|armv|win32|32[-_]?bit|i386|x86(?!_64)))(?=.*(win64|x64|x86_64|amd64|64[-_]?bit))"
    "win32"   = "(?i)^(?=.*(?<!dar)win)(?!.*(linux|darwin|apple|macos|osx|arm64|aarch64|arm32|armv|win64|x64|x86_64|amd64|64[-_]?bit))(?=.*(win32|x86|i386|386|32[-_]?bit))"
    "linux64" = "(?i)^(?=.*(linux|lin[-_]))(?!.*(win|darwin|apple|macos|osx|arm64|aarch64|arm32|armv|i386|i686|32[-_]?bit|x86(?!_64)))(?=.*(64|x64|x86_64|amd64))"
    "linux32" = "(?i)^(?=.*(linux|lin[-_]))(?!.*(win|darwin|apple|macos|osx|arm64|aarch64|arm32|armv|x64|x86_64|amd64|64[-_]?bit))(?=.*(32|x86|i386|i686|386))"
    "macos64" = "(?i)^(?=.*(macos|darwin|osx|mac[-_]))(?=.*(64|x64|x86_64|arm64|aarch64|universal))"
    "macos32" = "(?i)^(?=.*(macos|darwin|osx|mac[-_]))(?!.*(64|x64|x86_64|arm64|aarch64))(?=.*(32|x86|i386|386))"
    "arm64"   = "(?i)(arm64|aarch64|armv8)"
    "arm32"   = "(?i)(arm32|armv7|armv6|armhf)"
}

# HTTP settings. -TimeoutSec bounds the whole request on PowerShell 7 (HttpClient) and
# connect+headers on 5.1, so downloads get a generous value; -OperationTimeoutSeconds (7.4+)
# additionally aborts a stalled stream. Every Invoke-WebRequest also passes -UseBasicParsing:
# on patched Windows PowerShell 5.1 (CVE-2025-54100) a call that parses a response without it
# prompts for confirmation, which fails outright in non-interactive runs.
$script:ApiTimeoutSec      = 30
$script:DownloadTimeoutSec = 900
$script:UserAgent          = "ToolFetcher/$script:Version"
$script:DownloadExtraArgs  = @{}
if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey('OperationTimeoutSeconds')) {
    $script:DownloadExtraArgs['OperationTimeoutSeconds'] = 120
}

# -----------------------------------------------
# Define Logging Functions First
# -----------------------------------------------
# Log levels. A PowerShell enum (5.0+) avoids the C# compiler start-up that Add-Type costs in
# every new process, including each parallel runspace's first iteration.
enum LogLevel {
    Error = 0
    Warning = 1
    Info = 2
    Debug = 3
    Trace = 4
}

$script:LogFile = $null
$script:LoggingEnabled = $false
$script:LogMutexName = $null
# Set when a GitHub API rate limit is hit; later API-dependent tools are skipped until then.
$script:RateLimitedUntil = $null
$script:RateLimitRemaining = $null

# Patterns used to redact secrets from log output. Catches GitHub PATs in
# 'token <pat>', 'Authorization: token <pat>', and 'Bearer <pat>' forms,
# plus the new fine-grained PAT prefix (github_pat_).
$script:SecretRedactPatterns = @(
    '(?i)(token\s+)(gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|[A-Fa-f0-9]{40,})'
    '(?i)(Bearer\s+)(gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|[A-Fa-f0-9]{40,})'
)

function Format-RedactedMessage {
    param ([Parameter(Mandatory=$true)][string]$Text)
    # Fast path: nothing can need redacting when this run holds no token.
    if ([string]::IsNullOrEmpty($script:GitHubPAT)) { return $Text }
    # The literal token first (URLs, exception text), then the contextual patterns.
    $Text = $Text.Replace($script:GitHubPAT, '<REDACTED>')
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

    # Early out: skip redaction, timestamping and formatting when nothing consumes the line
    # (Debug/Trace below the console threshold and no file logging).
    $wanted = -not $NoConsole
    if ($Level -eq [LogLevel]::Debug -and -not $script:VerboseOutput) { $wanted = $false }
    if ($Level -eq [LogLevel]::Trace -and -not $script:TraceOutput) { $wanted = $false }
    if (-not $wanted -and -not $script:LoggingEnabled) { return }

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
        if ($Level -eq [LogLevel]::Debug -and -not $script:VerboseOutput) { $showOnConsole = $false }
        if ($Level -eq [LogLevel]::Trace -and -not $script:TraceOutput) { $showOnConsole = $false }

        if ($showOnConsole) {
            Write-Host $logMessage -ForegroundColor $ForegroundColor
        }
    }

    # Write to log file if enabled - always write all levels to log file
    if ($script:LoggingEnabled -and $script:LogFile) {
        # Serialize appends across parallel runspaces with a named mutex (microseconds when
        # uncontended). An abandoned mutex is acquired anyway.
        $logMutex = $null
        if ($script:LogMutexName) {
            try {
                $logMutex = New-Object System.Threading.Mutex($false, $script:LogMutexName)
                try { [void]$logMutex.WaitOne(10000) } catch [System.Threading.AbandonedMutexException] { $null = $_ }
            } catch { $logMutex = $null }
        }
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
        finally {
            if ($logMutex) { try { $logMutex.ReleaseMutex() } catch { $null = $_ }; $logMutex.Dispose() }
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
        # Named mutex so parallel runspaces (and a second ToolFetcher process) serialize
        # appends to this file. The name is derived from the path ('Local\' = this session).
        $pathHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($LogPath.ToLowerInvariant()))
        $script:LogMutexName = 'Local\ToolFetcher_' + ([System.BitConverter]::ToString($pathHash) -replace '-', '').Substring(0, 32)

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

# Applies the parent run's mutable state inside a ForEach-Object -Parallel runspace. Pooled
# runspaces keep functions but lose every variable between iterations, so the parallel block
# dot-sources this script with -SourceOnly on every iteration and then calls this with the
# hashtable the parent captured (see the dispatcher).
function Set-ToolFetcherRunState {
    param ([Parameter(Mandatory=$true)][hashtable]$State)
    $script:LogFile        = $State.LogFile
    $script:LoggingEnabled = [bool]$State.LoggingEnabled
    $script:LogMutexName   = $State.LogMutexName
    $script:VerboseOutput  = [bool]$State.VerboseOutput
    $script:TraceOutput    = [bool]$State.TraceOutput
    $script:GitHubPAT      = [string]$State.GitHubPAT
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
        $methodLabel = if (Test-PlaceholderEntry -Tool $tool) { "PLACEHOLDER" } else { $tool.DownloadMethod }
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
            if ($tool.ContainsKey("Category") -and -not [string]::IsNullOrWhiteSpace("$($tool.Category)")) {
                Write-Host "  Category: $(@($tool.Category) -join ', ')" -ForegroundColor Gray
            }

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
    $headers = @{ "Authorization" = "token $Token"; "User-Agent" = $script:UserAgent }
    try {
        $user = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -TimeoutSec $script:ApiTimeoutSec -ErrorAction Stop
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

    # Placeholder entries (Name set, RepoUrl or DownloadMethod empty) are
    # treated as wishlist items and skipped by the dispatcher. They pass
    # validation so users can keep TODO entries in their YAML files.
    $hasRepoUrl = Test-RequiredParameter -Tool $Tool -Parameter "RepoUrl"
    $hasMethod  = Test-RequiredParameter -Tool $Tool -Parameter "DownloadMethod"
    if (Test-PlaceholderEntry -Tool $Tool) {
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

# Placeholder entries (Name set, RepoUrl or DownloadMethod empty) are wishlist items:
# nothing can be downloaded without both, so they pass validation, show as [PLACEHOLDER]
# in -list and are skipped by the dispatcher instead of failing the whole file (the shipped
# group files keep reference entries for tools that have no automated download, such as
# Wireshark or IDA Free). Defined here, before main-flow-A, because validation and -list use it.
function Test-PlaceholderEntry {
    param ([Parameter(Mandatory=$true)]$Tool)
    return (-not (Test-RequiredParameter -Tool $Tool -Parameter "RepoUrl")) -or (-not (Test-RequiredParameter -Tool $Tool -Parameter "DownloadMethod"))
}

# -Tag filter: an entry matches when any of its Category values (scalar or list) is in the set.
function Test-ToolHasTag {
    param (
        [Parameter(Mandatory=$true)]$Tool,
        [Parameter(Mandatory=$true)]$TagSet
    )
    if (-not $Tool.ContainsKey("Category") -or $null -eq $Tool.Category) { return $false }
    foreach ($category in @($Tool.Category)) {
        if (-not [string]::IsNullOrWhiteSpace("$category") -and $TagSet.Contains([string]$category)) { return $true }
    }
    return $false
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

# -----------------------------------------------
# Function: Add Configuration Defaults
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
        # One GET instead of HEAD + GET: the availability check is the download itself.
        try {
            Write-LogInfo "Fetching tools configuration from URL: $Path"
            return (Invoke-WebRequest -Uri $Path -UseBasicParsing -TimeoutSec $script:ApiTimeoutSec -ErrorAction Stop).Content
        }
        catch {
            Write-LogWarning "URL '$Path' is not available: $($_.Exception.Message)"
            $choice = Read-Host "Use the default URL ($DefaultUrl) instead? (Y/N)"
            if ($choice -notmatch '^(?i:Y(es)?)$') { return $null }
        }
        try {
            return (Invoke-WebRequest -Uri $DefaultUrl -UseBasicParsing -TimeoutSec $script:ApiTimeoutSec -ErrorAction Stop).Content
        }
        catch {
            Write-LogError "Failed to fetch YAML from URL: $DefaultUrl. Exception: $_"
            return $null
        }
    }

    $resolved = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $script:BaseDir $Path }
    if (-not (Test-Path -Path $resolved)) {
        Write-LogWarning "Local tools file '$Path' not found at '$resolved'."
        $choice = Read-Host "Use the default URL ($DefaultUrl) instead? (Y/N)"
        if ($choice -notmatch '^(?i:Y(es)?)$') { return $null }
        try {
            return (Invoke-WebRequest -Uri $DefaultUrl -UseBasicParsing -TimeoutSec $script:ApiTimeoutSec).Content
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
# Import first; Get-Module -ListAvailable walks every module path and is only needed when the
# import fails (module not installed).
$yamlImported = $false
try { Import-Module -Name powershell-yaml -ErrorAction Stop; $yamlImported = $true } catch { $yamlImported = $false }
if (-not $yamlImported) {
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
if (-not $yamlImported) { Import-Module -Name powershell-yaml -ErrorAction Stop }

$mergedTools     = New-Object System.Collections.Generic.List[object]
$mergedToolDir   = ""
$primarySource   = $null

# -ToolsFile accepts an array and, as the help promises, comma-separated lists inside one value.
$toolsFileList = @()
foreach ($item in $ToolsFile) {
    foreach ($part in $item.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        if (-not [string]::IsNullOrWhiteSpace($part)) { $toolsFileList += $part.Trim() }
    }
}

foreach ($tfPath in $toolsFileList) {
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

    # A file-level 'category:' applies to every entry in that file without a Category of its
    # own, so -Tag works with the shipped tool_groups files without per-entry edits.
    $fileCategory = ''
    if ($cfg.ContainsKey('category') -and -not [string]::IsNullOrWhiteSpace("$($cfg.category)")) { $fileCategory = [string]$cfg.category }
    foreach ($entry in @($cfg.tools)) {
        if ($fileCategory -and -not ($entry.ContainsKey('Category') -and -not [string]::IsNullOrWhiteSpace("$($entry.Category)"))) {
            $entry.Category = $fileCategory
        }
    }
    $mergedTools.AddRange([object[]]@($cfg.tools))

    if ([string]::IsNullOrWhiteSpace($mergedToolDir) -and $cfg.ContainsKey("tooldirectory") -and -not [string]::IsNullOrWhiteSpace($cfg.tooldirectory)) {
        $mergedToolDir = $cfg.tooldirectory
        $primarySource = $tfPath
    }
    elseif ($cfg.ContainsKey("tooldirectory") -and -not [string]::IsNullOrWhiteSpace($cfg.tooldirectory) -and $cfg.tooldirectory -ne $mergedToolDir) {
        Write-LogWarning "tooldirectory in '$tfPath' ('$($cfg.tooldirectory)') differs from '$primarySource' ('$mergedToolDir'); using the first."
    }
}

$config = @{ tooldirectory = $mergedToolDir; tools = @($mergedTools.ToArray()) }

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
    $config.tools = @($config.tools | Where-Object { Test-ToolHasTag -Tool $_ -TagSet $tagSet })
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

# Resolution order: -ToolsDirectory > YAML tooldirectory > $PSScriptRoot.
# Folder creation is deferred to Initialize-OutputFolder so -list and
# -DryRun produce zero on-disk side effects.
if ($PSBoundParameters.ContainsKey('ToolsDirectory') -and -not [string]::IsNullOrWhiteSpace($ToolsDirectory)) {
    # Explicit -ToolsDirectory wins.
}
elseif (-not [string]::IsNullOrWhiteSpace($config.tooldirectory)) {
    $ToolsDirectory = $config.tooldirectory
}
else {
    $ToolsDirectory = $script:BaseDir
    Write-LogWarning "No tools directory configured; tools will be downloaded next to the script: $ToolsDirectory"
    Write-LogInfo "  (set 'tooldirectory:' in your YAML or use -ToolsDirectory to change this.)"
}
# A relative path is resolved against PowerShell's current location; the .NET process
# directory used by [System.IO] calls can differ from it.
if (-not [System.IO.Path]::IsPathRooted($ToolsDirectory)) {
    $ToolsDirectory = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $ToolsDirectory))
}
$tools = $config.tools

if ($Log) {
    $logDir = $ToolsDirectory
    if ($DryRun -and -not (Test-Path -LiteralPath $ToolsDirectory)) {
        # A dry run must not create the tools directory; log to the temp folder instead.
        $logDir = [System.IO.Path]::GetTempPath()
        Write-LogInfo "[DRY-RUN] Tools directory does not exist; writing the log to $logDir"
    }
    $logFilePath = Join-Path -Path $logDir -ChildPath "ToolFetcher_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Enable-FileLogging -LogPath $logFilePath
}

# -----------------------------------------------
# Determine update mode based on the parameters.
# -----------------------------------------------
$updateMode = $null
$updateToolList = @()   # always defined: the parallel block reads it via $using:
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Headers', Justification = 'Used inside the retry script block')]
    param (
        [Parameter(Mandatory=$true)][string]$ZipUrl,
        [Parameter(Mandatory=$true)][string]$ToolName,
        [Parameter(Mandatory=$true)][string]$Version,
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = $script:UserAgent },
        [Parameter(Mandatory=$false)][string]$ExpectedSha256 = "",
        [Parameter(Mandatory=$false)][string]$SaveAs = ""
    )

    Write-LogTrace "Starting ZIP staging process for $ToolName (version $Version) from $ZipUrl"
    # Per-tool subfolder so parallel downloads with the same URL filename don't collide.
    $safeName = ($ToolName -replace '[^A-Za-z0-9_.-]', '_')
    $stagingFolder = Join-Path $script:StagingRoot $safeName
    if (-not (Test-Path $stagingFolder)) {
        Write-LogDebug "Creating staging folder: $stagingFolder"
        New-Item -Path $stagingFolder -ItemType Directory -Force | Out-Null
    }

    # Use the original filename from the URL unless the caller names the file (-SaveAs, from
    # DownloadName). A name without an extension (".../latest/download") gets ".zip" so the
    # extraction folder below never collides with the archive itself.
    $fileName = Split-Path $ZipUrl -Leaf
    if (-not [string]::IsNullOrWhiteSpace($SaveAs)) { $fileName = $SaveAs }
    if ([string]::IsNullOrEmpty([System.IO.Path]::GetExtension($fileName))) { $fileName = "$fileName.zip" }
    $tempZip = Join-Path $stagingFolder $fileName
    Write-LogDebug "Temporary ZIP file: $tempZip"

    # For extraction, create a folder using the original base name.
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $tempExtract = Join-Path $stagingFolder $baseName
    Write-LogDebug "Temporary extraction folder: $tempExtract"

    # Function-scoped: hides the progress bar that makes Invoke-WebRequest -OutFile dramatically
    # slower on Windows PowerShell 5.1. Reverts automatically when this function returns.
    $ProgressPreference = 'SilentlyContinue'
    $iwrExtra = $script:DownloadExtraArgs

    try {
        Write-LogInfo "Downloading $ToolName from $ZipUrl"
        Invoke-WithRetry -Description "ZIP download for $ToolName" -ScriptBlock {
            Invoke-WebRequest -Uri $ZipUrl -OutFile $tempZip -Headers $Headers -UseBasicParsing `
                -TimeoutSec $script:DownloadTimeoutSec @iwrExtra -ErrorAction Stop
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
        $extractedItemCount = Expand-ZipSafely -ZipPath $tempZip -DestinationPath $tempExtract
        Write-LogDebug "Extracted ZIP to temporary folder: $tempExtract (Files: $extractedItemCount)"
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
    $root = $Folder.TrimEnd('\', '/')
    $files = Get-ChildItem -Recurse -File -LiteralPath $root
    foreach ($file in $files) {
        if ($file.Name -eq ".downloaded.json") { continue }
        $relativePath = $file.FullName.Substring($root.Length + 1)
        try {
            $hash = Get-FileHashHex -Path $file.FullName -Algorithm SHA256
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
        $actual = Get-FileHashHex -Path $FilePath -Algorithm SHA256
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
# Hashing helpers
# -----------------------------------------------
# .NET hashing: no per-file cmdlet overhead and no dependence on module autoloading
# (Get-FileHash is a script function in Windows PowerShell's Utility module). Output is
# uppercase hex, identical to Get-FileHash.
function Get-FileHashHex {
    param (
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$false)][ValidateSet('SHA256', 'MD5')][string]$Algorithm = 'SHA256'
    )
    $hasher = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    $stream = $null
    try {
        $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite, 1MB)
        return ([System.BitConverter]::ToString($hasher.ComputeHash($stream)) -replace '-', '')
    }
    finally {
        if ($stream) { $stream.Dispose() }
        $hasher.Dispose()
    }
}

# Manifests written by v2.x hold 32-hex MD5 digests; newer ones hold 64-hex SHA256. The
# algorithm is detected per entry so older installs keep updating cleanly; the marker's
# HashAlgorithm field only breaks ties for unrecognised lengths.
function Get-ManifestEntryAlgorithm {
    param ([string]$Digest, [string]$Declared = '')
    if ($Digest.Length -eq 32) { return 'MD5' }
    if ($Digest.Length -eq 64) { return 'SHA256' }
    if ($Declared -eq 'MD5' -or $Declared -eq 'SHA256') { return $Declared }
    return 'SHA256'
}

# Normalises a marker's Manifest (PSCustomObject from ConvertFrom-Json, or a hashtable) into a
# case-insensitive relative-path -> digest dictionary (Windows paths are case-insensitive).
function ConvertTo-ManifestTable {
    param ([Parameter(Mandatory=$false)]$Manifest)
    $table = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $Manifest) { return $table }
    if ($Manifest -is [System.Collections.IDictionary]) {
        foreach ($key in $Manifest.Keys) {
            if ($null -ne $Manifest[$key]) { $table[[string]$key] = [string]$Manifest[$key] }
        }
    }
    else {
        foreach ($property in $Manifest.PSObject.Properties) {
            if ($null -ne $property.Value) { $table[$property.Name] = [string]$property.Value }
        }
    }
    return $table
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
        [Parameter()]$Manifest = $null,
        [Parameter()][string]$HashAlgorithm = "SHA256",
        [Parameter()][string]$Branch = "",
        [Parameter()][string]$ApiETag = "",
        [Parameter()][string]$RemoteETag = "",
        [Parameter()][string]$RemoteLastModified = "",
        [Parameter()][string]$RemoteLength = ""
    )
    $markerFile = Join-Path $OutputFolder ".downloaded.json"
    $metadata = [ordered]@{
        Tool               = $ToolName
        Timestamp          = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
        DownloadMethod     = $DownloadMethod
        DownloadURL        = $DownloadURL
        Version            = $Version
        CommitHash         = $CommitHash
        Branch             = $Branch
        DownloadedFile     = $DownloadedFile
        ExtractionLocation = $ExtractionLocation
        HashAlgorithm      = $HashAlgorithm
        ApiETag            = $ApiETag
        RemoteETag         = $RemoteETag
        RemoteLastModified = $RemoteLastModified
        RemoteLength       = $RemoteLength
        Manifest           = $Manifest
    }
    # UTF-8 with BOM: identical bytes on both PowerShell editions (Out-File defaults to UTF-16
    # on 5.1) and still readable by v2.x, which reads BOM-less files as the ANSI code page.
    $json = $metadata | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($markerFile, $json, [System.Text.UTF8Encoding]::new($true))
    Write-LogDebug "Marker file created at $markerFile"
}

# -----------------------------------------------
# Function: Remove Managed Files
# -----------------------------------------------
function Remove-ManagedFiles {
    param (
        [Parameter(Mandatory=$true)][string]$OutputFolder,
        [Parameter(Mandatory=$false)]$Marker = $null
    )
    $markerFile = Join-Path $OutputFolder ".downloaded.json"
    Write-LogDebug "Checking for marker file at: $markerFile"

    if ($null -eq $Marker) { $Marker = Get-ToolMarker -OutputFolder $OutputFolder }
    if ($null -eq $Marker) {
        Write-LogDebug "No marker file found in $OutputFolder. No managed files to remove."
        return
    }
    Write-LogDebug "Marker file loaded successfully"

    try {
        # Keyed by relative path (case-insensitive). Files that are not in the manifest are
        # user-added and are never hashed or touched. Each entry's digest length selects the
        # algorithm, so installs made by v2.x (MD5) update cleanly.
        $manifest = ConvertTo-ManifestTable -Manifest $Marker.Manifest
        $declared = if ($Marker.PSObject.Properties['HashAlgorithm']) { [string]$Marker.HashAlgorithm } else { '' }

        if ($manifest.Count -eq 0) {
            Write-LogWarning "No manifest found in marker file"
        }
        else {
            Write-LogDebug "Manifest has $($manifest.Count) entries (declared algorithm: '$declared')"
            $root = $OutputFolder.TrimEnd('\', '/')
            $removed = 0; $backedUp = 0; $untouched = 0; $saveCount = 0

            # One directory scan; .save# files are counted in the same pass.
            foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
                if ($file.Name -eq '.downloaded.json') { continue }
                if ($file.Name -match '\.save\d+$') { $saveCount++; continue }

                $relativePath = $file.FullName.Substring($root.Length + 1)
                $expected = $null
                if (-not $manifest.TryGetValue($relativePath, [ref]$expected)) {
                    $untouched++
                    continue
                }

                try {
                    $algorithm = Get-ManifestEntryAlgorithm -Digest $expected -Declared $declared
                    $currentHash = Get-FileHashHex -Path $file.FullName -Algorithm $algorithm
                    if ($currentHash -ieq $expected) {
                        # Managed file with unchanged content: remove it.
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                        if (Test-Path -LiteralPath $file.FullName) {
                            Write-LogWarning "Failed to remove file: $($file.FullName)"
                        }
                        else { $removed++ }
                    }
                    else {
                        # Managed file with changed content: keep it as the next free .save#.
                        $backupNumber = 1
                        $backupPath = "$($file.FullName).save$backupNumber"
                        while (Test-Path -LiteralPath $backupPath) {
                            $backupNumber++
                            $backupPath = "$($file.FullName).save$backupNumber"
                        }
                        $newName = Split-Path $backupPath -Leaf
                        Write-LogInfo "Backing up modified file: $relativePath > $newName"
                        Rename-Item -LiteralPath $file.FullName -NewName $newName -Force
                        if (Test-Path -LiteralPath $backupPath) { $backedUp++ }
                        else { Write-LogWarning "Failed to back up file: $($file.FullName)" }
                    }
                }
                catch {
                    Write-LogWarning "Could not process file: $($file.FullName). Error: $_"
                }
            }
            Write-LogDebug "Managed-file cleanup in ${root}: removed $removed, backed up $backedUp, user files kept $untouched, existing .save# files $saveCount"
        }
    }
    catch {
        Write-LogWarning "Failed to remove managed files in $OutputFolder. Exception: $_"
    }

    # Always remove the marker (the caller writes a fresh one after the new download lands).
    Write-LogDebug "Removing marker file: $markerFile"
    Remove-Item -LiteralPath $markerFile -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $markerFile) {
        Write-LogWarning "Failed to remove marker file: $markerFile"
    }
    else {
        Write-LogDebug "Successfully removed marker file: $markerFile"
    }
}

# Helper function to download a file to a temporary location
function Save-FileToTemp {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Headers', Justification = 'Used inside the retry script block')]
    param (
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutputPath,
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = $script:UserAgent },
        [Parameter(Mandatory=$false)][string]$ToolName = ""
    )

    # Function-scoped progress suppression (see Invoke-ZipStaging).
    $ProgressPreference = 'SilentlyContinue'
    $iwrExtra = $script:DownloadExtraArgs

    try {
        $label = if ([string]::IsNullOrWhiteSpace($ToolName)) { "file" } else { $ToolName }
        Write-LogInfo "Downloading $label from $Url"
        Invoke-WithRetry -Description "file download for $label" -ScriptBlock {
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -Headers $Headers -UseBasicParsing `
                -TimeoutSec $script:DownloadTimeoutSec @iwrExtra -ErrorAction Stop
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
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = $script:UserAgent },
        [Parameter(Mandatory=$false)][hashtable]$Remote = $null,
        [Parameter(Mandatory=$false)][string]$SaveAs = ""
    )

    # Per-tool subfolder so parallel downloads with the same URL filename don't collide.
    $safeName = ($ToolConfig.Name -replace '[^A-Za-z0-9_.-]', '_')
    $stagingFolder = Join-Path $script:StagingRoot $safeName
    if (-not (Test-Path $stagingFolder)) { New-Item -Path $stagingFolder -ItemType Directory -Force | Out-Null }

    # -SaveAs names the file when the URL does not (e.g. ".../latest/win32-x64-user/stable").
    $fileName = Split-Path $FileUrl -Leaf
    if (-not [string]::IsNullOrWhiteSpace($SaveAs)) { $fileName = $SaveAs }
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

            $hash = Get-FileHashHex -Path $tempFile -Algorithm SHA256
            $newManifest = @{ $fileName = $hash }

            # Only now, with the new file downloaded and verified, is the previous install
            # cleaned, so a failed download never leaves a half-empty tool.
            if (Test-Path (Join-Path $OutputFolder ".downloaded.json")) {
                Remove-ManagedFiles -OutputFolder $OutputFolder
            }

            $destinationPath = Join-Path $OutputFolder -ChildPath $fileName
            Move-Item -LiteralPath $tempFile -Destination $destinationPath -Force
            Write-LogDebug "Moved file from temp to output folder: $destinationPath"

            $markerArgs = Get-MarkerRemoteArgs -Remote $Remote
            Write-MarkerFile -OutputFolder $OutputFolder `
                            -ToolName $ToolConfig.Name `
                            -DownloadMethod $ToolConfig.DownloadMethod `
                            -DownloadURL $FileUrl `
                            -Version $Version `
                            -CommitHash $CommitHash `
                            -DownloadedFile $destinationPath `
                            -ExtractionLocation $OutputFolder `
                            -Manifest $newManifest `
                            @markerArgs

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
# Moves staged content into the output folder instead of copying it and deleting the copy.
# On the same volume every top-level item is a rename; across volumes (Move-Item cannot move
# a directory between drives) it falls back to copy-and-delete. Existing destination folders
# are merged into, which is what the user-file-preserving cleanup relies on.
function Move-StagedContent {
    param (
        [Parameter(Mandatory=$true)][string]$SourceFolder,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    $null = [System.IO.Directory]::CreateDirectory($Destination)
    foreach ($item in Get-ChildItem -LiteralPath $SourceFolder -Force) {
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            if (Test-Path -LiteralPath $target) {
                Move-StagedContent -SourceFolder $item.FullName -Destination $target
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            else {
                try {
                    Move-Item -LiteralPath $item.FullName -Destination $target -Force -ErrorAction Stop
                }
                catch {
                    Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
                    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        else {
            Move-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}

function Expand-StagedZip {
    param (
        [Parameter(Mandatory=$true)]$Staging,
        [Parameter(Mandatory=$true)][string]$OutputFolder,
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$DownloadUrl,
        [Parameter(Mandatory=$false)][string]$Version = "",
        [Parameter(Mandatory=$false)][hashtable]$Remote = $null
    )

    $tempExtract = $Staging.TempExtract

    # A single top-level folder (the GitHub repo-branch wrapper) is flattened away.
    $extractedItems = @(Get-ChildItem -Path $tempExtract)
    if ($extractedItems.Count -eq 1 -and $extractedItems[0].PSIsContainer) {
        $singleFolder = $extractedItems[0].FullName
        Write-LogDebug "Detected single folder in extraction: $($extractedItems[0].Name)"
        $newManifest = Get-FileManifest -Folder $singleFolder
        $sourceRoot = $singleFolder
        $copiedMessage = "Moved contents of single folder directly to output folder: $OutputFolder"
    }
    else {
        $newManifest = Get-FileManifest -Folder $tempExtract
        $sourceRoot = $tempExtract
        $copiedMessage = "Moved extracted files to output folder: $OutputFolder"
    }

    # Only now, with the new content downloaded and extracted, is the previous install
    # cleaned, so a failed download never leaves a half-empty tool.
    if (Test-Path (Join-Path $OutputFolder ".downloaded.json")) {
        Remove-ManagedFiles -OutputFolder $OutputFolder
    }

    Move-StagedContent -SourceFolder $sourceRoot -Destination $OutputFolder
    Write-LogDebug $copiedMessage

    $markerArgs = Get-MarkerRemoteArgs -Remote $Remote
    Write-MarkerFile -OutputFolder $OutputFolder `
                     -ToolName $ToolConfig.Name `
                     -DownloadMethod $ToolConfig.DownloadMethod `
                     -DownloadURL $DownloadUrl `
                     -Version $Version `
                     -CommitHash "" `
                     -DownloadedFile "" `
                     -ExtractionLocation $OutputFolder `
                     -Manifest $newManifest `
                     @markerArgs

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

    # Lazily create the tools directory on first use (drive-existence sanity check).
    if (-not [System.IO.Directory]::Exists($ToolsDirectory)) {
        $drive = [System.IO.Path]::GetPathRoot($ToolsDirectory)
        if (-not [System.IO.Directory]::Exists($drive)) {
            Write-LogError "Drive '$drive' does not exist. Cannot create tools directory '$ToolsDirectory'."
            return $null
        }
        try {
            New-Item -Path $ToolsDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-LogInfo "Created tools directory: $ToolsDirectory"
        } catch {
            Write-LogError "Failed to create tools directory at '$ToolsDirectory'. Exception: $_"
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
# -----------------------------------------------
# HTTP helpers (both editions)
# -----------------------------------------------
# Reads one header from the shapes seen across editions: WebHeaderCollection (5.1 exception
# responses, case-insensitive indexer), the dictionaries Invoke-WebRequest exposes as .Headers
# on success, and HttpResponseHeaders (PowerShell 7 exception responses, TryGetValues).
function Get-ResponseHeader {
    param (
        [Parameter(Mandatory=$false)]$Headers,
        [Parameter(Mandatory=$true)][string]$Name
    )
    if ($null -eq $Headers) { return $null }
    if ($Headers -is [System.Collections.Specialized.NameValueCollection]) { return $Headers[$Name] }
    if ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in $Headers.Keys) {
            if ([string]$key -ieq $Name) { return ([string[]]@($Headers[$key]))[0] }
        }
        return $null
    }
    try {
        $values = $null
        if ($Headers.TryGetValues($Name, [ref]$values)) { return ([string[]]@($values))[0] }
    }
    catch { $null = $_ }
    return $null
}

# Diagnoses an HTTP failure: status code, Retry-After, GitHub rate-limit headers, and whether
# it is a rate limit (403/429 with X-RateLimit-Remaining 0, or any 429).
# Diagnoses an HTTP failure: status code, Retry-After, GitHub rate-limit headers, and whether
# it is a rate limit (403/429 with X-RateLimit-Remaining 0, or any 429). Handles the error
# shapes of Invoke-WebRequest on both editions and of a WebException thrown by a .NET call
# (wrapped in a MethodInvocationException).
function Get-HttpErrorInfo {
    param ([Parameter(Mandatory=$true)]$ErrorRecord)
    $info = @{ StatusCode = $null; RetryAfter = $null; RateLimitRemaining = $null; RateLimitReset = $null; RateLimited = $false; ResetTime = $null }
    $exception = $ErrorRecord.Exception
    $response = $null
    try { $response = $exception.Response } catch { $null = $_ }
    if ($null -eq $response -and $null -ne $exception.InnerException) {
        $exception = $exception.InnerException
        try { $response = $exception.Response } catch { $null = $_ }
    }
    if ($null -eq $response) { return $info }
    try { $info.StatusCode = [int]$response.StatusCode } catch { $null = $_ }
    $headers = $null
    try { $headers = $response.Headers } catch { $null = $_ }
    $retryAfter = [string](Get-ResponseHeader -Headers $headers -Name 'Retry-After')
    $remaining  = [string](Get-ResponseHeader -Headers $headers -Name 'X-RateLimit-Remaining')
    $reset      = [string](Get-ResponseHeader -Headers $headers -Name 'X-RateLimit-Reset')
    if ($retryAfter -match '^\d+$') { $info.RetryAfter = [int]$retryAfter }
    if ($remaining -match '^\d+$')  { $info.RateLimitRemaining = [int]$remaining }
    if ($reset -match '^\d+$')      { $info.RateLimitReset = [long]$reset }
    if (($info.StatusCode -eq 403 -or $info.StatusCode -eq 429) -and $info.RateLimitRemaining -eq 0 -and $null -ne $info.RateLimitReset) {
        $info.RateLimited = $true
        $info.ResetTime = [DateTimeOffset]::FromUnixTimeSeconds($info.RateLimitReset).LocalDateTime
    }
    elseif ($info.StatusCode -eq 429) {
        $info.RateLimited = $true
        $waitSeconds = 60
        if ($null -ne $info.RetryAfter) { $waitSeconds = $info.RetryAfter }
        $info.ResetTime = (Get-Date).AddSeconds($waitSeconds)
    }
    return $info
}

# GET against the GitHub API with retry, an optional conditional request (If-None-Match) and
# rate-limit diagnosis. Returns @{ Ok; StatusCode; Data; ETag; NotModified; RateLimited; Error }.
# A 304 is reported as Ok + NotModified and costs no rate-limit quota. Once a limit is hit,
# later calls return immediately until the reset time.
# GET against the GitHub API with retry, an optional conditional request (If-None-Match),
# manual redirect handling and rate-limit diagnosis.
# Returns @{ Ok; StatusCode; Data; ETag; NotModified; RateLimited; Error; FinalUri; Moved }.
# Redirects (a renamed or transferred repository answers 301) are followed here rather than by
# Invoke-WebRequest, because both PowerShell editions drop the Authorization header when they
# follow one: the redirected request would count against the anonymous 60/hour bucket.
# A 304 is reported as Ok + NotModified and costs no quota. Once a limit is hit, later calls
# return immediately until the reset time.
# GET against the GitHub API with retry, an optional conditional request (If-None-Match),
# manual redirect handling and rate-limit diagnosis.
# Returns @{ Ok; StatusCode; Data; ETag; NotModified; RateLimited; Error; FinalUri; Moved }.
# Uses HttpWebRequest with AllowAutoRedirect off on both editions: a renamed or transferred
# repository answers 301, and Invoke-WebRequest would follow it without the Authorization
# header, so the redirected request would count against the anonymous 60/hour bucket (and
# -MaximumRedirection 0 is broken on Windows PowerShell 5.1). A 304 costs no quota. Once a
# limit is hit, later calls return immediately until the reset time.
function Invoke-GitHubApi {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Headers', Justification = 'Used inside the retry script block')]
    param (
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = $script:UserAgent },
        [Parameter(Mandatory=$false)][string]$Description = "GitHub API request",
        [Parameter(Mandatory=$false)][string]$IfNoneMatch = ""
    )
    $result = @{ Ok = $false; StatusCode = $null; Data = $null; ETag = ''; NotModified = $false; RateLimited = $false; Error = ''; FinalUri = $Uri; Moved = $false }
    if ($null -ne $script:RateLimitedUntil -and (Get-Date) -lt $script:RateLimitedUntil) {
        $result.RateLimited = $true
        $result.Error = "GitHub API rate limit exceeded (resets at $($script:RateLimitedUntil.ToString('HH:mm:ss')))"
        return $result
    }
    $conditional = ''
    if (-not [string]::IsNullOrEmpty($IfNoneMatch)) { $conditional = ' (conditional)' }

    $currentUri = $Uri
    for ($hop = 0; $hop -le 5; $hop++) {
        Write-LogDebug "GitHub API: $currentUri$conditional"
        $response = $null
        try {
            $response = Invoke-WithRetry -Description $Description -ScriptBlock {
                $request = [System.Net.HttpWebRequest]::Create($currentUri)
                $request.Method = 'GET'
                $request.AllowAutoRedirect = $false
                $request.Timeout = $script:ApiTimeoutSec * 1000
                $request.UserAgent = $script:UserAgent
                foreach ($key in $Headers.Keys) {
                    if ($key -ine 'User-Agent') { $request.Headers[[string]$key] = [string]$Headers[$key] }
                }
                if (-not [string]::IsNullOrEmpty($IfNoneMatch)) { $request.Headers['If-None-Match'] = $IfNoneMatch }
                $request.GetResponse()
            }
            $status = [int]$response.StatusCode
            $result.StatusCode = $status
            $remaining = [string]$response.Headers['X-RateLimit-Remaining']
            if ($remaining -match '^\d+$') { $script:RateLimitRemaining = [int]$remaining }

            if ($status -eq 301 -or $status -eq 302 -or $status -eq 307 -or $status -eq 308) {
                $location = [string]$response.Headers['Location']
                if ([string]::IsNullOrEmpty($location) -or $hop -ge 5) {
                    $result.Error = "Redirect ($status) without a usable Location from $currentUri"
                    return $result
                }
                if ($location -notmatch '^https?://') { $location = ([System.Uri]::new([System.Uri]$currentUri, $location)).AbsoluteUri }
                Write-LogWarning "$Description was redirected ($status) to $location. The repository has probably moved: update RepoUrl in your YAML to keep the lookup direct."
                $result.Moved = $true
                $currentUri = $location
                continue
            }
            if ($status -eq 304) {
                $result.Ok = $true
                $result.NotModified = $true
                $result.ETag = $IfNoneMatch
                $result.FinalUri = $currentUri
                return $result
            }

            $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
            try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $result.Ok = $true
            $result.Data = $body | ConvertFrom-Json
            $result.ETag = [string]$response.Headers['ETag']
            $result.FinalUri = $currentUri
            return $result
        }
        catch {
            $info = Get-HttpErrorInfo -ErrorRecord $_
            $result.StatusCode = $info.StatusCode
            if ($info.RateLimited) {
                $script:RateLimitedUntil = $info.ResetTime
                $hint = ''
                if ([string]::IsNullOrEmpty($script:GitHubPAT)) { $hint = ' Use -PromptForPAT to raise the limit from 60 to 5,000 requests per hour.' }
                $result.RateLimited = $true
                $result.Error = "GitHub API rate limit exceeded (resets at $($info.ResetTime.ToString('HH:mm:ss'))). Remaining API-dependent tools will be skipped.$hint"
                Write-LogError $result.Error
                return $result
            }
            $message = $_.Exception.Message
            if ($null -ne $_.Exception.InnerException -and $_.Exception -is [System.Management.Automation.MethodInvocationException]) { $message = $_.Exception.InnerException.Message }
            $result.Error = "$message"
            return $result
        }
        finally {
            if ($null -ne $response) { try { $response.Close() } catch { $null = $_ } }
        }
    }
    $result.Error = "Too many redirects for $Uri"
    return $result
}

# HEAD probe for ETag / Last-Modified / Content-Length (no GitHub API quota). Never fatal.
function Get-RemoteFileInfo {
    param (
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = $script:UserAgent }
    )
    $info = @{ ETag = ''; LastModified = ''; Length = '' }
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -Headers $Headers -UseBasicParsing -TimeoutSec $script:ApiTimeoutSec -ErrorAction Stop
        $info.ETag         = [string](Get-ResponseHeader -Headers $response.Headers -Name 'ETag')
        $info.LastModified = [string](Get-ResponseHeader -Headers $response.Headers -Name 'Last-Modified')
        $info.Length       = [string](Get-ResponseHeader -Headers $response.Headers -Name 'Content-Length')
        Write-LogDebug "HEAD $Url -> ETag='$($info.ETag)' Last-Modified='$($info.LastModified)' Length='$($info.Length)'"
    }
    catch {
        Write-LogDebug "HEAD request for $Url failed (no up-to-date signal): $($_.Exception.Message)"
    }
    return $info
}

# Default branch: GitHub API first, then a quota-free codeload probe of main and master.
function Resolve-DefaultBranch {
    param (
        [Parameter(Mandatory=$true)][string]$Owner,
        [Parameter(Mandatory=$true)][string]$Repo,
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = $script:UserAgent }
    )
    $api = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Owner/$Repo" -Headers $Headers -Description "default branch lookup for $Owner/$Repo"
    if ($api.Ok -and $null -ne $api.Data -and -not [string]::IsNullOrEmpty($api.Data.default_branch)) {
        Write-LogDebug "Default branch for $Owner/${Repo}: $($api.Data.default_branch)"
        return [string]$api.Data.default_branch
    }
    Write-LogWarning "Failed to query default branch for $Owner/${Repo}: $($api.Error). Probing main/master directly."
    foreach ($candidate in @('main', 'master')) {
        try {
            $null = Invoke-WebRequest -Uri "https://codeload.github.com/$Owner/$Repo/zip/refs/heads/$candidate" -Method Head -Headers $Headers -UseBasicParsing -TimeoutSec $script:ApiTimeoutSec -ErrorAction Stop
            Write-LogDebug "Default branch for $Owner/${Repo}: $candidate (codeload probe)"
            return $candidate
        }
        catch { $null = $_ }
    }
    return $null
}

# Removes leftover staging files after a failed download (paths that do not exist are ignored).
function Remove-StagingLeftover {
    param ([Parameter(Mandatory=$false)]$Paths)
    foreach ($tempFile in @($Paths)) {
        if ($tempFile -and (Test-Path -LiteralPath $tempFile)) {
            Remove-Item -LiteralPath $tempFile -Force -Recurse -ErrorAction SilentlyContinue
            Write-LogDebug "Cleaned up temporary file/folder: $tempFile"
        }
    }
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
    Run a script block with exponential backoff on transient failures (5xx, network errors).
    3xx/4xx responses are not retried (bad URL, missing asset, auth failure, not-modified and
    rate limits, which callers diagnose), except 429 with a short Retry-After, which is honoured.
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
            $isLast = ($attempt -eq $MaxAttempts)
            $info = Get-HttpErrorInfo -ErrorRecord $_
            $delay = $DelaysSeconds[[Math]::Min($attempt - 1, $DelaysSeconds.Length - 1)]

            if ($null -ne $info.StatusCode) {
                if ($info.StatusCode -eq 429 -and $null -ne $info.RetryAfter -and $info.RetryAfter -le 60) {
                    $delay = [int]$info.RetryAfter
                }
                elseif ($info.StatusCode -ge 300 -and $info.StatusCode -lt 500) {
                    throw
                }
            }
            if ($isLast) { throw }

            Write-LogWarning "$Description failed (attempt $attempt/$MaxAttempts): $($_.Exception.Message). Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
}

function Expand-ZipSafely {
    <#
    .SYNOPSIS
    Extract a ZIP archive while validating that each entry resolves under the destination,
    defending against Zip-Slip (entries with '..' or absolute paths that escape the target
    folder). Uses .NET directly, with no per-entry cmdlet calls. Returns the number of files
    written.
    #>
    param (
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [Parameter(Mandatory=$true)][string]$DestinationPath
    )

    $null = [System.IO.Directory]::CreateDirectory($DestinationPath)
    $destFull = [System.IO.Path]::GetFullPath($DestinationPath).TrimEnd([char]'\', [char]'/') + [System.IO.Path]::DirectorySeparatorChar
    $written = 0

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $zip.Entries) {
            # Combine returns a rooted entry name verbatim and GetFullPath resolves '..', so the
            # prefix check below catches both escape techniques.
            $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($DestinationPath, $entry.FullName))
            if (-not $target.StartsWith($destFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Zip-Slip detected: entry '$($entry.FullName)' would extract to '$target', outside '$destFull'"
            }

            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                $null = [System.IO.Directory]::CreateDirectory($target)
                continue
            }

            $parent = [System.IO.Path]::GetDirectoryName($target)
            if ($parent) { $null = [System.IO.Directory]::CreateDirectory($parent) }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            $written++
        }
    }
    finally {
        $zip.Dispose()
    }
    return $written
}

# -----------------------------------------------
# Remote resolution and up-to-date checks
# -----------------------------------------------
# Writes newly learned upstream identifiers (ETags, branch) into an existing marker without a
# download, so an up-to-date tool whose marker predates them gets free conditional checks.
function Update-MarkerRemoteState {
    param (
        [Parameter(Mandatory=$true)][string]$OutputFolder,
        [Parameter(Mandatory=$false)]$Marker,
        [Parameter(Mandatory=$false)][hashtable]$Remote
    )
    if ($null -eq $Marker -or $null -eq $Remote -or $Remote.NotModified) { return }
    $changed = $false
    foreach ($key in @('ApiETag', 'RemoteETag', 'RemoteLastModified', 'RemoteLength', 'Branch')) {
        $value = ''
        if ($Remote.ContainsKey($key) -and $null -ne $Remote[$key]) { $value = [string]$Remote[$key] }
        if ([string]::IsNullOrEmpty($value)) { continue }
        if ((Get-MarkerValue -Marker $Marker -Name $key) -ne $value) {
            $Marker | Add-Member -NotePropertyName $key -NotePropertyValue $value -Force
            $changed = $true
        }
    }
    if (-not $changed) { return }
    try {
        $markerFile = Join-Path $OutputFolder ".downloaded.json"
        $json = $Marker | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($markerFile, $json, [System.Text.UTF8Encoding]::new($true))
        Write-LogDebug "Marker refreshed with upstream identifiers: $markerFile"
    }
    catch {
        Write-LogDebug "Could not refresh the marker in ${OutputFolder}: $($_.Exception.Message)"
    }
}

function Get-MarkerValue {
    param ([Parameter(Mandatory=$false)]$Marker, [Parameter(Mandatory=$true)][string]$Name)
    if ($null -eq $Marker) { return '' }
    $property = $Marker.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return [string]$property.Value
}

# Splat of the marker fields that describe the upstream state of a download.
function Get-MarkerRemoteArgs {
    param ([Parameter(Mandatory=$false)][hashtable]$Remote)
    $splat = @{ Branch = ''; ApiETag = ''; RemoteETag = ''; RemoteLastModified = ''; RemoteLength = '' }
    if ($null -ne $Remote) {
        foreach ($key in @($splat.Keys)) {
            if ($Remote.ContainsKey($key) -and $null -ne $Remote[$key]) { $splat[$key] = [string]$Remote[$key] }
        }
    }
    return $splat
}

# One metadata fetch per tool: everything the dispatcher and the Save-* functions need
# (download URL, version/commit, ETags). With -Marker, GitHub API calls are conditional
# (If-None-Match on the stored ApiETag); a 304 means "unchanged upstream", costs no
# rate-limit quota, and the marker's values are echoed back in the result.
function Resolve-ToolRemote {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = $script:UserAgent },
        [Parameter(Mandatory=$false)]$Marker = $null
    )
    $name = [string]$ToolConfig.Name
    $remote = @{
        Ok = $false; Error = ''; RateLimited = $false; NotModified = $false
        Method = [string]$ToolConfig.DownloadMethod; Version = ''; CommitHash = ''; Branch = ''
        DownloadUrl = ''; Asset = $null; Owner = ''; Repo = ''
        ApiETag = ''; RemoteETag = ''; RemoteLastModified = ''; RemoteLength = ''
    }
    # A trailing slash in RepoUrl would otherwise produce '//releases/latest' and '//archive/...'.
    $repoUrl = ([string]$ToolConfig.RepoUrl).TrimEnd('/')
    $ifNoneMatch = Get-MarkerValue -Marker $Marker -Name 'ApiETag'
    if ($repoUrl -match 'github\.com/([^/]+)/([^/]+?)(?:\.git)?$') {
        $remote.Owner = $matches[1]
        $remote.Repo  = $matches[2]
    }

    switch ($remote.Method) {
        'latestRelease' {
            if ([string]::IsNullOrEmpty($remote.Owner)) {
                $remote.Error = "Failed to get release info for $name. Exception: '$repoUrl' is not a github.com repository URL"
                Write-LogError $remote.Error
                return $remote
            }
            $releaseUri = "https://api.github.com/repos/$($remote.Owner)/$($remote.Repo)/releases/latest"
            Write-LogDebug "Using API endpoint: $releaseUri for $name"
            $api = Invoke-GitHubApi -Uri $releaseUri -Headers $Headers -Description "release lookup for $name" -IfNoneMatch $ifNoneMatch
            if (-not $api.Ok) {
                $remote.RateLimited = $api.RateLimited
                $remote.Error = "Failed to get release info for $name. Exception: $($api.Error)"
                if (-not $api.RateLimited) { Write-LogError $remote.Error }
                return $remote
            }
            if ($api.NotModified) {
                $remote.NotModified = $true
                $remote.Version     = Get-MarkerValue -Marker $Marker -Name 'Version'
                $remote.DownloadUrl = Get-MarkerValue -Marker $Marker -Name 'DownloadURL'
                $remote.ApiETag     = $ifNoneMatch
                $remote.Ok = $true
                return $remote
            }
            $releaseInfo = $api.Data
            Write-LogDebug "Retrieved release info. Assets count: $($releaseInfo.assets.Count)"
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
                    Write-LogWarning "No pattern defined for AssetType '$($ToolConfig.AssetType)' for $name."
                }
            }
            $asset = $assets | Select-Object -First 1
            if ($null -eq $asset) {
                Write-LogWarning "No matching asset found for $name."
                $remote.Error = "No matching asset found for $name."
                return $remote
            }
            $remote.Version     = [string]$releaseInfo.tag_name
            $remote.Asset       = $asset
            $remote.DownloadUrl = [string]$asset.browser_download_url
            $remote.ApiETag     = $api.ETag
            $remote.Ok = $true
        }
        'gitClone' {
            if ([string]::IsNullOrEmpty($remote.Owner)) {
                $remote.Error = "Invalid GitHub URL format for ${name}: $repoUrl"
                Write-LogError $remote.Error
                return $remote
            }
            Write-LogDebug "Extracted owner: $($remote.Owner), repo: $($remote.Repo)"
            $branch = Get-DefaultValue -Tool $ToolConfig -Parameter "Branch"
            if ([string]::IsNullOrWhiteSpace($branch)) {
                $branch = Resolve-DefaultBranch -Owner $remote.Owner -Repo $remote.Repo -Headers $Headers
                if ([string]::IsNullOrWhiteSpace($branch)) {
                    Write-LogError "Could not determine default branch for $name; skipping."
                    $remote.Error = "Could not determine default branch for $name"
                    $remote.RateLimited = ($null -ne $script:RateLimitedUntil)
                    return $remote
                }
            }
            $remote.Branch = [string]$branch
            $apiUrl = "https://api.github.com/repos/$($remote.Owner)/$($remote.Repo)/branches/$branch"
            Write-LogDebug "Querying GitHub API: $apiUrl"
            $api = Invoke-GitHubApi -Uri $apiUrl -Headers $Headers -Description "branch lookup for $name" -IfNoneMatch $ifNoneMatch
            if (-not $api.Ok) {
                $remote.RateLimited = $api.RateLimited
                $remote.Error = "Failed to get branch info for $name. Exception: $($api.Error)"
                if (-not $api.RateLimited) { Write-LogError $remote.Error }
                return $remote
            }
            if ($api.NotModified) {
                $remote.NotModified = $true
                $remote.CommitHash  = Get-MarkerValue -Marker $Marker -Name 'CommitHash'
                $remote.Version     = [string]$branch
                $remote.DownloadUrl = Get-MarkerValue -Marker $Marker -Name 'DownloadURL'
                $remote.ApiETag     = $ifNoneMatch
                $remote.Ok = $true
                return $remote
            }
            $remote.CommitHash  = [string]$api.Data.commit.sha
            Write-LogDebug "Latest commit hash for ${branch}: $($remote.CommitHash)"
            $remote.Version     = [string]$branch
            $remote.DownloadUrl = "https://github.com/$($remote.Owner)/$($remote.Repo)/archive/$($remote.CommitHash).zip"
            $remote.ApiETag     = $api.ETag
            $remote.Ok = $true
        }
        'branchZip' {
            $branch = Get-DefaultValue -Tool $ToolConfig -Parameter "Branch"
            if ([string]::IsNullOrWhiteSpace($branch)) {
                if ([string]::IsNullOrEmpty($remote.Owner)) {
                    Write-LogError "Could not determine default branch for $name; skipping."
                    $remote.Error = "Could not determine default branch for $name (not a github.com URL and no Branch set)"
                    return $remote
                }
                $branch = Resolve-DefaultBranch -Owner $remote.Owner -Repo $remote.Repo -Headers $Headers
                if ([string]::IsNullOrWhiteSpace($branch)) {
                    Write-LogError "Could not determine default branch for $name; skipping."
                    $remote.Error = "Could not determine default branch for $name"
                    $remote.RateLimited = ($null -ne $script:RateLimitedUntil)
                    return $remote
                }
            }
            $remote.Branch      = [string]$branch
            $remote.Version     = [string]$branch
            $remote.DownloadUrl = "$repoUrl/archive/refs/heads/$branch.zip"
            $head = Get-RemoteFileInfo -Url $remote.DownloadUrl -Headers $Headers
            $remote.RemoteETag = $head.ETag; $remote.RemoteLastModified = $head.LastModified; $remote.RemoteLength = $head.Length
            $remote.Ok = $true
        }
        'specificFile' {
            if ($ToolConfig.ContainsKey("SpecificFilePath") -and -not [string]::IsNullOrEmpty($ToolConfig.SpecificFilePath)) {
                if ($ToolConfig.RepoUrl -like "https://github.com/*") {
                    $rawRepoUrl = $ToolConfig.RepoUrl -replace "https://github.com/", "https://raw.githubusercontent.com/"
                    $cleanPath = $ToolConfig.SpecificFilePath -replace "^/raw", ""
                    $remote.DownloadUrl = "$rawRepoUrl$cleanPath"
                }
                else {
                    $remote.DownloadUrl = "$($ToolConfig.RepoUrl)$($ToolConfig.SpecificFilePath)"
                }
            }
            else {
                $remote.DownloadUrl = [string]$ToolConfig.RepoUrl
            }
            $remote.Version = "latest"
            $head = Get-RemoteFileInfo -Url $remote.DownloadUrl -Headers $Headers
            $remote.RemoteETag = $head.ETag; $remote.RemoteLastModified = $head.LastModified; $remote.RemoteLength = $head.Length
            $remote.Ok = $true
        }
        default {
            Write-LogError "Download method '$($remote.Method)' not recognized for $name."
            $remote.Error = "Download method '$($remote.Method)' not recognized"
        }
    }
    return $remote
}

# True when every manifest entry exists with a matching digest (placeholders are skipped).
function Test-ToolIntact {
    param (
        [Parameter(Mandatory=$true)]$Marker,
        [Parameter(Mandatory=$true)][string]$OutputFolder
    )
    $manifest = ConvertTo-ManifestTable -Manifest $Marker.Manifest
    if ($manifest.Count -eq 0) { return $true }
    $declared = Get-MarkerValue -Marker $Marker -Name 'HashAlgorithm'
    $root = $OutputFolder.TrimEnd('\', '/')
    foreach ($entry in $manifest.GetEnumerator()) {
        if ($entry.Value -eq 'FILE_HASH_ERROR') { continue }
        $path = Join-Path $root $entry.Key
        if (-not (Test-Path -LiteralPath $path)) {
            Write-LogDebug "Managed file missing: $($entry.Key)"
            return $false
        }
        try {
            $algorithm = Get-ManifestEntryAlgorithm -Digest $entry.Value -Declared $declared
            if ((Get-FileHashHex -Path $path -Algorithm $algorithm) -ine $entry.Value) {
                Write-LogDebug "Managed file modified: $($entry.Key)"
                return $false
            }
        }
        catch {
            Write-LogDebug "Could not verify $($entry.Key): $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

# True when the installed copy matches upstream (per download method) AND its managed files
# are intact. Anything else means "download again".
function Test-ToolUpToDate {
    param (
        [Parameter(Mandatory=$false)]$Marker,
        [Parameter(Mandatory=$false)][hashtable]$Remote,
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$OutputFolder
    )
    if ($null -eq $Marker -or $null -eq $Remote -or -not $Remote.Ok) { return $false }
    $method = [string]$ToolConfig.DownloadMethod
    if ((Get-MarkerValue -Marker $Marker -Name 'DownloadMethod') -ne $method) { return $false }
    $markerUrl  = Get-MarkerValue -Marker $Marker -Name 'DownloadURL'
    $markerETag = Get-MarkerValue -Marker $Marker -Name 'RemoteETag'
    $same = $false
    switch ($method) {
        'latestRelease' {
            $same = (-not [string]::IsNullOrEmpty($Remote.Version)) -and ((Get-MarkerValue -Marker $Marker -Name 'Version') -eq $Remote.Version) -and ($markerUrl -eq $Remote.DownloadUrl)
        }
        'gitClone' {
            $same = (-not [string]::IsNullOrEmpty($Remote.CommitHash)) -and ((Get-MarkerValue -Marker $Marker -Name 'CommitHash') -eq $Remote.CommitHash)
        }
        'branchZip' {
            $same = (-not [string]::IsNullOrEmpty($Remote.RemoteETag)) -and ($markerETag -eq $Remote.RemoteETag) -and ($markerUrl -eq $Remote.DownloadUrl)
        }
        'specificFile' {
            if (-not [string]::IsNullOrEmpty($Remote.RemoteETag)) {
                $same = ($markerETag -eq $Remote.RemoteETag) -and ($markerUrl -eq $Remote.DownloadUrl)
            }
            elseif (-not [string]::IsNullOrEmpty($Remote.RemoteLastModified) -and -not [string]::IsNullOrEmpty($Remote.RemoteLength)) {
                $same = ((Get-MarkerValue -Marker $Marker -Name 'RemoteLastModified') -eq $Remote.RemoteLastModified) -and ((Get-MarkerValue -Marker $Marker -Name 'RemoteLength') -eq $Remote.RemoteLength) -and ($markerUrl -eq $Remote.DownloadUrl)
            }
        }
    }
    if (-not $same) { return $false }
    if (-not (Test-ToolIntact -Marker $Marker -OutputFolder $OutputFolder)) {
        Write-LogInfo "$($ToolConfig.Name): upstream unchanged, but local managed files were modified or removed; re-downloading."
        return $false
    }
    return $true
}

function Get-GitHubHeaders {
    param (
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )

    $headers = @{ "User-Agent" = $script:UserAgent }
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
        [Parameter(Mandatory=$false)][hashtable]$Headers = @{ "User-Agent" = $script:UserAgent }
    )
    if ($RepoUrl.TrimEnd('/') -notmatch "github\.com/([^/]+)/([^/]+?)(?:\.git)?$") {
        Write-LogWarning "Cannot determine default branch: '$RepoUrl' is not a github.com URL"
        return $null
    }
    return Resolve-DefaultBranch -Owner $matches[1] -Repo $matches[2] -Headers $Headers
}

# -----------------------------------------------
# Function: Download Specific File Tool
# -----------------------------------------------
function Save-SpecificFileTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = "",
        [Parameter(Mandatory=$false)][hashtable]$Remote = $null
    )

    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "Name")) { return $false }
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "RepoUrl")) { return $false }
    $extract = Get-DefaultValue -Tool $ToolConfig -Parameter "Extract" -DefaultValue $true
    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT
    if ($null -eq $Remote) { $Remote = Resolve-ToolRemote -ToolConfig $ToolConfig -Headers $headers }
    if (-not $Remote.Ok) { return $false }

    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    if ($null -eq $outputFolder) {
        Write-LogError "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
        return $false
    }

    $fileUrl = $Remote.DownloadUrl
    Write-LogDebug "Constructed URL: $fileUrl"
    # DownloadName names the saved file (and decides ZIP handling) when the URL does not end
    # with a file name, e.g. vendor "latest" links that redirect to a versioned installer.
    $downloadName = [System.IO.Path]::GetFileName($fileUrl)
    if (Test-RequiredParameter -Tool $ToolConfig -Parameter "DownloadName") { $downloadName = [string]$ToolConfig.DownloadName }
    $ext = [System.IO.Path]::GetExtension($downloadName)

    if ($ext -ieq ".zip" -and $extract) {
        $expected = if ($ToolConfig.ContainsKey("ExpectedSha256")) { $ToolConfig.ExpectedSha256 } else { "" }
        $staging = Invoke-ZipStaging -ZipUrl $fileUrl -ToolName $ToolConfig.Name -Version "latest" -Headers $headers -ExpectedSha256 $expected -SaveAs $downloadName
        if (-not $staging.Success) {
            Remove-StagingLeftover -Paths $staging.TempFiles
            Write-LogError "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
            return $false
        }
        return [bool](Expand-StagedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $fileUrl -Version "latest" -Remote $Remote)
    }
    return [bool](Save-NonZipFile -FileUrl $fileUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Headers $headers -Remote $Remote -SaveAs $downloadName)
}

# -----------------------------------------------
# Function: Download Branch Zip Tool
# -----------------------------------------------
function Save-BranchZipTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = "",
        [Parameter(Mandatory=$false)][hashtable]$Remote = $null
    )

    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "Name")) { return $false }
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "RepoUrl")) { return $false }
    $extract = Get-DefaultValue -Tool $ToolConfig -Parameter "Extract" -DefaultValue $true
    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT
    if ($null -eq $Remote) { $Remote = Resolve-ToolRemote -ToolConfig $ToolConfig -Headers $headers }
    if (-not $Remote.Ok) { return $false }

    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    if ($null -eq $outputFolder) {
        Write-LogError "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
        return $false
    }

    $branch = $Remote.Branch
    $zipUrl = $Remote.DownloadUrl
    Write-LogInfo "Downloading branch zip for $($ToolConfig.Name) (branch: $branch)..."

    if ($extract) {
        $expected = if ($ToolConfig.ContainsKey("ExpectedSha256")) { $ToolConfig.ExpectedSha256 } else { "" }
        $staging = Invoke-ZipStaging -ZipUrl $zipUrl -ToolName $ToolConfig.Name -Version $branch -Headers $headers -ExpectedSha256 $expected
        if (-not $staging.Success) {
            Remove-StagingLeftover -Paths $staging.TempFiles
            Write-LogError "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
            return $false
        }
        return [bool](Expand-StagedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $zipUrl -Version $branch -Remote $Remote)
    }
    return [bool](Save-NonZipFile -FileUrl $zipUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Version $branch -Headers $headers -Remote $Remote)
}

# -----------------------------------------------
# Function: Download Latest Release Tool
# -----------------------------------------------
function Save-LatestReleaseTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = "",
        [Parameter(Mandatory=$false)][hashtable]$Remote = $null
    )

    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "Name")) { return $false }
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "RepoUrl")) { return $false }
    $extract = Get-DefaultValue -Tool $ToolConfig -Parameter "Extract" -DefaultValue $true
    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT
    if ($null -eq $Remote) { $Remote = Resolve-ToolRemote -ToolConfig $ToolConfig -Headers $headers }
    if (-not $Remote.Ok) { return $false }

    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    if ($null -eq $outputFolder) {
        Write-LogError "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
        return $false
    }

    $downloadUrl = $Remote.DownloadUrl
    $fileName = Split-Path $downloadUrl -Leaf
    $ext = [System.IO.Path]::GetExtension($fileName)

    if ($ext -ieq ".zip" -and $extract) {
        $expected = if ($ToolConfig.ContainsKey("ExpectedSha256")) { $ToolConfig.ExpectedSha256 } else { "" }
        $staging = Invoke-ZipStaging -ZipUrl $downloadUrl -ToolName $ToolConfig.Name -Version $Remote.Version -Headers $headers -ExpectedSha256 $expected
        if (-not $staging.Success) {
            Remove-StagingLeftover -Paths $staging.TempFiles
            Write-LogError "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
            return $false
        }
        return [bool](Expand-StagedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $downloadUrl -Version $Remote.Version -Remote $Remote)
    }
    return [bool](Save-NonZipFile -FileUrl $downloadUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Version $Remote.Version -Headers $headers -Remote $Remote)
}

# -----------------------------------------------
# Function: Download Git Clone Tool
# -----------------------------------------------
function Save-GitCloneTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = "",
        [Parameter(Mandatory=$false)][hashtable]$Remote = $null
    )

    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "Name")) { return $false }
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "RepoUrl")) { return $false }
    $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT
    if ($null -eq $Remote) { $Remote = Resolve-ToolRemote -ToolConfig $ToolConfig -Headers $headers }
    if (-not $Remote.Ok) { return $false }

    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    if ($null -eq $outputFolder) {
        Write-LogError "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
        return $false
    }

    $branch = $Remote.Branch
    $commitHash = $Remote.CommitHash
    $zipUrl = $Remote.DownloadUrl
    Write-LogInfo "Downloading repository ZIP for $($ToolConfig.Name) from branch $branch (commit $commitHash)..."
    Write-LogDebug "ZIP URL: $zipUrl"

    $expected = if ($ToolConfig.ContainsKey("ExpectedSha256")) { $ToolConfig.ExpectedSha256 } else { "" }
    $staging = Invoke-ZipStaging -ZipUrl $zipUrl -ToolName $ToolConfig.Name -Version $branch -Headers $headers -ExpectedSha256 $expected
    if (-not $staging.Success) {
        Remove-StagingLeftover -Paths $staging.TempFiles
        Write-LogError "Failed to process ZIP for $($ToolConfig.Name): $($staging.ErrorMessage)"
        return $false
    }

    # Repository archives keep their <repo>-<sha> wrapper folder (no flattening, as before).
    $tempExtract = $staging.TempExtract
    Write-LogTrace "Generating file manifest for extracted content"
    $newManifest = Get-FileManifest -Folder $tempExtract
    Write-LogDebug "Generated manifest with $($newManifest.Count) files"

    # Only now, with the new content downloaded and extracted, is the previous install cleaned.
    if (Test-Path (Join-Path $outputFolder ".downloaded.json")) {
        Write-LogDebug "Removing previously managed files from $outputFolder"
        Remove-ManagedFiles -OutputFolder $outputFolder
    }

    Write-LogDebug "Moving extracted files to output folder: $outputFolder"
    Move-StagedContent -SourceFolder $tempExtract -Destination $outputFolder
    Write-LogDebug "Moved extracted files to output folder: $outputFolder"

    Write-MarkerFile -OutputFolder $outputFolder `
                     -ToolName $ToolConfig.Name `
                     -DownloadMethod $ToolConfig.DownloadMethod `
                     -DownloadURL $zipUrl `
                     -Version $branch `
                     -CommitHash $commitHash `
                     -DownloadedFile "" `
                     -ExtractionLocation $outputFolder `
                     -Manifest $newManifest `
                     -Branch $branch `
                     -ApiETag $Remote.ApiETag

    # Clean up staging files
    Write-LogTrace "Cleaning up temporary files"
    Remove-Item -Path $staging.TempExtract -Recurse -Force
    Remove-Item -Path $staging.TempZip -Force

    Write-LogInfo "Successfully downloaded and extracted $($ToolConfig.Name) from branch $branch (commit $commitHash)"
    return $true
}

# -----------------------------------------------
# Function: Invoke Tool Work (one tool's full update + dispatch)
# -----------------------------------------------
# Encapsulates one iteration of the dispatcher loop so it can be invoked
# either sequentially (foreach) or in parallel (ForEach-Object -Parallel).
# All mutable state (Tool config, target dir, PAT, mode flags) is passed
# explicitly so the function works inside a fresh runspace.
# -----------------------------------------------
# Planning: decide what to do with one tool (no downloads, no deletions)
# -----------------------------------------------
# Returns a plan whose Action is skip, dry-run, up-to-date, failed or download. Remote
# metadata is resolved here, once, so the dispatcher can plan serially (GitHub asks for API
# requests to be serial) even when the downloads themselves run in parallel.
function Get-ToolPlan {
    param (
        [Parameter(Mandatory=$true)]$Tool,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = "",
        [Parameter(Mandatory=$false)][string]$UpdateMode = $null,
        [Parameter(Mandatory=$false)][string[]]$UpdateToolList = @(),
        [Parameter(Mandatory=$false)][switch]$ForceDownload,
        [Parameter(Mandatory=$false)][switch]$DryRun
    )

    $plan = [pscustomobject]@{
        Tool = $Tool; Name = [string]$Tool.Name; Method = [string]$Tool.DownloadMethod
        OutputFolder = ''; Action = 'skip'; Status = 'skipped'; Detail = ''; Remote = $null; IsUpdate = $false
    }

    try {
        if (Test-PlaceholderEntry -Tool $Tool) {
            Write-LogDebug "Skipping placeholder entry: $($Tool.Name)"
            $plan.Detail = 'placeholder'
            return $plan
        }

        if (-not [string]::IsNullOrEmpty($Tool.OutputFolder)) {
            $toolOutputFolder = Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $Tool.OutputFolder $Tool.Name)
        }
        else {
            $toolOutputFolder = Join-Path -Path $ToolsDirectory -ChildPath $Tool.Name
        }
        $plan.OutputFolder = $toolOutputFolder
        $markerFile   = Join-Path $toolOutputFolder ".downloaded.json"
        $folderExists = Test-Path -LiteralPath $toolOutputFolder
        $markerExists = Test-Path -LiteralPath $markerFile
        $processTool  = $false

        if ($UpdateMode -eq "specific") {
            if ($UpdateToolList -contains $Tool.Name.ToLower()) {
                $processTool = $true
                $plan.IsUpdate = $folderExists
                Write-Host "===========================================" -ForegroundColor White
                if ($folderExists) {
                    Write-LogInfo "Updating tool: $($Tool.Name)"
                }
                else {
                    Write-LogInfo "Tool $($Tool.Name) not found locally. Will download it."
                }
            }
            else {
                $plan.Detail = 'not in the -UpdateTools list'
            }
        }
        elseif ($UpdateMode -eq "general") {
            if ($folderExists) {
                if ($ForceDownload) {
                    $processTool = $true
                    $plan.IsUpdate = $true
                    Write-Host "===========================================" -ForegroundColor White
                    Write-LogInfo "Force updating tool: $($Tool.Name)"
                }
                elseif (-not $Tool.skipdownload) {
                    $processTool = $true
                    $plan.IsUpdate = $true
                    Write-Host "===========================================" -ForegroundColor White
                    Write-LogInfo "Updating tool: $($Tool.Name)"
                }
                else {
                    Write-LogInfo "Skipping update for $($Tool.Name) -- skipdownload is enabled. Use -force to override."
                    $plan.Detail = 'skipdownload'
                }
            }
            else {
                Write-LogDebug "$($Tool.Name) is not installed; -UpdateAll only updates installed tools."
                $plan.Detail = 'not installed'
            }
        }
        else {
            if ($ForceDownload) {
                $processTool = $true
                $plan.IsUpdate = $markerExists
                Write-Host "===========================================" -ForegroundColor White
                Write-LogInfo "Force downloading $($Tool.Name)..."
            }
            elseif ($Tool.skipdownload) {
                Write-LogInfo "Skipping $($Tool.Name) -- skipdownload is enabled."
                $plan.Detail = 'skipdownload'
            }
            elseif ($markerExists) {
                Write-LogInfo "Skipping $($Tool.Name) -- already downloaded."
                $plan.Detail = 'already downloaded'
            }
            else {
                $processTool = $true
                Write-Host "===========================================" -ForegroundColor White
                Write-LogInfo "Started working on $($Tool.Name)..."
            }
        }

        if (-not $processTool) { return $plan }

        $headers = Get-GitHubHeaders -GitHubPAT $GitHubPAT
        $marker = $null
        if ($markerExists) { $marker = Get-ToolMarker -OutputFolder $toolOutputFolder }
        $remote = $null

        # Up-to-date check before anything is removed or downloaded (conditional API request).
        if (-not $ForceDownload -and $null -ne $marker) {
            $remote = Resolve-ToolRemote -ToolConfig $Tool -Headers $headers -Marker $marker
            if ($remote.Ok -and (Test-ToolUpToDate -Marker $marker -Remote $remote -ToolConfig $Tool -OutputFolder $toolOutputFolder)) {
                if (-not [string]::IsNullOrEmpty($remote.CommitHash)) {
                    $what = "commit $($remote.CommitHash.Substring(0, [Math]::Min(7, $remote.CommitHash.Length)))"
                }
                elseif ($remote.Method -eq 'latestRelease') {
                    $what = "version $($remote.Version)"
                }
                else {
                    $what = "unchanged upstream"
                }
                Write-LogInfo "$($Tool.Name) is up to date ($what); skipping."
                # Markers written before ETags were recorded get them now, so later checks are
                # conditional requests that cost no rate-limit quota.
                Update-MarkerRemoteState -OutputFolder $toolOutputFolder -Marker $marker -Remote $remote
                Write-Host "===========================================" -ForegroundColor White
                $plan.Action = 'up-to-date'
                $plan.Status = 'up-to-date'
                $plan.Detail = $what
                return $plan
            }
            if ($remote.Ok -and $remote.NotModified) {
                # Local files changed: the 304 carried no body, so fetch the full metadata now.
                $remote = Resolve-ToolRemote -ToolConfig $Tool -Headers $headers
            }
        }

        if ($DryRun) {
            Write-LogInfo "[DRY-RUN] Would $($Tool.DownloadMethod) tool: $($Tool.Name) -> $toolOutputFolder"
            Write-Host "===========================================" -ForegroundColor White
            $plan.Action = 'dry-run'
            $plan.Status = 'dry-run'
            return $plan
        }

        if ($null -eq $remote) { $remote = Resolve-ToolRemote -ToolConfig $Tool -Headers $headers }
        if (-not $remote.Ok) {
            $plan.Action = 'failed'
            $plan.Status = 'failed'
            if ($remote.RateLimited) {
                $plan.Status = 'rate-limited'
                Write-LogWarning "Skipping $($Tool.Name): $($remote.Error)"
            }
            $plan.Detail = $remote.Error
            Write-Host "===========================================" -ForegroundColor White
            return $plan
        }

        $plan.Remote = $remote
        $plan.Action = 'download'
        $plan.Status = 'pending'
        return $plan
    }
    catch {
        Write-LogError "Failed to plan tool $($Tool.Name). Exception: $_"
        $plan.Action = 'failed'
        $plan.Status = 'failed'
        $plan.Detail = "$_"
        return $plan
    }
}

function ConvertTo-ToolResult {
    param (
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$false)][double]$Seconds = 0
    )
    return [pscustomobject]@{ Name = $Plan.Name; Method = $Plan.Method; Status = $Plan.Status; Detail = $Plan.Detail; Seconds = [math]::Round($Seconds, 1) }
}

# Executes a 'download' plan. This is the only place that downloads, cleans and writes markers.
function Invoke-ToolDownload {
    param (
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $status = 'failed'
    $detail = ''
    try {
        $tool = $Plan.Tool
        $ok = $false
        switch ($tool.DownloadMethod) {
            "gitClone"      { $ok = [bool](@(Save-GitCloneTool      -ToolConfig $tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT -Remote $Plan.Remote)[-1]) }
            "latestRelease" { $ok = [bool](@(Save-LatestReleaseTool -ToolConfig $tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT -Remote $Plan.Remote)[-1]) }
            "branchZip"     { $ok = [bool](@(Save-BranchZipTool     -ToolConfig $tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT -Remote $Plan.Remote)[-1]) }
            "specificFile"  { $ok = [bool](@(Save-SpecificFileTool  -ToolConfig $tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT -Remote $Plan.Remote)[-1]) }
            default {
                Write-LogError "Download method '$($tool.DownloadMethod)' not recognized for $($tool.Name)."
                $detail = "unknown download method '$($tool.DownloadMethod)'"
            }
        }
        if ($ok) {
            if ($Plan.IsUpdate) { $status = 'updated' } else { $status = 'downloaded' }
        }
        elseif ([string]::IsNullOrEmpty($detail)) {
            $detail = 'see the errors logged above'
        }
        Write-LogInfo "Finished working on $($tool.Name)."
        Write-Host "===========================================" -ForegroundColor White
    }
    catch {
        Write-LogError "Failed to process tool $($Plan.Name). Exception: $_"
        $detail = "$_"
    }
    $stopwatch.Stop()
    return [pscustomobject]@{ Name = $Plan.Name; Method = $Plan.Method; Status = $status; Detail = $detail; Seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1) }
}

# Sequential convenience wrapper: plan one tool and download it when needed.
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
    $plan = Get-ToolPlan -Tool $Tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT -UpdateMode $UpdateMode -UpdateToolList $UpdateToolList -ForceDownload:$ForceDownload -DryRun:$DryRun
    if ($plan.Action -eq 'download') {
        return Invoke-ToolDownload -Plan $plan -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT
    }
    return ConvertTo-ToolResult -Plan $plan
}

# End-of-run summary: counts per status and a list of problems.
function Write-RunSummary {
    param (
        [Parameter(Mandatory=$true)]$Results,
        [Parameter(Mandatory=$false)][double]$ElapsedSeconds = 0
    )
    # Not @($Results): the array subexpression fails with "Argument types do not match" on a
    # List[object] that holds PSCustomObjects (both editions). Enumerate explicitly instead.
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Results) { if ($null -ne $item) { $all.Add($item) } }
    $parts = @()
    foreach ($status in @('downloaded', 'updated', 'up-to-date', 'skipped', 'dry-run', 'rate-limited', 'failed')) {
        $count = @($all | Where-Object { $_.Status -eq $status }).Count
        if ($count -gt 0) { $parts += "$status $count" }
    }
    $summary = $parts -join ', '
    Write-Host ""
    Write-Host "Run summary ($($all.Count) tools, $([math]::Round($ElapsedSeconds, 1)) s): $summary" -ForegroundColor Cyan
    $problems = @($all | Where-Object { $_.Status -eq 'failed' -or $_.Status -eq 'rate-limited' })
    if ($problems.Count -gt 0) {
        Write-Host "Problems:" -ForegroundColor Yellow
        foreach ($problem in $problems) {
            Write-Host ("  {0,-13} {1} ({2}): {3}" -f $problem.Status, $problem.Name, $problem.Method, $problem.Detail) -ForegroundColor Yellow
        }
    }
    Write-LogInfo "Run summary: $summary"
}

if (-not $SourceOnly) {

# -----------------------------------------------
# Dispatcher: plan every tool, then download
# -----------------------------------------------
$useParallel = $Parallel -and ($PSVersionTable.PSVersion.Major -ge 7)
if ($Parallel -and -not $useParallel) {
    Write-LogWarning "-Parallel requires PowerShell 7+ (you're on $($PSVersionTable.PSVersion)). Falling back to sequential."
}
$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$results = New-Object System.Collections.Generic.List[object]

if ($useParallel) {
    Write-LogInfo "Running with parallel dispatch (ThrottleLimit=$ThrottleLimit)."
    # Plan serially here: GitHub asks for API requests to be made serially, and the
    # up-to-date checks, dry-run preview and rate-limit stop all live in the planner.
    # Runspaces only download, extract and copy.
    $plans = New-Object System.Collections.Generic.List[object]
    foreach ($tool in $tools) {
        $plan = Get-ToolPlan -Tool $tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT -UpdateMode $updateMode -UpdateToolList $updateToolList -ForceDownload:$ForceDownload -DryRun:$DryRun
        if ($plan.Action -eq 'download') { $plans.Add($plan) } else { $results.Add((ConvertTo-ToolResult -Plan $plan)) }
    }
    if ($plans.Count -gt 0) {
        $scriptPath = $PSCommandPath
        if ([string]::IsNullOrEmpty($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }
        # Everything a runspace needs from this run. Pooled runspaces keep functions but lose all
        # variables between iterations, so each iteration re-applies this state after dot-sourcing.
        $runState = @{
            LogFile        = $script:LogFile
            LoggingEnabled = $script:LoggingEnabled
            LogMutexName   = $script:LogMutexName
            VerboseOutput  = [bool]$VerboseOutput
            TraceOutput    = [bool]$TraceOutput
            GitHubPAT      = $GitHubPAT
        }
        $parallelResults = $plans | ForEach-Object -Parallel {
            . $using:scriptPath -SourceOnly
            Set-ToolFetcherRunState -State $using:runState
            Invoke-ToolDownload -Plan $_ -ToolsDirectory $using:ToolsDirectory -GitHubPAT $using:GitHubPAT
        } -ThrottleLimit $ThrottleLimit
        foreach ($item in @($parallelResults)) { if ($null -ne $item) { $results.Add($item) } }
    }
}
else {
    foreach ($tool in $tools) {
        $results.Add((Invoke-ToolWork -Tool $tool `
                        -ToolsDirectory $ToolsDirectory `
                        -GitHubPAT $GitHubPAT `
                        -UpdateMode $updateMode `
                        -UpdateToolList $updateToolList `
                        -ForceDownload:$ForceDownload `
                        -DryRun:$DryRun))
    }
}
$runStopwatch.Stop()

# Best-effort cleanup of the per-process staging folder.
if (Test-Path $script:StagingRoot) {
    Remove-Item -Path $script:StagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-RunSummary -Results $results -ElapsedSeconds $runStopwatch.Elapsed.TotalSeconds
$failedCount = @($results | Where-Object { $_.Status -eq 'failed' -or $_.Status -eq 'rate-limited' }).Count
if ($failedCount -gt 0) { exit 1 }

} # end: if (-not $SourceOnly) for main-flow-B (dispatcher)
