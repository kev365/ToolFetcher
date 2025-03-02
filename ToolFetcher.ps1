# =====================================================
# ToolFetcher
#
# A tool for fetching DFIR and other GitHub tools.
#
# Author: Kevin Stokes
# Version: See $script:Version variable below
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

# Script version - centralized for easy updates
$script:Version = "2.0.0"

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

# Set default logging level
$script:LoggingLevel = [LogLevel]::Info
$script:LogFile = $null
$script:LoggingEnabled = $false

# Main logging function that handles different log levels, console output, and file logging
function Write-ToolLog {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][LogLevel]$Level = [LogLevel]::Info,
        [Parameter(Mandatory=$false)][switch]$NoConsole = $false,
        [Parameter(Mandatory=$false)][ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    
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

function Log-Error {
    param ([string]$Message)
    Write-ToolLog -Message $Message -Level ([LogLevel]::Error) -ForegroundColor Red
}

function Log-Warning {
    param ([string]$Message)
    Write-ToolLog -Message $Message -Level ([LogLevel]::Warning) -ForegroundColor Yellow
}

function Log-Info {
    param ([string]$Message)
    Write-ToolLog -Message $Message -Level ([LogLevel]::Info) -ForegroundColor Cyan
}

function Log-Debug {
    param ([string]$Message)
    # Always log debug messages to file, but only show on console if VerboseOutput is enabled
    Write-ToolLog -Message $Message -Level ([LogLevel]::Debug) -ForegroundColor DarkGray
}

function Log-Trace {
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
            Log-Debug "Created log directory: $logDir"
        }
        
        # Test if we can write to the log file
        $null = New-Item -Path $LogPath -ItemType File -Force
        $script:LogFile = $LogPath
        $script:LoggingEnabled = $true
        
        Log-Info "Logging enabled to file: $LogPath"
        
        # Write a test entry to verify we can write to the file
        # Use Write-ToolLog instead of direct Add-Content to ensure consistent formatting
        Log-Info "Logging initialized"
        Log-Debug "Successfully wrote test entry to log file"
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
# Function: Test Tool Configuration
# -----------------------------------------------
function Test-ToolConfiguration {
    param ([Parameter(Mandatory = $true)]$Config)
    
    $isValid = $true
    $errors = @()
    
    # Check if tooldirectory is specified
    if (-not $Config.ContainsKey("tooldirectory") -or [string]::IsNullOrWhiteSpace($Config.tooldirectory)) {
        $isValid = $false
        $errors += "Missing or empty 'tooldirectory' in configuration"
    }
    
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
                foreach ($error in $toolValidation.Errors) {
                    $errors += "Tool '$($tool.name)': $error"
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
    
    # Check required parameters for all tools
    if (-not (Test-RequiredParameter -Tool $Tool -Parameter "name")) {
        $isValid = $false
        $errors += "Missing required parameter 'name'"
    }
    
    if (-not (Test-RequiredParameter -Tool $Tool -Parameter "RepoUrl")) {
        $isValid = $false
        $errors += "Missing required parameter 'RepoUrl'"
    }
    
    if (-not (Test-RequiredParameter -Tool $Tool -Parameter "DownloadMethod")) {
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
                if (-not $Tool.SkipDownload -and 
                    -not (Test-RequiredParameter -Tool $Tool -Parameter "SpecificFilePath") -and 
                    -not (Test-RequiredParameter -Tool $Tool -Parameter "DownloadName")) {
                    $isValid = $false
                    $errors += "For 'specificFile' method, either 'SpecificFilePath' or 'DownloadName' must be specified when SkipDownload is not true"
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

# -----------------------------------------------
# Function: Add Configuration Defaults
# -----------------------------------------------
function Add-ConfigurationDefaults {
    param ([Parameter(Mandatory = $true)]$Config)
    
    $updatedConfig = $Config.Clone()
    
    # Add default values to each tool
    if ($updatedConfig.ContainsKey("tools") -and $null -ne $updatedConfig.tools) {
        for ($i = 0; $i -lt $updatedConfig.tools.Count; $i++) {
            $tool = $updatedConfig.tools[$i]
            
            # Add default values based on download method
            switch ($tool.DownloadMethod) {
                "gitClone" {
                    # Default branch to master if not specified
                    if (-not $tool.ContainsKey("Branch") -or [string]::IsNullOrWhiteSpace($tool.Branch)) {
                        $tool.Branch = "master"
                    }
                }
                "branchZip" {
                    # Default branch to master if not specified
                    if (-not $tool.ContainsKey("Branch") -or [string]::IsNullOrWhiteSpace($tool.Branch)) {
                        $tool.Branch = "master"
                    }
                    
                    # Default Extract to true if not specified
                    if (-not $tool.ContainsKey("Extract")) {
                        $tool.Extract = $true
                    }
                }
                "latestRelease" {
                    # No specific defaults needed
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

# Initialize logging
if ($TraceOutput) {
    $script:LoggingLevel = [LogLevel]::Trace
}
elseif ($VerboseOutput) {
    $script:LoggingLevel = [LogLevel]::Debug
}
else {
    # For file logging, always use Debug level to capture more information
    $script:LoggingLevel = [LogLevel]::Debug
}

# Enable file logging only if explicitly requested
if ($Log) {
    $script:LoggingEnabled = $true
    Log-Debug "Logging to file is enabled by user request"
}
else {
    $script:LoggingEnabled = $false
    Log-Debug "Logging to file is disabled (use -Log to enable)"
}

Log-Info "ToolFetcher v$script:Version started"


# -----------------------------------------------
# Failsafe for ToolsFile
# -----------------------------------------------
$defaultToolsFileUrl = "https://raw.githubusercontent.com/kev365/ToolFetcher/refs/heads/main/tools.yaml"
if ($ToolsFile -match '^https?://') {
    try {
        $response = Invoke-WebRequest -Uri $ToolsFile -Method Head -UseBasicParsing -ErrorAction Stop
        Log-Info "Using user-specified URL for tools file: $ToolsFile"
    }
    catch {
        Log-Warning "The user-specified URL '$ToolsFile' is not available."
        $choice = Read-Host "Do you want to use the default URL ($defaultToolsFileUrl)? (Y/N)"
        if ($choice -match '^(?i:Y(es)?)$') {
            $ToolsFile = $defaultToolsFileUrl
            Log-Info "Using default URL: $ToolsFile"
        }
        else {
            Log-Error "Exiting script."
            exit 1
        }
    }
}
else {
    if ([System.IO.Path]::IsPathRooted($ToolsFile)) {
        if (Test-Path -Path $ToolsFile) {
            Log-Info "Using user-specified local tools file: $ToolsFile"
        }
        else {
            Log-Warning "The local tools file specified ($ToolsFile) was not found."
            $choice = Read-Host "Do you want to use the default URL ($defaultToolsFileUrl)? (Y/N)"
            if ($choice -match '^(?i:Y(es)?)$') {
                $ToolsFile = $defaultToolsFileUrl
                Log-Info "Using default URL: $ToolsFile"
            }
            else {
                Log-Error "Exiting script."
                exit 1
            }
        }
    }
    else {
        $localToolsFile = Join-Path $PSScriptRoot $ToolsFile
        if (Test-Path -Path $localToolsFile) {
            Log-Info "Using local tools file: $localToolsFile"
            $ToolsFile = $localToolsFile
        }
        else {
            Log-Warning "Local tools file '$ToolsFile' not found at '$localToolsFile'."
            $choice = Read-Host "Do you want to use the default URL ($defaultToolsFileUrl)? (Y/N)"
            if ($choice -match '^(?i:Y(es)?)$') {
                $ToolsFile = $defaultToolsFileUrl
                Log-Info "Using default URL: $ToolsFile"
            }
            else {
                Log-Error "Exiting script."
                exit 1
            }
        }
    }
}

# -----------------------------------------------
# Global Logging Setup
# -----------------------------------------------
# Remove these duplicate functions since they're already defined above
# function Log-Debug { param ([string]$Message) if ($VerboseOutput) { Write-Host "[DEBUG] $Message" -ForegroundColor DarkGray } }
# function Log-Info  { param ([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
# function Log-Warning { param ([string]$Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
# function Log-Error { param ([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

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

    # Setup logging after we have the tools directory
    if ($Log) {
        $logFilePath = Join-Path -Path $ToolsDirectory -ChildPath "ToolFetcher_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Enable-FileLogging -LogPath $logFilePath
        Log-Info "Log file will contain verbose information even though console output is normal"
    }

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
if ($PromptForPAT) {
    Log-Info "Prompting for GitHub Personal Access Token..."
    $secureString = Read-Host "Enter your GitHub Personal Access Token" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    try {
        $GitHubPAT = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
}

if (-not [string]::IsNullOrEmpty($GitHubPAT)) {
    if (-not (Validate-GitHubPAT -Token $GitHubPAT)) {
        $choice = Read-Host "The provided GitHub PAT appears to be invalid. Would you like to enter a new token? (Y/N)"
        if ($choice -match '^(?i:Y(es)?)$') {
            $secureString = Read-Host "Please enter a valid GitHub Personal Access Token" -AsSecureString
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
            try {
                $GitHubPAT = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            } finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            }
            
            if (-not (Validate-GitHubPAT -Token $GitHubPAT)) {
                Write-Host "The provided token is still invalid. Exiting." -ForegroundColor Red
                exit 1
            }
            else {
                Log-Info "GitHub PAT validated successfully."
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
        # First check if the drive exists
        $drive = [System.IO.Path]::GetPathRoot($ToolsDirectory)
        if (-not [System.IO.Directory]::Exists($drive)) {
            Log-Error "Drive '$drive' does not exist. Please specify a valid drive."
            exit 1
        }
        
        New-Item -Path $ToolsDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
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

# Validates that a required parameter has a value
# Returns true if the parameter is valid, false otherwise
function Test-RequiredParameter {
    param (
        [Parameter(Mandatory=$true)]$Tool,
        [Parameter(Mandatory=$true)][string]$Parameter
    )
    
    return $Tool.ContainsKey($Parameter) -and -not [string]::IsNullOrWhiteSpace($Tool[$Parameter])
}

# Gets a default value for a parameter if the provided value is null
# Returns the provided value if not null, otherwise returns the default value
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
# Function: Process ZIP Staging
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
            $hash = (Get-FileHash -Algorithm MD5 -Path $file.FullName -ErrorAction Stop).Hash
            $manifest[$relativePath] = $hash
        }
        catch {
            Log-Warning "Could not calculate hash for file: $($file.FullName). Error: $_"
            # Still include the file in the manifest with a placeholder hash
            $manifest[$relativePath] = "FILE_HASH_ERROR"
        }
    }
    return $manifest
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
    Log-Debug "Marker file created at $markerFile"
}

# -----------------------------------------------
# Function: Remove Managed Files
# -----------------------------------------------
function Remove-ManagedFiles {
    param ([Parameter(Mandatory=$true)][string]$OutputFolder)
    $markerFile = Join-Path $OutputFolder ".downloaded.json"
    Log-Debug "Checking for marker file at: $markerFile"
    
    if (Test-Path $markerFile) {
        Log-Debug "Marker file found, attempting to process it"
        try {
            $metadata = Get-Content -Path $markerFile | ConvertFrom-Json
            Log-Debug "Marker file loaded successfully"
            
            if ($metadata.Manifest) {
                Log-Debug "Manifest found in marker file with type: $($metadata.Manifest.GetType().FullName)"
                
                # Create a hashtable to track files by hash
                $managedHashes = @{}
                
                # Handle PSCustomObject or Hashtable for Manifest
                if ($metadata.Manifest -is [System.Management.Automation.PSCustomObject]) {
                    Log-Debug "Processing PSCustomObject manifest"
                    # Convert PSCustomObject properties to hashtable entries
                    $propertyCount = ($metadata.Manifest.PSObject.Properties | Measure-Object).Count
                    Log-Debug "Found $propertyCount properties in PSCustomObject manifest"
                    
                    $metadata.Manifest.PSObject.Properties | ForEach-Object {
                        if ($null -ne $_.Value) {
                            $managedHashes[$_.Value] = $_.Name
                            Log-Debug "Added hash mapping: $($_.Value) -> $($_.Name)"
                        }
                        else {
                            Log-Warning "Skipping null hash value for path: $($_.Name)"
                        }
                    }
                } 
                else {
                    Log-Debug "Processing hashtable manifest"
                    # Original code for hashtable
                    $keyCount = ($metadata.Manifest.Keys | Measure-Object).Count
                    Log-Debug "Found $keyCount keys in hashtable manifest"
                    
                    foreach ($relativePath in $metadata.Manifest.Keys) {
                        $hash = $metadata.Manifest.$relativePath
                        if ($null -ne $hash) {
                            $managedHashes[$hash] = $relativePath
                            Log-Debug "Added hash mapping: $hash -> $relativePath"
                        }
                        else {
                            Log-Warning "Skipping null hash value for path: $relativePath"
                        }
                    }
                }
                
                # Get all files in the directory
                $currentFiles = Get-ChildItem -Path $OutputFolder -Recurse -File | 
                    Where-Object { $_.Name -ne ".downloaded.json" -and -not ($_.Name -match "\.save\d+$") }
                $fileCount = ($currentFiles | Measure-Object).Count
                Log-Debug "Found $fileCount files in output folder (excluding .downloaded.json and .save# files)"
                
                foreach ($file in $currentFiles) {
                    $relativePath = $file.FullName.Substring($OutputFolder.Length + 1)
                    Log-Debug "Processing file: $relativePath"
                    
                    # Calculate the hash of the current file
                    try {
                        $currentHash = (Get-FileHash -Algorithm MD5 -Path $file.FullName -ErrorAction Stop).Hash
                        Log-Debug "File hash: $currentHash"
                        
                        # Check if this file is in our manifest (by hash)
                        if ($managedHashes.ContainsKey($currentHash)) {
                            # This is a managed file with unchanged content - remove it
                            Log-Debug "Hash match found, removing file: $($file.FullName)"
                            Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                            if (Test-Path $file.FullName) {
                                Log-Warning "Failed to remove file: $($file.FullName)"
                            } else {
                                Log-Debug "Successfully removed file: $($file.FullName)"
                            }
                        }
                        # Check if the relative path exists in the manifest
                        elseif (($metadata.Manifest -is [System.Management.Automation.PSCustomObject] -and 
                                $metadata.Manifest.PSObject.Properties.Name -contains $relativePath) -or
                                ($metadata.Manifest -is [System.Collections.IDictionary] -and 
                                $metadata.Manifest.ContainsKey($relativePath))) {
                            # This is a managed file with changed content - back it up
                            Log-Debug "Path match found, backing up modified file: $relativePath"
                            $backupNumber = 1
                            $backupPath = "$($file.FullName).save$backupNumber"
                            
                            # Find an available backup name
                            while (Test-Path $backupPath) {
                                $backupNumber++
                                $backupPath = "$($file.FullName).save$backupNumber"
                            }
                            
                            # Rename the file to the backup name
                            $newName = Split-Path $backupPath -Leaf
                            Log-Info "Backing up modified file: $relativePath > $newName"
                            Rename-Item -Path $file.FullName -NewName $newName -Force
                            if (Test-Path $backupPath) {
                                Log-Debug "Successfully backed up file as: $newName"
                            } else {
                                Log-Warning "Failed to back up file: $($file.FullName)"
                            }
                        }
                        else {
                            Log-Debug "File not in manifest, leaving untouched: $relativePath"
                        }
                    }
                    catch {
                        Log-Warning "Could not process file: $($file.FullName). Error: $_"
                    }
                    # Files not in the manifest are left untouched (user-added files)
                }
                
                # Log count of .save# files if any exist
                $saveFiles = Get-ChildItem -Path $OutputFolder -Recurse -File | 
                    Where-Object { $_.Name -match "\.save\d+$" }
                $saveFileCount = ($saveFiles | Measure-Object).Count
                if ($saveFileCount -gt 0) {
                    Log-Debug "Found $saveFileCount backup (.save#) files in output folder. Skipping managed file removal for these files"
                }
            }
            else {
                Log-Warning "No manifest found in marker file"
            }
            
            # Always remove the marker file
            Log-Debug "Removing marker file: $markerFile"
            Remove-Item -Path $markerFile -Force -ErrorAction SilentlyContinue
            if (Test-Path $markerFile) {
                Log-Warning "Failed to remove marker file: $markerFile"
            } else {
                Log-Debug "Successfully removed marker file: $markerFile"
            }
        }
        catch {
            Log-Warning "Failed to remove managed files in $OutputFolder. Exception: $_"
        }
    }
    else {
        Log-Debug "No marker file found in $OutputFolder. No managed files to remove."
    }
}

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

# Helper function to process extracted ZIP files
function Process-ExtractedZip {
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
        Log-Debug "Detected single folder in extraction: $($extractedItems[0].Name)"
        
        # Use the contents of the single folder for the manifest and copying
        $newManifest = Get-FileManifest -Folder $singleFolder
        
        if (Test-Path (Join-Path $OutputFolder ".downloaded.json")) {
            Remove-ManagedFiles -OutputFolder $OutputFolder
        }
        
        # Copy the contents of the single folder directly to the output folder
        Copy-Item -Path (Join-Path $singleFolder "*") -Destination $OutputFolder -Recurse -Force
        Log-Debug "Copied contents of single folder directly to output folder: $OutputFolder"
    }
    else {
        # Original behavior for multiple files/folders
        $newManifest = Get-FileManifest -Folder $tempExtract
        
        if (Test-Path (Join-Path $OutputFolder ".downloaded.json")) {
            Remove-ManagedFiles -OutputFolder $OutputFolder
        }
        
        Copy-Item -Path (Join-Path $tempExtract "*") -Destination $OutputFolder -Recurse -Force
        Log-Debug "Copied extracted files to output folder: $OutputFolder"
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
    
    # First check if the tools directory exists
    if (-not [System.IO.Directory]::Exists($ToolsDirectory)) {
        Log-Error "Tools directory '$ToolsDirectory' does not exist. Cannot create output folder for $($ToolConfig.Name)."
        return $null
    }
    
    try {
        if (-not [string]::IsNullOrEmpty($ToolConfig.OutputFolder)) {
            $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $ToolConfig.OutputFolder $ToolConfig.Name)
        }
        else {
            $outputFolder = Join-Path -Path $ToolsDirectory -ChildPath $ToolConfig.Name
        }
        
        if (-not (Test-Path -Path $outputFolder)) {
            New-Item -Path $outputFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Log-Debug "Created output folder: $outputFolder"
        }
        
        return $outputFolder
    }
    catch {
        Log-Error "Failed to create output folder for $($ToolConfig.Name). Exception: $_"
        return $null
    }
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

# -----------------------------------------------
# Function: Download Specific File Tool
# -----------------------------------------------
function Download-SpecificFileTool {
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
        Log-Error "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
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
            
            Process-ExtractedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $fileUrl | Out-Null
        }
        else {
            Process-ZipFileNoExtract -ZipUrl $fileUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Headers $headers | Out-Null
        }
    }
    else {
        Process-NonZipFile -FileUrl $fileUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Headers $headers | Out-Null
    }
}

# -----------------------------------------------
# Function: Download Branch Zip Tool
# -----------------------------------------------
function Download-BranchZipTool {
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
    $branch = Get-DefaultValue -Tool $ToolConfig -Parameter "Branch" -DefaultValue "master"
    
    $zipUrl = "$($ToolConfig.RepoUrl)/archive/refs/heads/$branch.zip"
    Log-Info "Downloading branch zip for $($ToolConfig.Name)..."
    
    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    if ($null -eq $outputFolder) {
        Log-Error "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
        return
    }
    
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
        
        Process-ExtractedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $zipUrl -Version $branch | Out-Null
    }
    else {
        Process-ZipFileNoExtract -ZipUrl $zipUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Version $branch -Headers $headers | Out-Null
    }
}

# -----------------------------------------------
# Function: Download Latest Release Tool
# -----------------------------------------------
function Download-LatestReleaseTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "Name")) { return }
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "RepoUrl")) { return }
    
    # Define asset patterns if not provided
    $AssetPatterns = @{
        "win64" = "(?i)(win64|windows[-_]?64|x64|amd64|64[-_]?bit)"
        "win32" = "(?i)(win32|windows[-_]?32|x86|386|32[-_]?bit)"
        "linux64" = "(?i)(linux[-_]?64|linux[-_]?amd64)"
        "linux32" = "(?i)(linux[-_]?32|linux[-_]?386)"
        "macos64" = "(?i)(macos[-_]?64|darwin[-_]?64|osx[-_]?64)"
        "macos32" = "(?i)(macos[-_]?32|darwin[-_]?32|osx[-_]?32)"
        "arm64" = "(?i)(arm64|aarch64)"
        "arm32" = "(?i)(arm32|armv7)"
    }
    
    # Handle optional parameters with defaults
    $extract = Get-DefaultValue -Tool $ToolConfig -Parameter "Extract" -DefaultValue $true
    
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
        if ($null -eq $outputFolder) {
            Log-Error "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
            return
        }
        
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
                
                Process-ExtractedZip -Staging $staging -OutputFolder $outputFolder -ToolConfig $ToolConfig -DownloadUrl $downloadUrl -Version $releaseInfo.tag_name | Out-Null
            }
            else {
                Process-ZipFileNoExtract -ZipUrl $downloadUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Version $releaseInfo.tag_name -Headers $headers | Out-Null
            }
        }
        else {
            Process-NonZipFile -FileUrl $downloadUrl -OutputFolder $outputFolder -ToolConfig $ToolConfig -Version $releaseInfo.tag_name -Headers $headers | Out-Null
        }
    }
    else {
        Log-Warning "No matching asset found for $($ToolConfig.Name)."
    }
}

