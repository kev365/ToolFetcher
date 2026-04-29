# =====================================================
# ToolFetcherUI - Interactive TUI for ToolFetcher
#
# Loaded only when ToolFetcher.ps1 is invoked with -Interactive.
# Requires PowerShell 7+ and Microsoft.PowerShell.ConsoleGuiTools.
#
# Public entry point: Show-ToolFetcherTUI
# =====================================================

<#
.SYNOPSIS
Builds an enriched view over the merged tools list with local/remote
version status, shows it in an interactive multi-select grid, and
returns the user's selection so the engine can download them.

.DESCRIPTION
Status icons:
  ✓  up-to-date      (marker version matches upstream)
  ⬇  update available (marker exists but differs from upstream)
  ✗  not downloaded  (no marker)
  ⏸  placeholder     (RepoUrl + DownloadMethod both empty)
  ?  unknown         (status check skipped or failed)

The remote-version lookup runs in parallel runspaces (PS 7+ only).
Without a PAT, GitHub's unauthenticated rate limit (60/hr) will be
hit if many latestRelease/gitClone tools are checked - the TUI
reports rate-limit failures and shows '?' for affected entries.

The function returns nothing; it invokes Invoke-ToolWork on the
selected tools directly via Phase 7's parallel/sequential dispatcher.

.PARAMETER Tools
Already-merged tools array (from $config.tools after defaults applied).

.PARAMETER ToolsDirectory
Resolved tools directory.

.PARAMETER GitHubPAT
Optional PAT for higher rate limits during the status check and
during downloads.

