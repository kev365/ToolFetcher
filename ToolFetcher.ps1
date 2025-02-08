# =====================================================
# ToolFetcher
#
# A tool for fetching DFIR and other GitHub tools.
#
# Author: Kevin Stokes (https://www.linkedin.com/in/dfir-kev/)
# Version: 1.0.0
# License: MIT
# =====================================================

# =====================================================
# User Configurable Variables
# =====================================================

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
# Tools Configuration Array
# =====================================================
# Each tool is represented by a hashtable with these properties:
#
# Required:
#   Name           - A friendly name for the tool.
#   RepoUrl        - The URL of the GitHub repository or direct file URL.
#   DownloadMethod - How to download the tool. Valid values:
#                    • "gitClone"     – Clone the repository using Git.
#                    • "latestRelease"– Download the latest release asset via the GitHub API.
#                    • "branchZip"    – Download the branch ZIP archive (without a .git folder).
#                    • "specificFile" – Download a specific file.
#
# Optional properties (vary by DownloadMethod):
#
# • For "gitClone":
#      Branch         - The branch to clone.
#
# • For "latestRelease":
#      DownloadName   - (Optional) Exact asset name to filter by (overrides AssetType if provided).
#      AssetType      - (Optional) A key (e.g., "win64") mapping to a regex in $AssetPatterns.
#                       Used when DownloadName isn’t provided.
#      AssetFilename  - (Optional) Specify the asset name exactly.
#      Extract        - (Optional) Set to $false to disable extraction (default extracts ".zip" files).
#
# • For "branchZip":
#      Branch         - (Optional) The branch to download (defaults to "master" if omitted).
#      Extract        - (Optional) Set to $false to disable extraction.
#
# • For "specificFile":
#      SpecificFilePath - The relative path (e.g., starting with "/raw/...") to the file in the repo.
#
# Global for all methods:
#   OutputFolder   - (Optional) A custom subfolder (under $toolsFolder) to group this tool.
#                    Default output paths:
#                      • For gitClone, latestRelease, and branchZip:
#                          Join-Path($toolsFolder, $OutputFolder, $Name)
#                      • For specificFile:
#                          Join-Path($toolsFolder, $OutputFolder)
#                    If not provided:
#                      • gitClone/latestRelease/branchZip default to Join-Path($toolsFolder, $Name)
#                      • specificFile defaults to $toolsFolder.
#
# Additional flag:
#   skipdownload   - Set to $true to skip downloading this tool.
#
$tools = @(
    @{
        Name           = "SQLECmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/SQLECmd.zip" 	# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/SQLECmd.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/SQLECmd.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "Database"
    },
    @{
        Name           = "JLECmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/JLECmd.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/JLECmd.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/JLECmd.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "LNK-JMP"
    },
    @{
        Name           = "JumpListExplorer"
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/JumpListExplorer.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/JumpListExplorer.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "LNK-JMP"
    },
    @{
        Name           = "LECmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/LECmd.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/LECmd.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/LECmd.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "LNK-JMP"
    },
    @{
        Name           = "EZViewer"
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/EZViewer.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/EZViewer.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "MISC"
    },
    @{
        Name           = "hasher"
        RepoUrl        = "https://download.ericzimmermanstools.com/hasher.zip" # .Net4
        DownloadMethod = "specificFile"
		OutputFolder   = "MISC"
    },
    @{
        Name           = "iisGeolocate"
        # RepoUrl      = "https://download.ericzimmermanstools.com/iisGeolocate.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/iisGeolocate.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/iisGeolocate.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "MISC"
    },
    @{
        Name           = "TimeApp"
        RepoUrl        = "https://download.ericzimmermanstools.com/TimeApp.zip" # .Net4
        DownloadMethod = "specificFile"
		OutputFolder   = "MISC"
    },
    @{
        Name           = "TimelineExplorer"
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/TimelineExplorer.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/TimelineExplorer.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "MISC"
    },
    @{
        Name           = "BackstageParser"
        RepoUrl        = "https://github.com/ArsenalRecon/BackstageParser"
        DownloadMethod = "branchZip"
        Branch         = "master"
		OutputFolder   = "MSOffice"
		# skipdownload   = $true
    },
    @{
        Name           = "forensicsim"
        RepoUrl        = "https://github.com/lxndrblz/forensicsim"
        DownloadMethod = "latestRelease"
        DownloadName   = "forensicsim.zip"
		OutputFolder   = "MSOffice"
    },
    @{
        Name           = "LevelDBDumper"
        RepoUrl        = "https://github.com/mdawsonuk/LevelDBDumper"
        DownloadMethod = "latestRelease"
        DownloadName   = "LevelDBDumper.exe" # 64-bit
		OutputFolder   = "MSOffice"
    },
    @{
        Name           = "OneDriveExplorer"
        RepoUrl        = "https://github.com/Beercow/OneDriveExplorer"
        DownloadMethod = "latestRelease"
        DownloadName   = "ODE.zip"
		OutputFolder   = "MSOffice"
    },
    @{
        Name           = "INDXRipper"
        RepoUrl        = "https://github.com/harelsegev/INDXRipper"
        DownloadMethod = "latestRelease"
        DownloadName   = "INDXRipper-20231117-py3.12-amd64.zip"
		OutputFolder   = "NTFS"
    },
    @{
        Name           = "MFTECmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/MFTECmd.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/MFTECmd.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/MFTECmd.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "NTFS"
    },
    @{
        Name           = "MFTExplorer"
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/MFTExplorer.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/MFTExplorer.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "NTFS"
    },
    @{
        Name           = "RustyUsn"
        RepoUrl        = "https://github.com/forensicmatt/RustyUsn"
        DownloadMethod = "latestRelease"
        DownloadName   = "rusty_usn-v1.5.0-x86_64-pc-windows-msvc.zip"
		OutputFolder   = "NTFS"
    },
    @{
        Name           = "PECmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/PECmd.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/PECmd.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/PECmd.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "Prefetch"
    },
    @{
        Name           = "RBCmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/RBCmd.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/RBCmd.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/RBCmd.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "RecycleBin"
    },
    @{
        Name           = "AmcacheParser"
        # RepoUrl      = "https://download.ericzimmermanstools.com/AmcacheParser.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/AmcacheParser.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/AmcacheParser.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "WinRegistry"
    },
    @{
        Name           = "AppCompatCacheParser"
        # RepoUrl      = "https://download.ericzimmermanstools.com/AppCompatCacheParser.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/AppCompatCacheParser.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/AppCompatCacheParser.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "WinRegistry"
    },
    @{
        Name           = "RecentFileCacheParser"
        # RepoUrl      = "https://download.ericzimmermanstools.com/RecentFileCacheParser.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/RecentFileCacheParser.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/RecentFileCacheParser.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "WinRegistry"
    },
    @{
        Name           = "RECmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/RECmd.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/RECmd.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/RECmd.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "WinRegistry"
    },
    @{
        Name           = "RegistryExplorer"
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/RegistryExplorer.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/RegistryExplorer.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "WinRegistry"
    },
    @{
        Name           = "rla"
        # RepoUrl      = "https://download.ericzimmermanstools.com/rla.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/rla.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/rla.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "WinRegistry"
    },
    @{
        Name           = "SBECmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/SBECmd.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/SBECmd.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/SBECmd.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "WinRegistry"
    },
    @{
        Name           = "SDBExplorer"
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/SDBExplorer.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/SDBExplorer.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "WinRegistry"
    },
    @{
        Name           = "ShellBagsExplorer"
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/ShellBagsExplorer.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/ShellBagsExplorer.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "WinRegistry"
    },
    @{
        Name           = "KStrike"
        RepoUrl        = "https://github.com/brimorlabs/KStrike"
        DownloadMethod = "branchZip"
        Branch         = "master"
		OutputFolder   = "SUM-UAL"
    },
    @{
        Name           = "SumECmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/SumECmd.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/SumECmd.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/SumECmd.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "SUM-UAL"
    },
    @{
        Name           = "SumECmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/SumECmd.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/SumECmd.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/SumECmd.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "SUM-UAL"
    },
    @{
        Name           = "SEPparser_cmd"
        RepoUrl        = "https://github.com/Beercow/SEPparser"
        DownloadMethod = "latestRelease"
        DownloadName   = "SEPparser.exe"
		OutputFolder   = "SymantecLogs"
    },
    @{
        Name           = "SEPparser_gui"
        RepoUrl        = "https://github.com/Beercow/SEPparser"
        DownloadMethod = "latestRelease"
        DownloadName   = "SEPparser_GUI.exe"
		OutputFolder   = "SymantecLogs"
    },
    @{
        Name           = "VSCMount"
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/VSCMount.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/VSCMount.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "VSC"
    },
    @{
        Name           = "WxTCmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/WxTCmd.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/WxTCmd.zip" # .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/WxTCmd.zip" # .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "Win10Timeline"
    },
    @{
        Name           = "hindsight"
        RepoUrl        = "https://github.com/obsidianforensics/hindsight"
        DownloadMethod = "latestRelease"
        DownloadName   = "hindsight.exe"
		OutputFolder   = "WebHistory"
    },
    @{
        Name           = "hindsight_gui"
        RepoUrl        = "https://github.com/obsidianforensics/hindsight"
        DownloadMethod = "latestRelease"
        DownloadName   = "hindsight_gui.exe"
		OutputFolder   = "WebHistory"
    },
    @{
        Name           = "BitsParser"
        RepoUrl        = "https://github.com/fireeye/BitsParser"
        DownloadMethod = "branchZip"
        Branch         = "master"
		OutputFolder   = "WinBITS"
    },
    @{
        Name             = "DHParser"
        RepoUrl          = "https://github.com/jklepsercyber/defender-detectionhistory-parser"
        DownloadMethod   = "specificFile"
        SpecificFilePath = "/raw/refs/heads/main/dhparser.exe"
        DownloadName     = "dhparser.exe"
		OutputFolder     = "WinDefender"
    },
    @{
        Name           = "RegRipper3.0"
        RepoUrl        = "https://github.com/keydet89/RegRipper3.0"
        DownloadMethod = "branchZip"
        Branch         = "master"
		OutputFolder   = "WinRegistry"
    },
    @{
        Name           = "APT-Hunter"
        RepoUrl        = "https://github.com/ahmedkhlief/APT-Hunter"
        DownloadMethod = "latestRelease"
        DownloadName   = "APT-Hunter.zip"
        OutputFolder   = "WinEventlogs"
    },
    @{
        Name           = "chainsaw"
        RepoUrl        = "https://github.com/WithSecureLabs/chainsaw"
        DownloadMethod = "latestRelease"
        DownloadName   = "chainsaw_x86_64-pc-windows-msvc.zip"
        OutputFolder   = "WinEventlogs"
    },
    @{
        Name           = "EvtxECmd"
        # RepoUrl      = "https://download.ericzimmermanstools.com/EvtxECmd.zip" 		# .Net4
        RepoUrl        = "https://download.ericzimmermanstools.com/net6/EvtxECmd.zip" 	# .Net6
        # RepoUrl      = "https://download.ericzimmermanstools.com/net9/EvtxECmd.zip" 	# .Net9
        DownloadMethod = "specificFile"
		OutputFolder   = "WinEventlogs"
    },
    @{
        Name           = "hayabusa"
        RepoUrl        = "https://github.com/Yamato-Security/hayabusa"
        DownloadMethod = "latestRelease"
        AssetType      = "win64"
		OutputFolder   = "WinEventlogs"
    },
    @{
        Name           = "EvtxHussar"
        RepoUrl        = "https://github.com/yarox24/EvtxHussar"
        DownloadMethod = "latestRelease"
        AssetType      = "win64"
		OutputFolder   = "WinEventlogs"
    },
    @{
        Name           = "hayabusa-rules"
        RepoUrl        = "https://github.com/Yamato-Security/hayabusa-rules"
        DownloadMethod = "branchZip"
        Branch         = "main"
		OutputFolder   = "WinEventlogs"
    },
    @{
        Name           = "sidr"
        RepoUrl        = "https://github.com/strozfriedberg/sidr"
        DownloadMethod = "latestRelease"
        DownloadName   = "sidr.exe"
		OutputFolder   = "WinSearchIndex"
    },
    @{
        Name           = "wmi-parser"
        RepoUrl        = "https://github.com/woanware/wmi-parser"
        DownloadMethod = "latestRelease"
        DownloadName   = "wmi-parser.v0.0.2.zip"
		OutputFolder   = "WMI"
    },
    @{
        Name           = "XWFIM"
        RepoUrl        = "https://download.ericzimmermanstools.com/XWFIM.zip" # .Net4
        DownloadMethod = "specificFile"
		OutputFolder   = "XWays"
    },
    @{
        Name           = "Plist_Time_Dump"
        RepoUrl        = "https://github.com/kev365/plist_time_dump"
        DownloadMethod = "branchZip"
        Branch         = "master"
		OutputFolder   = "Apple"
		skipdownload   = $true
    }
)

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
