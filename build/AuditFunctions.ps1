#Requires -Version 7
# Network-free logic for build/Test-ToolDefinitions.ps1 (the upstream audit).
# Expects the product script (ToolFetcher.ps1 -SourceOnly: Select-ReleaseAsset, $script:AssetPatterns)
# and build/DevCommon.ps1 to be dot-sourced first. This file dot-sources nothing and makes no network calls.

# Owner and repo of a github.com URL; ignores a trailing slash, .git and any path after the repo segment.
function ConvertTo-GitHubRepoRef {
    param ([Parameter(Mandatory)][AllowEmptyString()][string]$Url)
    $m = [regex]::Match($Url, '^https?://(?:www\.)?github\.com/([^/?#]+)/([^/?#]+)', 'IgnoreCase')
    if (-not $m.Success) { return $null }
    $repo = $m.Groups[2].Value -replace '\.git$', ''
    if ([string]::IsNullOrEmpty($repo)) { return $null }
    return [pscustomobject]@{ Owner = $m.Groups[1].Value; Repo = $repo }
}

# Lowercase identity of what an entry downloads, so entries that differ only by Name, trailing
# slash or .git collapse into one audit probe.
function Get-ToolEntryKey {
    param ([Parameter(Mandatory)]$Tool)
    $repoUrl = ([string]$Tool.RepoUrl).Trim().TrimEnd('/')
    $repoUrl = ($repoUrl -replace '\.git$', '').TrimEnd('/')
    $parts = @($repoUrl, [string]$Tool.DownloadMethod, [string]$Tool.Branch, [string]$Tool.DownloadName,
        [string]$Tool.AssetFilename, [string]$Tool.AssetType, [string]$Tool.SpecificFilePath)
    return ($parts -join '|').ToLowerInvariant()
}

# One entry per distinct key, in order of first appearance, each with Sources = "<file>:<Name>" for
# every definition that shares it. The file comes from the entry's SourceFile property when present.
function Get-UniqueToolEntries {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Returns the collection of unique entries; the plural name is the Task 10 contract')]
    param ([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tools)
    $entries = [ordered]@{}
    $sources = @{}
    foreach ($tool in $Tools) {
        $key = Get-ToolEntryKey -Tool $tool
        $file = if ($tool.SourceFile) { [string]$tool.SourceFile } else { '' }
        $label = "${file}:$($tool.Name)"
        if (-not $entries.Contains($key)) {
            if ($tool -is [System.Collections.IDictionary]) {
                $copy = [ordered]@{}
                foreach ($k in $tool.Keys) { $copy[$k] = $tool[$k] }
            }
            else {
                $copy = [pscustomobject]@{}
                foreach ($p in $tool.PSObject.Properties) { $copy | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
            }
            $entries[$key] = $copy
            $sources[$key] = [System.Collections.Generic.List[string]]::new()
        }
        if (-not $sources[$key].Contains($label)) { $sources[$key].Add($label) }
    }
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $entries.Keys) {
        $entry = $entries[$key]
        if ($entry -is [System.Collections.IDictionary]) { $entry['Sources'] = $sources[$key].ToArray() }
        else { $entry | Add-Member -NotePropertyName Sources -NotePropertyValue $sources[$key].ToArray() -Force }
        $result.Add($entry)
    }
    # The leading comma keeps a single entry an array for the caller.
    return , $result.ToArray()
}

# Runs the product's asset selection over names only. Selected is the asset the downloader would take;
# Ambiguous means more than one asset qualifies; SignatureFirst means the pick is a signature or checksum file.
function Get-AuditSelection {
    param (
        [Parameter(Mandatory)]$Tool,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AssetNames
    )
    $assets = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $AssetNames) {
        $assets.Add([pscustomobject]@{ name = $name; browser_download_url = "https://example.invalid/$name" })
    }
    $found = Select-ReleaseAsset -ToolConfig $Tool -Assets $assets.ToArray() -All
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($asset in $found) {
        if ($null -ne $asset) { $names.Add([string]$asset.name) }
    }
    $selected = $null
    if ($names.Count -gt 0) { $selected = $names[0] }
    return [pscustomobject]@{
        Matches        = $names.ToArray()
        Selected       = $selected
        Ambiguous      = ($names.Count -gt 1)
        SignatureFirst = ($null -ne $selected -and $selected -match '\.(asc|sig|sha256)$')
    }
}

# The version string embedded in the last two path segments of a URL, or $null.
function Test-VersionLockedUrl {
    param ([Parameter(Mandatory)][string]$Url)
    $path = $Url
    $uri = $null
    if ([uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri)) { $path = $uri.AbsolutePath }
    $segments = @($path -split '/' | Where-Object { $_ })
    $tail = $segments | Select-Object -Last 2
    foreach ($segment in $tail) {
        $m = [regex]::Match([System.Uri]::UnescapeDataString($segment), '\d+\.\d+(\.\d+)*')
        if ($m.Success) { return $m.Value }
    }
    return $null
}

# Folds one probe record into ok | warn | broken | skipped | transient. Precedence: skipped, transient,
# broken, warn, ok. A record is a hashtable or object; absent fields read as $null (falsy). Beyond the
# fields listed in the plan, DownloadMethod is read to apply the latestRelease-without-Selected rule.
function Get-AuditStatus {
    param ([Parameter(Mandatory)]$Record)
    if ($Record.SkipDownload) { return 'skipped' }
    if ($Record.Transient) { return 'transient' }
    $isLatest = ([string]$Record.DownloadMethod) -eq 'latestRelease'
    if ($Record.RepoMissing -or $Record.BranchMissing -or
        ($isLatest -and -not $Record.Selected) -or
        $Record.SignatureFirst -or
        ($null -ne $Record.HttpStatus -and [int]$Record.HttpStatus -ge 400) -or
        ($Record.ExpectBinary -and [string]$Record.ContentType -like 'text/html*')) {
        return 'broken'
    }
    if ($Record.Moved -or $Record.Archived -or $Record.Ambiguous -or $Record.VersionLocked) { return 'warn' }
    return 'ok'
}

# Trips on the first rate-limited response so callers stop calling GitHub and mark records Transient.
function New-RateLimitGate {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory object only; nothing is changed')]
    param ()
    $gate = [pscustomobject]@{ Tripped = $false }
    $gate | Add-Member -MemberType ScriptMethod -Name Observe -Value {
        param($Info)
        if ($null -ne $Info -and $Info.RateLimited) { $this.Tripped = $true }
    }
    return $gate
}