.PARAMETER ThrottleLimit
Max concurrent runspaces for both the status check and the download.
#>
function Show-ToolFetcherTUI {
    param (
        [Parameter(Mandatory=$true)][array]$Tools,
        [Parameter(Mandatory=$true)][string]$ToolsDirectory,
        [Parameter(Mandatory=$false)][string]$GitHubPAT = "",
        [Parameter(Mandatory=$false)][int]$ThrottleLimit = 4
    )

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-LogError "-Interactive requires PowerShell 7+ (you're on $($PSVersionTable.PSVersion))."
        return
    }

    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.ConsoleGuiTools)) {
        Write-LogInfo "The 'Microsoft.PowerShell.ConsoleGuiTools' module is required for -Interactive."
        $choice = Read-Host "Would you like to install it now? (Y/N)"
        if ($choice -match '^(?i:Y(es)?)$') {
            try {
                Install-Module -Name Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser -Force -AllowClobber
            }
            catch {
                Write-LogError "Failed to install Microsoft.PowerShell.ConsoleGuiTools: $_"
                return
            }
        }
        else {
            Write-LogError "Cannot launch -Interactive without the module. Exiting."
            return
        }
    }
    Import-Module -Name Microsoft.PowerShell.ConsoleGuiTools -ErrorAction Stop

    Write-LogInfo "Building tool status view..."

    # --- Pass 1: enumerate, compute output paths, read markers (local versions) ---
    $rows = @()
    foreach ($tool in $Tools) {
        $isPlaceholder = [string]::IsNullOrWhiteSpace($tool.RepoUrl) -and [string]::IsNullOrWhiteSpace($tool.DownloadMethod)

        $outputFolder = if (-not [string]::IsNullOrEmpty($tool.OutputFolder)) {
            Join-Path -Path $ToolsDirectory -ChildPath (Join-Path $tool.OutputFolder $tool.Name)
        } else {
            Join-Path -Path $ToolsDirectory -ChildPath $tool.Name
        }

        $marker = if ($isPlaceholder) { $null } else { Get-ToolMarker -OutputFolder $outputFolder }
        $localVersion = if ($marker) {
            if ($marker.Version) { $marker.Version }
            elseif ($marker.CommitHash) { $marker.CommitHash.Substring(0, [Math]::Min(7, $marker.CommitHash.Length)) }
            else { "(unknown)" }
        } else { "" }

        $rows += [pscustomobject]@{
            Name         = $tool.Name
            Group        = $tool.OutputFolder
            Method       = if ($isPlaceholder) { "PLACEHOLDER" } else { $tool.DownloadMethod }
            Status       = if ($isPlaceholder) { "[paused] placeholder" } elseif ($marker) { "?" } else { "[no] not downloaded" }
            Local        = $localVersion
            Remote       = ""
            _Tool        = $tool
            _Placeholder = $isPlaceholder
        }
    }

    # --- Pass 2: parallel remote-version lookup ---
    $checkable = $rows | Where-Object { -not $_._Placeholder -and $_._Tool.RepoUrl -like "https://github.com/*" }
    $checkableCount = ($checkable | Measure-Object).Count
    if ($checkableCount -gt 0) {
        Write-LogInfo "Checking remote versions for $checkableCount tools (parallel)..."
        $scriptPath = $PSCommandPath
        if ([string]::IsNullOrEmpty($scriptPath)) {
            # When dot-sourced, find the engine path.
            $scriptPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "ToolFetcher.ps1"
        } else {
            # When called from ToolFetcher.ps1 itself, $PSCommandPath is the UI module.
            # Switch to the engine path.
            $scriptPath = Join-Path (Split-Path -Parent $scriptPath) "ToolFetcher.ps1"
        }

        $remoteVersions = $checkable | ForEach-Object -Parallel {
            . $using:scriptPath -SourceOnly
            $tool = $_._Tool
            $headers = Get-GitHubHeaders -GitHubPAT $using:GitHubPAT
            $remote = $null
            try {
                if ($tool.DownloadMethod -ieq "latestRelease") {
                    $apiRepoUrl = $tool.RepoUrl -replace "https://github.com/", "https://api.github.com/repos/"
                    $info = Invoke-RestMethod -Uri "$apiRepoUrl/releases/latest" -Headers $headers -ErrorAction Stop
                    $remote = $info.tag_name
                }
                elseif ($tool.DownloadMethod -ieq "gitClone" -or $tool.DownloadMethod -ieq "branchZip") {
                    if ($tool.RepoUrl -match "github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$") {
                        $owner = $Matches[1]; $repo = $Matches[2]
                        $branch = if ($tool.Branch) { $tool.Branch } else { (Get-GitHubDefaultBranch -RepoUrl $tool.RepoUrl -Headers $headers) }
                        if ($branch) {
                            $info = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/branches/$branch" -Headers $headers -ErrorAction Stop
                            $remote = $info.commit.sha.Substring(0, 7)
                        }
                    }
                }
            }
            catch { }

            [pscustomobject]@{ Name = $_.Name; Remote = $remote }
        } -ThrottleLimit $ThrottleLimit

        # Index remote versions by name for fast lookup
        $remoteByName = @{}
        foreach ($r in $remoteVersions) {
            if ($r.Remote) { $remoteByName[$r.Name] = $r.Remote }
        }

        # Apply remote info + final status
        foreach ($row in $rows) {
            if ($row._Placeholder) { continue }
            if ($remoteByName.ContainsKey($row.Name)) {
                $row.Remote = $remoteByName[$row.Name]
                if ([string]::IsNullOrWhiteSpace($row.Local)) {
                    $row.Status = "[no] not downloaded"
                }
                elseif ($row.Local -eq $row.Remote -or $row.Remote -like "$($row.Local)*" -or $row.Local -like "$($row.Remote)*") {
                    $row.Status = "[ok] up-to-date"
                }
                else {
                    $row.Status = "[update] available"
                }
            }
            else {
                # Lookup didn't return a version (network failure, rate limit, non-GitHub URL)
                if ([string]::IsNullOrWhiteSpace($row.Local)) {
                    $row.Status = "[no] not downloaded"
                }
                else {
                    $row.Status = "? (lookup failed)"
                }
            }
        }
    }

    # --- Pass 3: present picker ---
    Write-LogInfo "Launching interactive picker (filter with /, multi-select with Space, confirm with Enter)..."
    $display = $rows | Select-Object Status, Name, Group, Method, Local, Remote
    $picked = $display | Out-ConsoleGridView -OutputMode Multiple -Title "ToolFetcher - select tools to download"

    if (-not $picked -or $picked.Count -eq 0) {
        Write-LogInfo "No tools selected. Exiting."
        return
    }

    # Map picked rows back to original tool configs by Name.
    $pickedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $picked) { [void]$pickedNames.Add($p.Name) }

    $selectedTools = $rows | Where-Object { $pickedNames.Contains($_.Name) -and -not $_._Placeholder } | ForEach-Object { $_._Tool }
    Write-LogInfo "Selected $($selectedTools.Count) tool(s) for download."

    # --- Pass 4: dispatch ---
    if (-not (Test-Path $ToolsDirectory)) {
        New-Item -ItemType Directory -Path $ToolsDirectory -Force | Out-Null
    }

    $logFileSnapshot    = $script:LogFile
    $logEnabledSnapshot = $script:LoggingEnabled
    $enginePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "ToolFetcher.ps1"

    $selectedTools | ForEach-Object -Parallel {
        . $using:enginePath -SourceOnly
        $script:LogFile        = $using:logFileSnapshot
        $script:LoggingEnabled = $using:logEnabledSnapshot

        Invoke-ToolWork -Tool $_ `
                        -ToolsDirectory $using:ToolsDirectory `
                        -GitHubPAT $using:GitHubPAT
    } -ThrottleLimit $ThrottleLimit

    Write-LogInfo "Interactive session complete."
}
