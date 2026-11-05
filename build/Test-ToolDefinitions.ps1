#Requires -Version 7.4
<#
.SYNOPSIS
    Audits every tool definition against its upstream and reports what is broken, moved, archived,
    ambiguous or out of date.

.DESCRIPTION
    Loads tools.yaml and every tool_groups/*.yaml except _tool_template.yaml (or the files given with
    -ToolsFile) through ToolFetcher's own loader and validator (ToolFetcher.ps1 -SourceOnly), folds entries
    that download the same thing into one (build/AuditFunctions.ps1, Get-UniqueToolEntries) and probes
    each unique entry once:

      latestRelease        the repository, then its latest release; the entry's selector is applied to the
                           asset names exactly as ToolFetcher applies it (Select-ReleaseAsset).
      branchZip, gitClone  the repository, then the branch (the entry's Branch, else the default branch).
      specificFile         the repository when the URL is on github.com, then a ranged GET (Range:
                           bytes=0-0, up to 10 redirects, ToolFetcher's User-Agent) of the URL ToolFetcher
                           would download. HEAD is never used: download.ericzimmermanstools.com answers
                           HEAD with 404. ExifTool on SourceForge is also compared with exiftool.org/ver.txt.
      placeholder          no RepoUrl: listed as skipped and not probed. A RepoUrl but no DownloadMethod:
                           the URL is probed and the entry is listed as skipped.

    Status per entry (rules in build/AuditFunctions.ps1, Get-AuditStatus):
      broken     repository, branch or asset missing; a selector that matches nothing; a signature or
                 checksum file picked first; HTTP 400 or above; an HTML page where a binary was expected.
      warn       repository moved or renamed; archived; more than one asset matches; a version-locked URL;
                 a redirect that does not resolve (still 3xx after 10 redirects, a redirect loop, or an
                 HTTPS-to-HTTP downgrade), which is permanent and therefore not transient.
      transient  network error, HTTP 5xx or 429 after a retry, or the GitHub rate limit; never fails the run.
      skipped    SkipDownload: true in every file that defines the entry, or a placeholder; never fails the run.
      ok         none of the above.

    One rate-limit gate covers every GitHub API call: after the first rate-limited answer no further
    GitHub calls are made and the remaining GitHub-backed entries are reported as transient.

    Output: a console table sorted broken, warn, transient, ok, skipped; with -OutFile a JSON report;
    with -PassThru the records on the pipeline. The exit code is 1 when any record is broken, else 0.

    Record fields: Name, Sources ("<file>:<Name>" for every definition folded into the entry), Method,
    RepoUrl, Status, Detail, Latest (release tag), Published (release date), Selected (asset ToolFetcher
    would take), Matches (every qualifying asset), FullName (owner/repo as GitHub reports it), Archived,
    LastCommit (branch head commit date, else the repository's last push), HttpStatus, FinalUrl (after
    redirects, query string removed), Length, LastModified, ContentType, VersionLocked (version found in
    the URL), Transient. Dates are UTC ISO 8601.

.PARAMETER ToolsFile
    One or more tool definition files (local paths; relative paths are resolved against the current
    location; a comma-separated list in one value is split). Default: tools.yaml plus every
    tool_groups/*.yaml except _tool_template.yaml.

.PARAMETER GitHubPAT
    Token for the GitHub API. Precedence: -GitHubPAT, then $env:GH_TOKEN, then $env:GITHUB_TOKEN; without
    any of them the audit runs anonymously (60 API requests per hour) and warns. The token is sent only in
    the GitHub API request headers built by Get-GitHubHeaders, and to ToolFetcher.ps1 under -Download. It is
    never written to the console, the JSON report or a log. Direct URL probes do not send it.

.PARAMETER OutFile
    Writes the report as UTF-8 JSON: Generated, Authenticated, ToolsFiles, Records and Downloads.

.PARAMETER Download
    LOCAL, MANUAL USE ONLY; never run it from GitHub Actions. After the static audit, runs ToolFetcher.ps1
    under pwsh once per tools file with -ToolsFile <file> -ToolsDirectory
    <temp>\ToolFetcherAudit_<pid>\<file name without extension> -Log -GitHubPAT <token>, and appends each
    run's 'Run summary' line and its failed lines to the console and to the report under Downloads.
    For the shipped definitions it moves several gigabytes; the downloaded tools and the ToolFetcher logs
    stay in that folder for inspection, so delete it afterwards. It is not offered from Actions because
    ToolFetcher.ps1 validates its token against GET /user, which the runner's GITHUB_TOKEN cannot call,
    and an anonymous run would exceed the 60-per-hour limit.

.PARAMETER PassThru
    Emits the records to the pipeline before the script exits, so a caller using & receives both the
    records and $LASTEXITCODE.

.EXAMPLE
    pwsh -NoProfile -File build/Test-ToolDefinitions.ps1 -GitHubPAT (gh auth token)

    Audits the shipped definitions with the gh CLI's token.

.EXAMPLE
    pwsh -NoProfile -File build/Test-ToolDefinitions.ps1 -ToolsFile tests/fixtures/audit-regressions.yaml -GitHubPAT (gh auth token) -OutFile $env:TEMP\audit.json

    Audits the regression fixture (exit code 1: its entries are broken on purpose) and writes the JSON report.

.EXAMPLE
    pwsh -NoProfile -File build/Test-ToolDefinitions.ps1 -GitHubPAT (gh auth token) -Download

    Local end-to-end check: the static audit, then a real ToolFetcher download run per tools file.

.NOTES
    Requires PowerShell 7.4 or later: the direct URL probes pass Invoke-WebRequest -OperationTimeoutSeconds,
    which 7.0 to 7.3 do not have (every probe would fail to bind and come back transient).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Console UI: headings, summary and download lines for a developer script')]
[CmdletBinding()]
param(
    [string[]]$ToolsFile = @(),
    [string]$GitHubPAT = '',
    [string]$OutFile = '',
    [switch]$Download,
    [switch]$PassThru
)

# Dot-sourcing ToolFetcher.ps1 binds its own parameters ($ToolsFile, $GitHubPAT, ...) in this scope, so
# everything this script was given is captured here and the parameter variables are not read again.
$requestedFiles = @($ToolsFile)
$token = ''
foreach ($candidate in @($GitHubPAT, $env:GH_TOKEN, $env:GITHUB_TOKEN)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate)) { $token = $candidate.Trim(); break }
}
$reportPath = ''
if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
    $reportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
}
$runDownloads = [bool]$Download
$emitRecords = [bool]$PassThru

. (Join-Path $PSScriptRoot 'DevCommon.ps1')
$repoRoot = Get-RepoRoot
$productScript = Join-Path $repoRoot 'ToolFetcher.ps1'
. $productScript -SourceOnly
. (Join-Path $PSScriptRoot 'AuditFunctions.ps1')
Import-PinnedYaml
# Sets $script:GitHubPAT so the product's Format-RedactedMessage scrubs the token; file logging stays off.
Set-ToolFetcherRunState -State @{ GitHubPAT = $token; LoggingEnabled = $false; VerboseOutput = $false; TraceOutput = $false; LogFile = $null; LogMutexName = $null }

$script:AuditBinaryExtensions = @('.zip', '.7z', '.exe', '.msi', '.gz', '.tgz', '.tar', '.bz2', '.xz', '.rar', '.cab', '.dll', '.jar')
$script:AuditNotQueried = 'not queried: the GitHub API rate limit was reached earlier in this run'
$script:AuditUnauthorized = $false

# Scrubs the token (the literal value and token-shaped strings) from text bound for the console or the report.
function Protect-AuditText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    return (Format-RedactedMessage -Text $Text)
}

function ConvertTo-IsoDate {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    $format = 'yyyy-MM-ddTHH:mm:ssZ'
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString($format, $culture) }
    if ($Value -is [System.DateTimeOffset]) { return $Value.UtcDateTime.ToString($format, $culture) }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $parsed = [System.DateTimeOffset]::MinValue
    if ([System.DateTimeOffset]::TryParse($text, $culture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $parsed.UtcDateTime.ToString($format, $culture)
    }
    return $text
}

# The path relative to the repo root with forward slashes, or the file name for a file outside the repo.
function Get-SourceLabel {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
    $relative = [System.IO.Path]::GetRelativePath($Root, $Path)
    if ($relative.StartsWith('..') -or [System.IO.Path]::IsPathRooted($relative)) { return [System.IO.Path]::GetFileName($Path) }
    return $relative.Replace('\', '/')
}

function Test-BinaryName {
    param([AllowNull()][AllowEmptyString()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return ($script:AuditBinaryExtensions -contains [System.IO.Path]::GetExtension($Name).ToLowerInvariant())
}

function Format-NameList {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Names, [int]$Max = 6)
    if ($null -eq $Names -or $Names.Count -eq 0) { return 'none' }
    if ($Names.Count -le $Max) { return ($Names -join ', ') }
    return ('{0} (+{1} more)' -f (($Names | Select-Object -First $Max) -join ', '), ($Names.Count - $Max))
}

# The selector Select-ReleaseAsset applies, in its precedence order.
function Format-SelectorText {
    param([Parameter(Mandatory)]$Entry)
    foreach ($field in 'DownloadName', 'AssetFilename', 'AssetType') {
        $value = [string]$Entry[$field]
        if (-not [string]::IsNullOrEmpty($value)) { return "$field '$value'" }
    }
    return 'no selector'
}

# The URL ToolFetcher downloads for a specificFile entry (mirrors Resolve-ToolRemote).
function Get-SpecificFileUrl {
    param([Parameter(Mandatory)]$Entry)
    $repoUrl = [string]$Entry['RepoUrl']
    $filePath = [string]$Entry['SpecificFilePath']
    if ([string]::IsNullOrEmpty($filePath)) { return $repoUrl }
    if ($repoUrl -like 'https://github.com/*') {
        return (($repoUrl -replace 'https://github.com/', 'https://raw.githubusercontent.com/') + ($filePath -replace '^/raw', ''))
    }
    return "$repoUrl$filePath"
}

# One GitHub API GET through the product's Invoke-GitHubApi, behind the shared rate-limit gate. Never throws.
function Invoke-AuditGitHubApi {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)]$Gate,
        [string]$Description = 'audit request'
    )
    if ($Gate.Tripped) {
        return @{ Ok = $false; StatusCode = $null; Data = $null; RateLimited = $true; Moved = $false; Error = $script:AuditNotQueried }
    }
    try {
        # 6>$null: the product's console lines (redirect, retry and rate-limit messages) are reported in the table instead.
        $api = Invoke-GitHubApi -Uri $Uri -Headers $Headers -Description $Description 6>$null
    }
    catch {
        $api = @{ Ok = $false; StatusCode = $null; Data = $null; RateLimited = $false; Moved = $false; Error = $_.Exception.Message }
    }
    $Gate.Observe($api)
    # A rejected token makes every call fail as transient; remembered so the run warns instead of passing quietly.
    if ($api.StatusCode -eq 401) { $script:AuditUnauthorized = $true }
    return $api
}

function Test-GitHubNotFound {
    param([Parameter(Mandatory)]$Api)
    return ($null -ne $Api.StatusCode -and @(404, 410, 451) -contains [int]$Api.StatusCode)
}

function Get-GitHubRepoState {
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)]$Gate
    )
    $state = [pscustomobject]@{ Ok = $false; Missing = $false; Transient = $false; Moved = $false; FullName = $null; Archived = $null; PushedAt = $null; DefaultBranch = $null; Error = '' }
    $api = Invoke-AuditGitHubApi -Uri "https://api.github.com/repos/$Owner/$Repo" -Headers $Headers -Gate $Gate -Description "repository lookup for $Owner/$Repo"
    if ($api.Ok -and $null -ne $api.Data) {
        $state.Ok = $true
        $state.FullName = [string]$api.Data.full_name
        $state.Archived = [bool]$api.Data.archived
        $state.PushedAt = ConvertTo-IsoDate -Value $api.Data.pushed_at
        $state.DefaultBranch = [string]$api.Data.default_branch
        $renamed = -not [string]::IsNullOrEmpty($state.FullName) -and -not $state.FullName.Equals("$Owner/$Repo", [System.StringComparison]::OrdinalIgnoreCase)
        $state.Moved = [bool]$api.Moved -or $renamed
    }
    elseif (Test-GitHubNotFound -Api $api) {
        $state.Missing = $true
        $state.Error = "repository $Owner/$Repo not found (HTTP $($api.StatusCode))"
    }
    else {
        $state.Transient = $true
        $state.Error = "repository lookup failed: $($api.Error)"
    }
    return $state
}

function Get-LatestReleaseState {
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)]$Gate
    )
    $state = [pscustomobject]@{ Ok = $false; NoRelease = $false; Transient = $false; Tag = $null; Published = $null; AssetNames = [string[]]@(); Error = '' }
    $api = Invoke-AuditGitHubApi -Uri "https://api.github.com/repos/$Owner/$Repo/releases/latest" -Headers $Headers -Gate $Gate -Description "release lookup for $Owner/$Repo"
    if ($api.Ok -and $null -ne $api.Data) {
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($asset in $api.Data.assets) {
            if ($null -ne $asset) { $names.Add([string]$asset.name) }
        }
        $state.Ok = $true
        $state.Tag = [string]$api.Data.tag_name
        $state.Published = ConvertTo-IsoDate -Value $api.Data.published_at
        $state.AssetNames = $names.ToArray()
    }
    elseif (Test-GitHubNotFound -Api $api) {
        $state.NoRelease = $true
        $state.Error = 'no published release'
    }
    else {
        $state.Transient = $true
        $state.Error = "release lookup failed: $($api.Error)"
    }
    return $state
}

function Get-BranchState {
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)]$Gate
    )
    $state = [pscustomobject]@{ Ok = $false; Missing = $false; Transient = $false; LastCommit = $null; Error = '' }
    $api = Invoke-AuditGitHubApi -Uri "https://api.github.com/repos/$Owner/$Repo/branches/$Branch" -Headers $Headers -Gate $Gate -Description "branch lookup for $Owner/$Repo $Branch"
    if ($api.Ok -and $null -ne $api.Data) {
        $state.Ok = $true
        $state.LastCommit = ConvertTo-IsoDate -Value $api.Data.commit.commit.committer.date
    }
    elseif (Test-GitHubNotFound -Api $api) {
        $state.Missing = $true
        $state.Error = "branch '$Branch' not found (HTTP $($api.StatusCode))"
    }
    else {
        $state.Transient = $true
        $state.Error = "branch lookup failed: $($api.Error)"
    }
    return $state
}

# Ranged GET of a download URL with ToolFetcher's User-Agent and no token. A network error, 5xx or 429 is
# retried once and then reported as transient; a redirect that does not resolve is reported as Unresolved
# (warn). Never throws.
function Get-DirectUrlState {
    param([Parameter(Mandatory)][string]$Url)
    $state = [pscustomobject]@{ Responded = $false; Transient = $false; Unresolved = $false; HttpStatus = $null; FinalUrl = $null; ContentType = $null; Length = $null; LastModified = $null; Error = '' }
    $request = @{
        Uri                     = $Url
        UseBasicParsing         = $true
        Headers                 = @{ Range = 'bytes=0-0' }
        UserAgent               = $script:UserAgent
        MaximumRedirection      = 10
        SkipHttpErrorCheck      = $true
        TimeoutSec              = 30
        OperationTimeoutSeconds = 30
        ErrorAction             = 'Stop'
    }
    $response = $null
    $failure = ''
    $insecureRedirect = $false
    foreach ($attempt in 1, 2) {
        $response = $null
        $failure = ''
        try { $response = Invoke-WebRequest @request }
        catch {
            # PowerShell 7.4+ refuses an HTTPS-to-HTTP redirect with this error instead of returning the 3xx.
            if ([string]$_.FullyQualifiedErrorId -like 'InsecureRedirection*') { $insecureRedirect = $true }
            $failure = $_.Exception.Message
        }
        if ($insecureRedirect) { break }
        $retry = ($null -eq $response) -or ([int]$response.StatusCode -ge 500) -or ([int]$response.StatusCode -eq 429)
        if (-not $retry) { break }
        if ($attempt -eq 1) { Start-Sleep -Seconds 2 }
    }
    if ($insecureRedirect) {
        $state.Unresolved = $true
        $state.Error = 'redirect not resolved: HTTPS to HTTP downgrade refused'
        return $state
    }
    if ($null -eq $response) {
        $state.Transient = $true
        $state.Error = "request failed: $failure"
        return $state
    }
    $state.Responded = $true
    $status = [int]$response.StatusCode
    $state.HttpStatus = $status
    $finalUri = $null
    try { $finalUri = $response.BaseResponse.RequestMessage.RequestUri } catch { $finalUri = $null }
    if ($null -ne $finalUri) { $state.FinalUrl = $finalUri.GetLeftPart([System.UriPartial]::Path) }
    $state.ContentType = Get-ResponseHeader -Headers $response.Headers -Name 'Content-Type'
    $lastModified = Get-ResponseHeader -Headers $response.Headers -Name 'Last-Modified'
    if (-not [string]::IsNullOrEmpty($lastModified)) { $state.LastModified = ConvertTo-IsoDate -Value $lastModified }
    if ($status -ge 200 -and $status -lt 300) {
        $range = [regex]::Match([string](Get-ResponseHeader -Headers $response.Headers -Name 'Content-Range'), '/(\d+)\s*$')
        $contentLength = [string](Get-ResponseHeader -Headers $response.Headers -Name 'Content-Length')
        if ($range.Success) { $state.Length = [long]$range.Groups[1].Value }
        elseif ($status -eq 200 -and $contentLength -match '^\d+$') { $state.Length = [long]$contentLength }
    }
    if ($status -ge 500 -or $status -eq 429) {
        $state.Transient = $true
        $state.Error = "HTTP $status after a retry"
    }
    elseif ($status -ge 300 -and $status -lt 400) {
        # Still redirecting after the 10-hop limit (a long chain or a loop): permanent, so warn, not transient.
        $state.Unresolved = $true
        $state.Error = "HTTP $status, redirect not resolved after 10 redirects (redirect limit or loop)"
        $location = [string](Get-ResponseHeader -Headers $response.Headers -Name 'Location')
        if (-not [string]::IsNullOrEmpty($location)) { $state.Error += "; next Location $(($location -split '\?')[0])" }
    }
    return $state
}

# True when a URL is an ExifTool download on SourceForge (host compared without www.).
function Test-ExifToolUrl {
    param([Parameter(Mandatory)][string]$Url)
    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri)) { return $false }
    $hostName = $uri.Host.ToLowerInvariant()
    if ($hostName.StartsWith('www.')) { $hostName = $hostName.Substring(4) }
    return ($hostName -eq 'sourceforge.net' -and $uri.AbsolutePath -match '^/projects/exiftool(/|$)')
}

function Get-ExifToolCurrentVersion {
    $response = Invoke-WebRequest -Uri 'https://exiftool.org/ver.txt' -UseBasicParsing -UserAgent $script:UserAgent -TimeoutSec 30 -OperationTimeoutSeconds 30 -ErrorAction Stop
    $content = $response.Content
    if ($content -is [byte[]]) { $content = [System.Text.Encoding]::ASCII.GetString($content) }
    return ([string]$content).Trim()
}

# Repository state, looked up once per owner/repo for the whole run.
function Get-CachedRepoState {
    param(
        [Parameter(Mandatory)]$Ref,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)]$Gate,
        [Parameter(Mandatory)][hashtable]$Cache
    )
    $cacheKey = "$($Ref.Owner)/$($Ref.Repo)".ToLowerInvariant()
    if (-not $Cache.ContainsKey($cacheKey)) {
        $Cache[$cacheKey] = Get-GitHubRepoState -Owner $Ref.Owner -Repo $Ref.Repo -Headers $Headers -Gate $Gate
    }
    return $Cache[$cacheKey]
}

# Copies a direct-URL probe into the record and the status flags; returns the Detail text.
function Add-DirectUrlResult {
    param(
        [Parameter(Mandatory)]$Direct,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory)][hashtable]$Flags,
        [AllowNull()][System.Uri]$RequestUri
    )
    $Record.HttpStatus = $Direct.HttpStatus
    $Record.FinalUrl = $Direct.FinalUrl
    $Record.Length = $Direct.Length
    $Record.LastModified = $Direct.LastModified
    $Record.ContentType = $Direct.ContentType
    $Flags.HttpStatus = $Direct.HttpStatus
    $Flags.ContentType = $Direct.ContentType
    if ($Direct.Unresolved) {
        # Get-AuditStatus has no field for an unresolved redirect; Moved is its redirect flag and maps to warn.
        # The 3xx body's Content-Type says nothing about the download, so it must not trigger the HTML rule.
        $Flags.Moved = $true
        $Flags.ContentType = $null
        return $Direct.Error
    }
    if ($Direct.Transient) {
        $Flags.Transient = $true
        return "transient: $($Direct.Error)"
    }
    $text = "HTTP $($Direct.HttpStatus) $($Direct.ContentType)".TrimEnd()
    if ($null -ne $RequestUri -and -not [string]::IsNullOrEmpty($Direct.FinalUrl)) {
        $finalHost = ([System.Uri]$Direct.FinalUrl).Host
        if ($finalHost -ne $RequestUri.Host) { $text += " via $finalHost" }
    }
    if ($Flags.ExpectBinary -and [string]$Direct.ContentType -like 'text/html*') { $text += ', an HTML page where a binary was expected' }
    return $text
}

# Probes one unique entry and returns its record. Every failure inside becomes Transient with the message
# in Detail, so one bad probe never aborts the audit.
function Get-EntryAudit {
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)][bool]$Skipped,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)]$Gate,
        [Parameter(Mandatory)][hashtable]$RepoCache
    )
    $method = [string]$Entry['DownloadMethod']
    $repoUrl = ([string]$Entry['RepoUrl']).Trim()
    # The fields Get-AuditStatus folds into a status; DownloadMethod drives its latestRelease rule.
    $flags = @{
        SkipDownload = $Skipped; Transient = $false; RepoMissing = $false; BranchMissing = $false; Moved = $false
        Archived = $false; Selected = $null; Ambiguous = $false; SignatureFirst = $false; HttpStatus = $null
        ContentType = $null; ExpectBinary = $false; VersionLocked = $null; DownloadMethod = $method
    }
    $record = [ordered]@{
        Name = [string]$Entry['Name']; Sources = [string[]]@($Entry['Sources']); Method = $method; RepoUrl = $repoUrl
        Status = ''; Detail = ''; Latest = $null; Published = $null; Selected = $null; Matches = $null
        FullName = $null; Archived = $null; LastCommit = $null; HttpStatus = $null; FinalUrl = $null; Length = $null
        LastModified = $null; ContentType = $null; VersionLocked = $null; Transient = $false
    }
    $notes = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($method)) { $notes.Add('placeholder: no DownloadMethod') }
    elseif ($Skipped) { $notes.Add('SkipDownload') }

    try {
        $ref = ConvertTo-GitHubRepoRef -Url $repoUrl
        $repo = $null
        if ($null -ne $ref) {
            $repo = Get-CachedRepoState -Ref $ref -Headers $Headers -Gate $Gate -Cache $RepoCache
            if ($repo.Transient) {
                $flags.Transient = $true
                $notes.Add("transient: $($repo.Error)")
            }
            elseif ($repo.Missing) {
                $flags.RepoMissing = $true
                $notes.Add($repo.Error)
            }
            else {
                $record.FullName = $repo.FullName
                $record.Archived = $repo.Archived
                $record.LastCommit = $repo.PushedAt
                $flags.Archived = [bool]$repo.Archived
                $flags.Moved = [bool]$repo.Moved
                if ($repo.Moved) { $notes.Add("moved to $($repo.FullName)") }
                if ($repo.Archived) { $notes.Add('archived') }
            }
        }

        switch ($method) {
            'latestRelease' {
                if ($null -eq $ref) { $notes.Add('not a github.com repository URL') }
                elseif ($null -ne $repo -and $repo.Ok) {
                    $release = Get-LatestReleaseState -Owner $ref.Owner -Repo $ref.Repo -Headers $Headers -Gate $Gate
                    if ($release.Transient) {
                        $flags.Transient = $true
                        $notes.Add("transient: $($release.Error)")
                    }
                    elseif ($release.NoRelease) {
                        $record.Matches = [string[]]@()
                        $notes.Add($release.Error)
                    }
                    else {
                        $record.Latest = $release.Tag
                        $record.Published = $release.Published
                        $selection = Get-AuditSelection -Tool $Entry -AssetNames $release.AssetNames
                        $record.Selected = $selection.Selected
                        $record.Matches = [string[]]$selection.Matches
                        $flags.Selected = $selection.Selected
                        $flags.Ambiguous = $selection.Ambiguous
                        $flags.SignatureFirst = $selection.SignatureFirst
                        if ($null -eq $selection.Selected) {
                            $notes.Add("no asset matches $(Format-SelectorText -Entry $Entry) in $($release.Tag) (assets: $(Format-NameList -Names $release.AssetNames))")
                        }
                        elseif ($selection.SignatureFirst) {
                            $notes.Add("first match is a signature or checksum file: $($selection.Selected)")
                        }
                        elseif ($selection.Ambiguous) {
                            $notes.Add("$($selection.Matches.Count) assets match in $($release.Tag): $(Format-NameList -Names $selection.Matches)")
                        }
                        else {
                            $notes.Add("$($release.Tag): $($selection.Selected)")
                        }
                    }
                }
            }
            { $_ -eq 'branchZip' -or $_ -eq 'gitClone' } {
                $branch = [string]$Entry['Branch']
                if ($null -eq $ref) {
                    if ($method -eq 'branchZip' -and -not [string]::IsNullOrWhiteSpace($branch)) {
                        # ToolFetcher builds <RepoUrl>/archive/refs/heads/<Branch>.zip for any host.
                        $zipUrl = "$($repoUrl.TrimEnd('/'))/archive/refs/heads/$branch.zip"
                        $flags.ExpectBinary = $true
                        $zipUri = $null
                        $null = [System.Uri]::TryCreate($zipUrl, [System.UriKind]::Absolute, [ref]$zipUri)
                        $notes.Add((Add-DirectUrlResult -Direct (Get-DirectUrlState -Url $zipUrl) -Record $record -Flags $flags -RequestUri $zipUri))
                    }
                    else {
                        $flags.RepoMissing = $true
                        $notes.Add('not a github.com repository URL')
                    }
                }
                elseif ($null -ne $repo -and $repo.Ok) {
                    $branchLabel = "branch '$branch'"
                    if ([string]::IsNullOrWhiteSpace($branch)) {
                        $branch = $repo.DefaultBranch
                        $branchLabel = "default branch '$branch'"
                    }
                    $branchState = Get-BranchState -Owner $ref.Owner -Repo $ref.Repo -Branch $branch -Headers $Headers -Gate $Gate
                    if ($branchState.Transient) {
                        $flags.Transient = $true
                        $notes.Add("transient: $($branchState.Error)")
                    }
                    elseif ($branchState.Missing) {
                        $flags.BranchMissing = $true
                        $notes.Add($branchState.Error)
                    }
                    else {
                        $record.LastCommit = $branchState.LastCommit
                        $notes.Add("$branchLabel, last commit $($branchState.LastCommit)")
                    }
                    if ($branch -cne $repo.DefaultBranch) { $notes.Add("default branch is '$($repo.DefaultBranch)'") }
                }
            }
            default {
                # specificFile, and placeholders that carry a URL but no DownloadMethod.
                $url = Get-SpecificFileUrl -Entry $Entry
                $urlPath = $url
                $requestUri = $null
                if ([System.Uri]::TryCreate($url, [System.UriKind]::Absolute, [ref]$requestUri)) { $urlPath = $requestUri.AbsolutePath }
                $flags.ExpectBinary = (Test-BinaryName -Name $urlPath) -or (Test-BinaryName -Name ([string]$Entry['DownloadName']))
                $locked = Test-VersionLockedUrl -Url $url
                $record.VersionLocked = $locked
                $flags.VersionLocked = $locked
                $notes.Add((Add-DirectUrlResult -Direct (Get-DirectUrlState -Url $url) -Record $record -Flags $flags -RequestUri $requestUri))
                if ($null -ne $locked) { $notes.Add("version-locked $locked") }
                if (Test-ExifToolUrl -Url $url) {
                    try { $notes.Add("current $(Get-ExifToolCurrentVersion)") }
                    catch { $notes.Add("exiftool.org/ver.txt unavailable: $($_.Exception.Message)") }
                }
            }
        }
    }
    catch {
        $flags.Transient = $true
        $notes.Add("transient: probe failed: $($_.Exception.Message)")
    }

    $record.Transient = [bool]$flags.Transient
    $record.Status = Get-AuditStatus -Record $flags
    $record.Detail = Protect-AuditText -Text ($notes -join '; ')
    # Guarded: the [string] parameter would turn a $null FinalUrl into ''.
    if (-not [string]::IsNullOrEmpty($record.FinalUrl)) { $record.FinalUrl = Protect-AuditText -Text $record.FinalUrl }
    return [pscustomobject]$record
}

# Runs ToolFetcher.ps1 under pwsh for one tools file and keeps its summary and failure lines, token scrubbed.
function Invoke-DownloadRun {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ScriptPath,
        [AllowEmptyString()][string]$Token = ''
    )
    $toolsDirectory = Join-Path $Root ([System.IO.Path]::GetFileNameWithoutExtension($Path))
    $arguments = @('-ToolsFile', $Path, '-ToolsDirectory', $toolsDirectory, '-Log')
    if (-not [string]::IsNullOrEmpty($Token)) { $arguments += @('-GitHubPAT', $Token) }
    $run = Invoke-Edition -Edition pwsh -ScriptPath $ScriptPath -ArgumentList $arguments
    $summary = $null
    $logFile = $null
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($rawLine in $run.Output) {
        $line = Protect-AuditText -Text ([string]$rawLine)
        if ([string]::IsNullOrEmpty($line)) { continue }
        if ($line -match '^\s*Run summary') { $summary = $line.Trim() }
        elseif ($line -match '^\s+(failed|rate-limited)\s') { $failed.Add($line.Trim()) }
        $logMatch = [regex]::Match($line, 'Logging enabled to file: (.+)$')
        if ($logMatch.Success) { $logFile = $logMatch.Groups[1].Value.Trim() }
    }
    if ($null -eq $summary) { $summary = 'no Run summary line in the ToolFetcher output' }
    return [pscustomobject][ordered]@{
        ToolsFile      = $Label
        ToolsDirectory = $toolsDirectory
        ExitCode       = $run.ExitCode
        Summary        = $summary
        Failed         = $failed.ToArray()
        LogFile        = $logFile
        Seconds        = [math]::Round($run.Seconds, 1)
    }
}

# ---- Load and validate the tools files with ToolFetcher's own functions ----
if ($requestedFiles.Count -eq 0) {
    $requestedFiles = @(Join-Path $repoRoot 'tools.yaml')
    $requestedFiles += @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tool_groups') -Filter '*.yaml' -File |
            Where-Object { $_.Name -ne '_tool_template.yaml' } | Sort-Object Name | ForEach-Object { $_.FullName })
}
$toolsFiles = [System.Collections.Generic.List[object]]::new()
foreach ($item in $requestedFiles) {
    foreach ($part in ([string]$item).Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($part.Trim())
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Tools file not found: $part" }
        $toolsFiles.Add([pscustomobject]@{ Path = $fullPath; Label = (Get-SourceLabel -Path $fullPath -Root $repoRoot) })
    }
}

$defaultToolsFileUrl = 'https://raw.githubusercontent.com/kev365/ToolFetcher/refs/heads/main/tools.yaml'
$allTools = [System.Collections.Generic.List[object]]::new()
foreach ($file in $toolsFiles) {
    # Absolute path whose existence was checked above, so the product's fallback prompt is never reached.
    $content = Resolve-ToolsFileContent -Path $file.Path -DefaultUrl $defaultToolsFileUrl 6>$null
    if ($null -eq $content) { throw "Could not read $($file.Label)" }
    $yaml = ConvertFrom-Yaml -Yaml $content -ErrorAction Stop
    if ($null -eq $yaml -or $null -eq $yaml['tools']) { throw "$($file.Label) has no tools array" }
    # Group files carry no tooldirectory key, which Test-ToolConfiguration requires; the product builds its
    # merged configuration the same way.
    $config = @{ tooldirectory = ''; tools = @($yaml['tools']) }
    $validation = Test-ToolConfiguration -Config $config
    if (-not $validation.IsValid) {
        throw ("$($file.Label) is invalid:`n  " + ($validation.Errors -join "`n  "))
    }
    $config = Add-ConfigurationDefaults -Config $config
    foreach ($tool in $config.tools) {
        $tool['SourceFile'] = $file.Label
        $allTools.Add($tool)
    }
}

# An entry is live when at least one definition of it downloads (neither SkipDownload nor a placeholder).
$liveKeys = [System.Collections.Generic.HashSet[string]]::new()
$probeTools = [System.Collections.Generic.List[object]]::new()
$placeholders = [ordered]@{}
foreach ($tool in $allTools) {
    if ([string]::IsNullOrWhiteSpace([string]$tool['RepoUrl'])) {
        # Their download fields are all empty, so folding by them would merge unrelated placeholders:
        # one record per placeholder name instead.
        $nameKey = ([string]$tool['Name']).ToLowerInvariant()
        if (-not $placeholders.Contains($nameKey)) {
            $placeholders[$nameKey] = [pscustomobject]@{ Name = [string]$tool['Name']; Sources = [System.Collections.Generic.List[string]]::new() }
        }
        $label = "$($tool['SourceFile']):$($tool['Name'])"
        if (-not $placeholders[$nameKey].Sources.Contains($label)) { $placeholders[$nameKey].Sources.Add($label) }
        continue
    }
    $probeTools.Add($tool)
    if (-not $tool['SkipDownload'] -and -not (Test-PlaceholderEntry -Tool $tool)) { [void]$liveKeys.Add((Get-ToolEntryKey -Tool $tool)) }
}
$entries = Get-UniqueToolEntries -Tools $probeTools.ToArray()

$fileLabels = [string[]]@(foreach ($file in $toolsFiles) { $file.Label })
Write-Host "Auditing $($entries.Count + $placeholders.Count) unique entries ($($allTools.Count) definitions) from $($fileLabels -join ', ')"
if ([string]::IsNullOrEmpty($token)) {
    Write-Warning 'No GitHub token (-GitHubPAT, GH_TOKEN or GITHUB_TOKEN): GitHub API calls are anonymous and limited to 60 per hour; entries past the limit are reported as transient.'
}

# ---- Probe ----
$headers = Get-GitHubHeaders -GitHubPAT $token
$gate = New-RateLimitGate
$repoCache = @{}
$records = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $entries) {
    $skipped = -not $liveKeys.Contains((Get-ToolEntryKey -Tool $entry))
    $records.Add((Get-EntryAudit -Entry $entry -Skipped $skipped -Headers $headers -Gate $gate -RepoCache $repoCache))
}
foreach ($placeholder in $placeholders.Values) {
    $records.Add([pscustomobject][ordered]@{
            Name = $placeholder.Name; Sources = $placeholder.Sources.ToArray(); Method = ''; RepoUrl = ''
            Status = 'skipped'; Detail = 'placeholder: no RepoUrl, not probed'; Latest = $null; Published = $null
            Selected = $null; Matches = $null; FullName = $null; Archived = $null; LastCommit = $null; HttpStatus = $null
            FinalUrl = $null; Length = $null; LastModified = $null; ContentType = $null; VersionLocked = $null; Transient = $false
        })
}
if ($gate.Tripped) {
    Write-Warning 'GitHub API rate limit reached: the GitHub-backed entries after it were not queried and are reported as transient.'
}
if ($script:AuditUnauthorized) {
    Write-Warning 'GitHub answered 401 (bad credentials): the token is invalid or expired, and the GitHub-backed entries are reported as transient.'
}

# ---- Report ----
$rank = @{ broken = 0; warn = 1; transient = 2; ok = 3; skipped = 4 }
$records | Sort-Object @{ Expression = { $rank[$_.Status] } }, Name |
    Format-Table Status, Name, Method, Detail -AutoSize -Wrap | Out-Host
$counts = foreach ($status in 'broken', 'warn', 'transient', 'ok', 'skipped') {
    '{0} {1}' -f @($records | Where-Object { $_.Status -eq $status }).Count, $status
}
$brokenCount = @($records | Where-Object { $_.Status -eq 'broken' }).Count
$summaryColor = 'Green'
if ($brokenCount -gt 0) { $summaryColor = 'Red' }
Write-Host "$($records.Count) entries: $($counts -join ', ')" -ForegroundColor $summaryColor

$downloads = [System.Collections.Generic.List[object]]::new()
if ($runDownloads) {
    $downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ToolFetcherAudit_$PID"
    if ([string]::IsNullOrEmpty($token)) { Write-Warning 'No GitHub token: the ToolFetcher download runs are anonymous too.' }
    Write-Host ''
    Write-Host "Downloads (into $downloadRoot)" -ForegroundColor Cyan
    foreach ($file in $toolsFiles) {
        Write-Host "  $($file.Label): running ToolFetcher.ps1 ..."
        $run = Invoke-DownloadRun -Path $file.Path -Label $file.Label -Root $downloadRoot -ScriptPath $productScript -Token $token
        $downloads.Add($run)
        $runColor = 'Green'
        if ($run.ExitCode -ne 0) { $runColor = 'Yellow' }
        Write-Host "    exit $($run.ExitCode), $($run.Seconds) s: $($run.Summary)" -ForegroundColor $runColor
        foreach ($line in $run.Failed) { Write-Host "      $line" -ForegroundColor Yellow }
    }
    Write-Host "  Tools and ToolFetcher logs are left in $downloadRoot; delete the folder when done."
}

if (-not [string]::IsNullOrEmpty($reportPath)) {
    $report = [ordered]@{
        Generated     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        Authenticated = -not [string]::IsNullOrEmpty($token)
        ToolsFiles    = $fileLabels
        Records       = $records.ToArray()
        Downloads     = $downloads.ToArray()
    }
    $json = Protect-AuditText -Text ($report | ConvertTo-Json -Depth 6)
    $reportFolder = Split-Path -Parent $reportPath
    if (-not [string]::IsNullOrEmpty($reportFolder) -and -not (Test-Path -LiteralPath $reportFolder)) {
        $null = New-Item -ItemType Directory -Path $reportFolder -Force
    }
    [System.IO.File]::WriteAllText($reportPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote $reportPath"
}

if ($emitRecords) {
    foreach ($record in $records) { $record }
}
if ($brokenCount -gt 0) { exit 1 }
exit 0