# -----------------------------------------------
# Function: Download Git Clone Tool
# -----------------------------------------------
function Download-GitCloneTool {
    param (
        [Parameter(Mandatory=$true)]$ToolConfig,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = ""
    )
    
    # Validate required parameters
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "Name")) { return }
    if (-not (Test-RequiredParameter -Tool $ToolConfig -Parameter "RepoUrl")) { return }
    
    # Handle optional parameters with defaults
    $branch = Get-DefaultValue -Tool $ToolConfig -Parameter "Branch" -DefaultValue "master"
    
    $outputFolder = Initialize-OutputFolder -ToolConfig $ToolConfig -ToolsDirectory $ToolsDirectory
    if ($null -eq $outputFolder) {
        Log-Error "Cannot process tool $($ToolConfig.Name) due to output folder initialization failure."
        return
    }
    
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
# Dispatcher: Loop Through Tools and Process
# -----------------------------------------------
# First check if the tools directory exists
if (-not [System.IO.Directory]::Exists($ToolsDirectory)) {
    Log-Error "Tools directory '$ToolsDirectory' does not exist. Cannot process any tools."
    exit 1
}

foreach ($tool in $tools) {
    try {
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
                        Log-Debug "Update: Removing previous files for $($tool.Name)."
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
                        Log-Debug "Update: Removing previous files for $($tool.Name)."
                        Remove-ManagedFiles -OutputFolder $toolOutputFolder
                    }
                    else {
                        Log-Debug "Update: No marker file found for $($tool.Name); preserving user files."
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
                Download-LatestReleaseTool -ToolConfig $tool -ToolsDirectory $ToolsDirectory -GitHubPAT $GitHubPAT
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
    catch {
        Log-Error "Failed to process tool $($tool.Name). Exception: $_"
        continue
    }
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

.PARAMETER Log
    Enable logging to a file. When specified, a log file will be automatically created in the tools directory
    with a timestamp in the filename.

.PARAMETER GitHubPAT
    GitHub Personal Access Token to use for API requests to avoid rate limiting.

.PARAMETER PromptForPAT
    Prompt for GitHub Personal Access Token securely (token will not be visible or stored in command history)

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
    PS> .\ToolFetcher.ps1 -Log
    
    Runs with logging enabled and saves all output to a timestamped log file in the tools directory.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -GitHubPAT "ghp_1234567890abcdef"
    
    Uses a GitHub Personal Access Token to avoid API rate limiting when downloading from GitHub.
    Note: This method exposes your token in command history and process listings.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -ToolsFile "https://raw.githubusercontent.com/kev365/ToolFetcher/main/tools.yaml"
    
    Uses a remote YAML configuration file instead of a local one.

.EXAMPLE
    PS> .\ToolFetcher.ps1 -PromptForPAT
    
    Prompts for a GitHub Personal Access Token securely. The token will not be visible when typing
    and will not be stored in command history.

.NOTES
    Author: Kevin Stokes
    Version: $script:Version
    
    Requirements:
    - PowerShell 5.1 or higher
    - Internet connection
    - PowerShell-yaml module (will be installed if missing)
#>

