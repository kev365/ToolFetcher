#Requires -Version 7.4
<#
.SYNOPSIS
    Runs the ToolFetcher verification steps and prints a pass/fail table.

.DESCRIPTION
    Checks, in this order:
      parse      ToolFetcher.ps1 parses without errors.
      encoding   ToolFetcher.ps1 is ASCII, has no BOM and ends its lines with CRLF.
      analyzer   PSScriptAnalyzer 1.25.0 with PSScriptAnalyzerSettings.psd1 reports nothing for
                 ToolFetcher.ps1 or any build/*.ps1 (left out with -SkipAnalyzer).
      listtools  -ListTools exits 0 and prints 'Total Tools: N', N being the entry count of tools.yaml.
      groups     -ListTools -ToolsFile <file> exits 0 and prints the file's entry count, for every
                 tool_groups/*.yaml except _tool_template.yaml (under pwsh, or desktop when only
                 desktop is selected).
      dryrun     -DryRun -ToolsDirectory <temp folder> exits 0 and the folder does not exist afterwards.
      pester     (-Pester only) the product test suite, excluding the Build and Network tags.
      gitclean   git status --porcelain is the same at the end of the run as at the start.
    listtools, dryrun and pester run once per selected edition. The exit code is 0 only when every
    row passed.

.PARAMETER Edition
    pwsh (PowerShell 7), desktop (Windows PowerShell 5.1) or both (the default).

.PARAMETER SkipAnalyzer
    Leave out the analyzer row, which takes about a minute.

.PARAMETER Pester
    Also run the product Pester suite under each selected edition.

.PARAMETER OutJson
    Also write the rows to this file as a JSON array of { Name, Edition, Passed, Detail, Seconds }.
    A relative path is resolved against the current directory.

.EXAMPLE
    pwsh -NoProfile -File build/Invoke-Checks.ps1 -Pester

.EXAMPLE
    pwsh -NoProfile -File build/Invoke-Checks.ps1 -Edition pwsh -SkipAnalyzer -OutJson checks.json
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Console UI: progress and failure lines for a developer script')]
[CmdletBinding()]
param(
    [ValidateSet('pwsh', 'desktop', 'both')]
    [string]$Edition = 'both',
    [switch]$SkipAnalyzer,
    [switch]$Pester,
    [string]$OutJson = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DevCommon.ps1')

$script:AnalyzerVersion = '1.25.0'
$script:RepoRoot = Get-RepoRoot
$script:ProductScript = Join-Path $script:RepoRoot 'ToolFetcher.ps1'
$script:Rows = [System.Collections.Generic.List[object]]::new()

function ConvertTo-CheckRow {
    # The one row shape used for the table and the JSON file.
    param(
        [Parameter(Mandatory)]
        [ValidateSet('parse', 'encoding', 'analyzer', 'listtools', 'groups', 'dryrun', 'gitclean', 'pester')]
        [string]$Name,
        [Parameter(Mandatory)][ValidateSet('pwsh', 'desktop', 'n/a')][string]$Edition,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Detail,
        [Parameter(Mandatory)][System.Diagnostics.Stopwatch]$Watch
    )
    [pscustomobject]@{
        Name    = $Name
        Edition = $Edition
        Passed  = $Passed
        Detail  = $Detail
        Seconds = [math]::Round($Watch.Elapsed.TotalSeconds, 1)
    }
}

function Write-RunTail {
    # Shows the end of a child run's output below a failed check.
    param(
        [Parameter(Mandatory)][string]$Label,
        [AllowNull()][string[]]$Lines
    )
    Write-Host "     --- last lines of $Label ---" -ForegroundColor DarkGray
    foreach ($line in @($Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 20)) {
        Write-Host "     $line" -ForegroundColor DarkGray
    }
}

function Get-PrintedToolTotal {
    # The N of the last 'Total Tools: N' line, or $null when there is none.
    param([AllowNull()][string[]]$Lines)
    $total = $null
    foreach ($line in $Lines) {
        $m = [regex]::Match([string]$line, 'Total Tools:\s*(\d+)')
        if ($m.Success) { $total = [int]$m.Groups[1].Value }
    }
    return $total
}

function Get-ListingProblem {
    # $null when a -ListTools run exited 0 and printed the expected total, else what went wrong.
    param(
        [Parameter(Mandatory)][psobject]$Run,
        [Parameter(Mandatory)][int]$Expected,
        [Parameter(Mandatory)][string]$Source
    )
    $printed = Get-PrintedToolTotal -Lines $Run.Output
    if ($Run.ExitCode -ne 0) { return "exit code $($Run.ExitCode)" }
    if ($null -eq $printed) { return "no 'Total Tools: N' line in the output" }
    if ($printed -ne $Expected) { return "printed Total Tools: $printed but $Source has $Expected entries" }
    return $null
}

function Test-ScriptParse {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script:ProductScript, [ref]$null, [ref]$parseErrors) | Out-Null
    $count = @($parseErrors).Count
    if ($count -eq 0) {
        $detail = 'ToolFetcher.ps1 parses without errors'
    }
    else {
        $first = $parseErrors[0]
        $detail = '{0} parse error(s); first at line {1}: {2}' -f $count, $first.Extent.StartLineNumber, $first.Message
    }
    ConvertTo-CheckRow -Name parse -Edition 'n/a' -Passed ($count -eq 0) -Detail $detail -Watch $watch
}

function Test-ScriptEncoding {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $encoding = Test-TextEncoding -Path $script:ProductScript
    $problems = [System.Collections.Generic.List[string]]::new()
    if (-not $encoding.Ascii) { $problems.Add('non-ASCII bytes') }
    if ($encoding.Bom) { $problems.Add('UTF-8 BOM') }
    if ($encoding.LoneLf) { $problems.Add('lines ending in LF without CR') }
    elseif (-not $encoding.Crlf) { $problems.Add('no CRLF line endings') }
    if ($problems.Count -eq 0) { $detail = 'ASCII, no BOM, CRLF' } else { $detail = $problems -join '; ' }
    ConvertTo-CheckRow -Name encoding -Edition 'n/a' -Passed ($problems.Count -eq 0) -Detail $detail -Watch $watch
}

function Test-AnalyzerClean {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Import-Module PSScriptAnalyzer -RequiredVersion $script:AnalyzerVersion -ErrorAction Stop
    }
    catch {
        $detail = "PSScriptAnalyzer $($script:AnalyzerVersion) could not be imported: $($_.Exception.Message)"
        return (ConvertTo-CheckRow -Name analyzer -Edition 'n/a' -Passed $false -Detail $detail -Watch $watch)
    }
    $settings = Join-Path $script:RepoRoot 'PSScriptAnalyzerSettings.psd1'
    $files = [System.Collections.Generic.List[string]]::new()
    $files.Add($script:ProductScript)
    foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'build') -Filter '*.ps1' -File | Sort-Object Name)) {
        $files.Add($file.FullName)
    }
    $findings = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $files) {
        foreach ($record in (Invoke-ScriptAnalyzer -Path $file -Settings $settings)) {
            $where = '{0}:{1}' -f (Split-Path -Path $record.ScriptPath -Leaf), $record.Line
            $findings.Add("$where $($record.RuleName)")
            Write-Host "     $where $($record.RuleName): $($record.Message)" -ForegroundColor DarkGray
        }
    }
    if ($findings.Count -eq 0) {
        $detail = "0 findings in $($files.Count) files"
    }
    else {
        $detail = '{0} finding(s): {1}' -f $findings.Count, (($findings | Select-Object -First 3) -join ', ')
    }
    ConvertTo-CheckRow -Name analyzer -Edition 'n/a' -Passed ($findings.Count -eq 0) -Detail $detail -Watch $watch
}

function Test-ToolListing {
    param([Parameter(Mandatory)][ValidateSet('pwsh', 'desktop')][string]$Edition)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $expected = Get-ToolEntryCount -YamlPath (Join-Path $script:RepoRoot 'tools.yaml')
    $run = Invoke-Edition -Edition $Edition -ScriptPath $script:ProductScript -ArgumentList '-ListTools'
    $problem = Get-ListingProblem -Run $run -Expected $expected -Source 'tools.yaml'
    if ($null -eq $problem) {
        $detail = "Total Tools: $expected matches tools.yaml"
    }
    else {
        $detail = $problem
        Write-RunTail -Label "-ListTools ($Edition)" -Lines $run.Output
    }
    ConvertTo-CheckRow -Name listtools -Edition $Edition -Passed ($null -eq $problem) -Detail $detail -Watch $watch
}

function Test-GroupListing {
    param([Parameter(Mandatory)][ValidateSet('pwsh', 'desktop')][string]$Edition)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $groupFolder = Join-Path $script:RepoRoot 'tool_groups'
    $groups = @(Get-ChildItem -LiteralPath $groupFolder -Filter '*.yaml' -File |
        Where-Object { $_.Name -ne '_tool_template.yaml' } | Sort-Object Name)
    $failures = [System.Collections.Generic.List[string]]::new()
    foreach ($group in $groups) {
        $expected = Get-ToolEntryCount -YamlPath $group.FullName
        $run = Invoke-Edition -Edition $Edition -ScriptPath $script:ProductScript -ArgumentList '-ListTools', '-ToolsFile', $group.FullName
        $problem = Get-ListingProblem -Run $run -Expected $expected -Source $group.Name
        if ($null -ne $problem) {
            $failures.Add("$($group.Name): $problem")
            Write-RunTail -Label "-ListTools -ToolsFile $($group.Name) ($Edition)" -Lines $run.Output
        }
    }
    if ($groups.Count -eq 0) {
        $failures.Add("no group files in $groupFolder")
    }
    if ($failures.Count -eq 0) {
        $detail = "$($groups.Count) group files list their entry counts"
    }
    else {
        $detail = $failures -join '; '
    }
    ConvertTo-CheckRow -Name groups -Edition $Edition -Passed ($failures.Count -eq 0) -Detail $detail -Watch $watch
}

function Test-DryRunClean {
    param([Parameter(Mandatory)][ValidateSet('pwsh', 'desktop')][string]$Edition)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $target = Join-Path ([System.IO.Path]::GetTempPath()) "ToolFetcherChecks_$PID"
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    $run = Invoke-Edition -Edition $Edition -ScriptPath $script:ProductScript -ArgumentList '-DryRun', '-ToolsDirectory', $target
    $created = Test-Path -LiteralPath $target
    if ($created) { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue }
    $planned = @($run.Output | Where-Object { $_ -match '\[DRY-RUN\] Would ' }).Count
    if ($run.ExitCode -ne 0) {
        $detail = "exit code $($run.ExitCode)"
    }
    elseif ($created) {
        $detail = "the dry run created $target"
    }
    else {
        $detail = "$planned tools planned, nothing written to the tools directory"
    }
    $passed = ($run.ExitCode -eq 0) -and -not $created
    if (-not $passed) { Write-RunTail -Label "-DryRun ($Edition)" -Lines $run.Output }
    ConvertTo-CheckRow -Name dryrun -Edition $Edition -Passed $passed -Detail $detail -Watch $watch
}

function Save-PesterWrapper {
    # Invoke-Edition runs files only, so the suite is started through a throwaway script that pins
    # Pester to the 5.x line (Windows PowerShell 5.1 also carries the inbox Pester 3.4).
    param([Parameter(Mandatory)][string]$Folder)
    $null = New-Item -ItemType Directory -Path $Folder -Force
    $path = Join-Path $Folder 'Invoke-ProductTests.ps1'
    $lines = @(
        '# Written by build/Invoke-Checks.ps1 for a single run and deleted afterwards.'
        'param([Parameter(Mandatory = $true)][string]$Path)'
        'try { Import-Module Pester -MinimumVersion 5.5 -MaximumVersion 5.99.99 -ErrorAction Stop }'
        'catch { Write-Output (''Pester 5 could not be imported: '' + $_.Exception.Message); exit 1 }'
        '$result = Invoke-Pester -Path $Path -ExcludeTag Build, Network -PassThru'
        '$failed = $result.FailedCount + $result.FailedBlocksCount + $result.FailedContainersCount'
        'Write-Output (''PESTER-SUMMARY Passed={0} Failed={1} Skipped={2} Version={3}'' -f $result.PassedCount, $failed, $result.SkippedCount, (Get-Module Pester).Version)'
        'exit $failed'
    )
    [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
    return $path
}

function Test-PesterSuite {
    param([Parameter(Mandatory)][ValidateSet('pwsh', 'desktop')][string]$Edition)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $folder = Join-Path ([System.IO.Path]::GetTempPath()) "ToolFetcherChecksPester_$PID"
    try {
        $wrapper = Save-PesterWrapper -Folder $folder
        $run = Invoke-Edition -Edition $Edition -ScriptPath $wrapper -ArgumentList '-Path', (Join-Path $script:RepoRoot 'tests')
    }
    finally {
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
    $summary = $null
    foreach ($line in $run.Output) {
        $m = [regex]::Match([string]$line, '^PESTER-SUMMARY Passed=(\d+) Failed=(\d+) Skipped=(\d+) Version=(\S+)')
        if ($m.Success) { $summary = $m }
    }
    if ($null -eq $summary) {
        $passed = $false
        $detail = "exit code $($run.ExitCode), no Pester summary in the output"
    }
    else {
        $passedCount = [int]$summary.Groups[1].Value
        $failedCount = [int]$summary.Groups[2].Value
        $passed = ($run.ExitCode -eq 0) -and ($failedCount -eq 0) -and ($passedCount -gt 0)
        $detail = 'Passed {0}, Failed {1}, Skipped {2} (Pester {3})' -f $passedCount, $failedCount, $summary.Groups[3].Value, $summary.Groups[4].Value
    }
    if (-not $passed) { Write-RunTail -Label "Invoke-Pester ($Edition)" -Lines $run.Output }
    ConvertTo-CheckRow -Name pester -Edition $Edition -Passed $passed -Detail $detail -Watch $watch
}

function Get-GitSnapshot {
    # State 'ok' with the porcelain lines, 'norepo' outside a work tree, or 'error' with a message.
    $snapshot = [pscustomobject]@{ State = 'ok'; Lines = [string[]]@(); Message = '' }
    if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
        $snapshot.State = 'error'
        $snapshot.Message = 'git was not found on PATH'
        return $snapshot
    }
    $probe = @(& git -C $script:RepoRoot rev-parse --is-inside-work-tree 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0 -or $probe[-1] -ne 'true') {
        if (($probe -join ' ') -match 'not a git repository' -or $probe[-1] -eq 'false') {
            $snapshot.State = 'norepo'
        }
        else {
            $snapshot.State = 'error'
            $snapshot.Message = "git rev-parse failed: $($probe -join ' ')"
        }
        return $snapshot
    }
    # --no-optional-locks: a status check must not rewrite the index while other git commands run.
    $output = @(& git --no-optional-locks -C $script:RepoRoot status --porcelain --untracked-files=all -- . 2>&1)
    $code = $LASTEXITCODE
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    if ($code -ne 0) {
        $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
        $snapshot.State = 'error'
        $snapshot.Message = "git status failed with exit code ${code}: $($stderr -join ' ')"
        return $snapshot
    }
    $snapshot.Lines = [string[]]$stdout
    return $snapshot
}

function Test-GitClean {
    param([Parameter(Mandatory)][psobject]$Before)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $after = Get-GitSnapshot
    $passed = $false
    if ($Before.State -eq 'error') {
        $detail = $Before.Message
    }
    elseif ($after.State -eq 'error') {
        $detail = $after.Message
    }
    elseif ($Before.State -eq 'norepo' -and $after.State -eq 'norepo') {
        $passed = $true
        $detail = 'not a git repository'
    }
    elseif ($Before.State -ne $after.State) {
        $detail = "repository state changed from '$($Before.State)' to '$($after.State)' during the run"
    }
    else {
        $added = @($after.Lines | Where-Object { $_ -notin $Before.Lines })
        $removed = @($Before.Lines | Where-Object { $_ -notin $after.Lines })
        if ($added.Count -eq 0 -and $removed.Count -eq 0) {
            $passed = $true
            if ($after.Lines.Count -eq 0) { $detail = 'working tree clean before and after' }
            else { $detail = "git status unchanged ($($after.Lines.Count) entries before and after)" }
        }
        else {
            $changes = @($added | ForEach-Object { "+ $_" }) + @($removed | ForEach-Object { "- $_" })
            foreach ($change in $changes) { Write-Host "     $change" -ForegroundColor DarkGray }
            $detail = 'git status changed during the run: {0}' -f (($changes | Select-Object -First 5) -join '; ')
        }
    }
    ConvertTo-CheckRow -Name gitclean -Edition 'n/a' -Passed $passed -Detail $detail -Watch $watch
}

function Invoke-Check {
    # Runs one check function and records its row; an unexpected error becomes a failed row.
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$On,
        [Parameter(Mandatory)][scriptblock]$Check
    )
    Write-Host ('-> {0} ({1})' -f $Name, $On) -ForegroundColor Cyan
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $row = $null
    try {
        $row = @(& $Check) | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties['Passed'] } | Select-Object -Last 1
        if ($null -eq $row) { throw 'the check returned no result' }
    }
    catch {
        $row = ConvertTo-CheckRow -Name $Name -Edition $On -Passed $false -Detail "check error: $($_.Exception.Message)" -Watch $watch
    }
    $script:Rows.Add($row)
    if ($row.Passed) { $word = 'PASS'; $color = 'Green' } else { $word = 'FAIL'; $color = 'Red' }
    Write-Host ('   {0} {1}s  {2}' -f $word, $row.Seconds, $row.Detail) -ForegroundColor $color
}

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------
if ($Edition -eq 'both') { $editions = @('pwsh', 'desktop') } else { $editions = @($Edition) }
if ($editions -contains 'pwsh') { $groupEdition = 'pwsh' } else { $groupEdition = 'desktop' }

Write-Host "ToolFetcher checks in $($script:RepoRoot) (editions: $($editions -join ', '))"
try { $gitBefore = Get-GitSnapshot }
catch { $gitBefore = [pscustomobject]@{ State = 'error'; Lines = [string[]]@(); Message = "git status failed: $($_.Exception.Message)" } }

Invoke-Check -Name parse -On 'n/a' -Check { Test-ScriptParse }
Invoke-Check -Name encoding -On 'n/a' -Check { Test-ScriptEncoding }
if (-not $SkipAnalyzer) {
    Invoke-Check -Name analyzer -On 'n/a' -Check { Test-AnalyzerClean }
}
foreach ($ed in $editions) {
    Invoke-Check -Name listtools -On $ed -Check { Test-ToolListing -Edition $ed }
}
Invoke-Check -Name groups -On $groupEdition -Check { Test-GroupListing -Edition $groupEdition }
foreach ($ed in $editions) {
    Invoke-Check -Name dryrun -On $ed -Check { Test-DryRunClean -Edition $ed }
}
if ($Pester) {
    foreach ($ed in $editions) {
        Invoke-Check -Name pester -On $ed -Check { Test-PesterSuite -Edition $ed }
    }
}
# Last, so the comparison covers everything the other checks ran.
Invoke-Check -Name gitclean -On 'n/a' -Check { Test-GitClean -Before $gitBefore }

$allRows = $script:Rows.ToArray()
$allRows | Format-Table Name, Edition, Passed, Seconds, Detail -AutoSize -Wrap | Out-Host

if ($OutJson) {
    $jsonPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutJson)
    $jsonFolder = Split-Path -Path $jsonPath -Parent
    if ($jsonFolder -and -not (Test-Path -LiteralPath $jsonFolder)) {
        $null = New-Item -ItemType Directory -Path $jsonFolder -Force
    }
    $json = ConvertTo-Json -InputObject $allRows -Depth 3
    [System.IO.File]::WriteAllText($jsonPath, $json + [Environment]::NewLine)
    Write-Host "Wrote $jsonPath"
}

$failedRows = @($allRows | Where-Object { -not $_.Passed })
if ($failedRows.Count -gt 0) {
    Write-Host "$($failedRows.Count) of $($allRows.Count) checks failed." -ForegroundColor Red
    exit 1
}
Write-Host "All $($allRows.Count) checks passed." -ForegroundColor Green
exit 0
