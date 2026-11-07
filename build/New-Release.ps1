#Requires -Version 7.4
<#
.SYNOPSIS
    Bumps the version, builds and verifies the release zip and notes, and prints the publish commands.

.DESCRIPTION
    Preconditions, checked in this order:
      1. -Version looks like X.Y.Z.
      2. git status --porcelain is empty (skipped under -WhatIf), a local 'main' branch exists and is an
         ancestor of HEAD (the printed merge is then a fast-forward whose tree is the one in the zip).
      3. $script:Version in ToolFetcher.ps1 equals the version in the README title.
      4. CHANGELOG.md has a '## [Unreleased]' section whose text up to the next '## [' heading holds at
         least one line starting with '- ', and no '## [X.Y.Z]' section yet.
      5. build/Invoke-Checks.ps1 passes with the analyzer row included (left out with -SkipChecks).
    Failures of 2 to 4 are reported together in one error; 5 runs only when they all pass.
    A declined confirmation prompt (-Confirm) at the version bump stops the run with nothing changed; a
    write that fails after an earlier file was rewritten names the files to restore with git checkout.

    Then, under -RepoRoot:
      - sets $script:Version and the README title to X.Y.Z and renames '## [Unreleased]' in CHANGELOG.md
        to '## [X.Y.Z] - <Date>', then re-runs the parse check on ToolFetcher.ps1;
      - builds dist/ToolFetcher-X.Y.Z.zip: the script, tools.yaml, README.md, CHANGELOG.md, LICENSE and
        every tool_groups/*.yaml (template included) under a top-level ToolFetcher/ folder, copied byte
        for byte so the CRLF line endings of the checkout are kept;
      - verifies the zip: the entry list equals that file set, every entry's CR-stripped SHA256 equals
        the working-tree file's, and the script inside carries the new version;
      - writes dist/release-notes-X.Y.Z.md: the new CHANGELOG section and the "Full changelog" link;
      - prints the commit (subject 'Release X.Y.Z', one -m per bullet of the new CHANGELOG section as the
        body), merge (when not on main), tag, push --dry-run and gh release create commands, quoted for
        PowerShell.

    The script never commits, tags, pushes or publishes. Under -WhatIf nothing is written (dist/
    included); the notes text then comes from the Unreleased section and the printed paths do not exist.
    Refusals are thrown as terminating errors.

.PARAMETER Version
    The new version, X.Y.Z.

.PARAMETER Date
    The release date for the CHANGELOG heading, yyyy-MM-dd. Defaults to today.

.PARAMETER RepoRoot
    The checkout to release. Defaults to the folder above build/.

.PARAMETER SkipChecks
    Do not run build/Invoke-Checks.ps1. For a rehearsal only.

.PARAMETER AsLibrary
    Define the functions and return without running anything, for dot-sourcing from tests.

.EXAMPLE
    pwsh -NoProfile -File build/New-Release.ps1 -Version 2.2.3 -WhatIf

.EXAMPLE
    pwsh -NoProfile -File build/New-Release.ps1 -Version 2.2.3
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Console UI: precondition progress and the publish commands for a developer script')]
[CmdletBinding(SupportsShouldProcess)]
param(
    # Not Mandatory: the tests dot-source this file with -AsLibrary only. Validated in the main flow.
    [string]$Version = '',
    [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
    [string]$RepoRoot = '',
    [switch]$SkipChecks,
    [switch]$AsLibrary
)

. (Join-Path $PSScriptRoot 'DevCommon.ps1')
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

function Get-ReleaseFileList {
    # Paths relative to the repo root, backslash-separated, in ordinal order.
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$RepoRoot)
    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($name in 'ToolFetcher.ps1', 'tools.yaml', 'README.md', 'CHANGELOG.md', 'LICENSE') {
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $name) -PathType Leaf)) {
            throw "Release file missing: $(Join-Path $RepoRoot $name)"
        }
        $files.Add($name)
    }
    $groupFolder = Join-Path $RepoRoot 'tool_groups'
    if (-not (Test-Path -LiteralPath $groupFolder -PathType Container)) {
        throw "Release folder missing: $groupFolder"
    }
    foreach ($group in (Get-ChildItem -LiteralPath $groupFolder -Filter '*.yaml' -File)) {
        $files.Add('tool_groups\' + $group.Name)
    }
    $sorted = $files.ToArray()
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    return $sorted
}

function Get-CrStrippedSha256 {
    # SHA256 (hex) of the bytes with every CR (0x0D) removed, so CRLF and LF copies compare equal.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $kept = [System.IO.MemoryStream]::new($Bytes.Length)
    $start = 0
    while ($start -lt $Bytes.Length) {
        $cr = [Array]::IndexOf($Bytes, [byte]13, $start)
        if ($cr -lt 0) { $cr = $Bytes.Length }
        $kept.Write($Bytes, $start, $cr - $start)
        $start = $cr + 1
    }
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($kept.ToArray()))
}

function New-ReleaseZip {
    # Builds <OutDir>\ToolFetcher-<Version>.zip and returns its path (also under -WhatIf, unwritten).
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
        [Parameter(Mandatory)][string]$OutDir
    )
    $root = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).ProviderPath
    $outFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
    $files = Get-ReleaseFileList -RepoRoot $root
    $zipPath = Join-Path $outFolder "ToolFetcher-$Version.zip"
    if ($PSCmdlet.ShouldProcess($zipPath, "Create the release zip from $($files.Count) files")) {
        if (-not (Test-Path -LiteralPath $outFolder -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $outFolder -Force -Confirm:$false -ErrorAction Stop
        }
        if (Test-Path -LiteralPath $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force -Confirm:$false -ErrorAction Stop
        }
        $archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($relative in $files) {
                $entryName = 'ToolFetcher/' + $relative.Replace('\', '/')
                $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $archive, (Join-Path $root $relative), $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    return $zipPath
}

function Test-ReleaseZip {
    # $true when the zip holds exactly the release file set with the working tree's content (CR-stripped
    # SHA256) and the script inside carries $Version. Each problem found is written as a warning.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version
    )
    $root = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).ProviderPath
    $zipFile = (Resolve-Path -LiteralPath $ZipPath -ErrorAction Stop).ProviderPath
    $expected = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in (Get-ReleaseFileList -RepoRoot $root)) {
        $expected.Add('ToolFetcher/' + $relative.Replace('\', '/'))
    }
    $versionLine = '$script:Version = "' + $Version + '"'
    $problems = [System.Collections.Generic.List[string]]::new()
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipFile)
    try {
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $archive.Entries) { $names.Add($entry.FullName) }
        foreach ($name in $expected) {
            if (-not $names.Contains($name)) { $problems.Add("missing entry: $name") }
        }
        foreach ($name in $names) {
            if (-not $expected.Contains($name)) { $problems.Add("unexpected entry: $name") }
        }
        if ($names.Count -ne [System.Collections.Generic.HashSet[string]]::new($names).Count) {
            $problems.Add('the zip holds duplicate entry names')
        }
        foreach ($entry in $archive.Entries) {
            if (-not $expected.Contains($entry.FullName)) { continue }
            $buffer = [System.IO.MemoryStream]::new()
            $stream = $entry.Open()
            try { $stream.CopyTo($buffer) } finally { $stream.Dispose() }
            $entryBytes = $buffer.ToArray()
            $relative = $entry.FullName.Substring('ToolFetcher/'.Length).Replace('/', '\')
            $fileBytes = [System.IO.File]::ReadAllBytes((Join-Path $root $relative))
            if ((Get-CrStrippedSha256 -Bytes $entryBytes) -ne (Get-CrStrippedSha256 -Bytes $fileBytes)) {
                $problems.Add("$($entry.FullName) differs from $relative in the working tree")
            }
            if ($entry.FullName -ceq 'ToolFetcher/ToolFetcher.ps1') {
                $text = [System.Text.Encoding]::UTF8.GetString($entryBytes)
                if (-not $text.Contains($versionLine)) {
                    $problems.Add("ToolFetcher/ToolFetcher.ps1 does not contain $versionLine")
                }
            }
        }
    }
    finally {
        $archive.Dispose()
    }
    foreach ($problem in $problems) { Write-Warning "${zipFile}: $problem" }
    return ($problems.Count -eq 0)
}

function Update-ReleaseVersion {
    # Sets $script:Version and the README title to $Version and renames '## [Unreleased]' to
    # '## [<Version>] - <Date>'. All three edits are prepared first, then written together. Returns $true
    # when the files were written and $false when ShouldProcess declined (-WhatIf or a refused prompt).
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
        [Parameter(Mandatory)][ValidatePattern('^\d{4}-\d{2}-\d{2}$')][string]$Date
    )
    $root = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).ProviderPath
    $edits = @(
        @{
            File        = 'ToolFetcher.ps1'
            What        = 'line $script:Version = "..."'
            Pattern     = '(?m)^(\$script:Version\s*=\s*")[^"]*(")'
            Replacement = '${1}' + $Version + '${2}'
        }
        @{
            File        = 'README.md'
            What        = 'title # ToolFetcher (vX.Y.Z) on line 1'
            Pattern     = '\A# ToolFetcher \(v\d+\.\d+\.\d+\)(?=\r?\n|\z)'
            Replacement = "# ToolFetcher (v$Version)"
        }
        @{
            File        = 'CHANGELOG.md'
            What        = 'heading ## [Unreleased]'
            Pattern     = '(?m)^## \[Unreleased\][ \t]*(?=\r?$)'
            Replacement = "## [$Version] - $Date"
        }
    )
    $updates = [System.Collections.Generic.List[object]]::new()
    foreach ($edit in $edits) {
        $path = Join-Path $root $edit.File
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        # throwOnInvalidBytes: an invalid byte fails the bump instead of being rewritten as U+FFFD.
        $encoding = [System.Text.UTF8Encoding]::new($hasBom, $true)
        $skip = 0
        if ($hasBom) { $skip = 3 }
        try { $text = $encoding.GetString($bytes, $skip, $bytes.Length - $skip) }
        catch { throw "$($edit.File) is not valid UTF-8, so the version bump does not rewrite it: $($_.Exception.Message)" }
        $regex = [regex]::new($edit.Pattern)
        $found = $regex.Matches($text).Count
        if ($found -ne 1) { throw "$($edit.File): expected exactly one $($edit.What), found $found" }
        $updates.Add([pscustomobject]@{ Path = $path; Text = $regex.Replace($text, $edit.Replacement, 1); Encoding = $encoding })
    }
    $targets = ($edits | ForEach-Object { $_.File }) -join ', '
    if (-not $PSCmdlet.ShouldProcess($targets, "Set version $Version and CHANGELOG date $Date")) { return $false }
    $written = [System.Collections.Generic.List[string]]::new()
    foreach ($update in $updates) {
        $name = [System.IO.Path]::GetFileName($update.Path)
        try { [System.IO.File]::WriteAllText($update.Path, $update.Text, $update.Encoding) }
        catch {
            $reason = $_.Exception.Message
            if ($null -ne $_.Exception.InnerException) { $reason = $_.Exception.InnerException.Message }
            $hint = 'no file was rewritten'
            if ($written.Count -gt 0) {
                $hint = "already rewritten: $($written -join ', '); undo them with: git checkout -- $($written -join ' ')"
            }
            throw "$name could not be written ($reason); $hint"
        }
        $written.Add($name)
    }
    return $true
}

function Get-ChangelogSection {
    # The body of '## [<Version>]' in CHANGELOG.md (heading excluded) up to the next '## [' heading,
    # trimmed and CRLF-joined. -Version 'Unreleased' reads the Unreleased section.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][ValidatePattern('^(\d+\.\d+\.\d+|Unreleased)$')][string]$Version
    )
    $path = Join-Path $RepoRoot 'CHANGELOG.md'
    $lines = [regex]::Split((Get-Content -LiteralPath $path -Raw -ErrorAction Stop), '\r?\n')
    $heading = '^## \[' + [regex]::Escape($Version) + '\]'
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -cmatch $heading) { $start = $i; break }
    }
    if ($start -lt 0) { throw "CHANGELOG.md has no '## [$Version]' section" }
    $body = [System.Collections.Generic.List[string]]::new()
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith('## [')) { break }
        $body.Add($lines[$i])
    }
    return ($body.ToArray() -join "`r`n").Trim()
}

function Get-ReleaseCommands {
    # The publish commands, in the order a human runs them. Nothing here runs them.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Plural noun: returns the whole ordered list of publish commands; the name is fixed by the release plan')]
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$NotesPath,
        # The CHANGELOG section whose bullets become the commit body; defaults to -Version. The main flow
        # passes 'Unreleased' under -WhatIf, where the heading has not been renamed.
        [ValidatePattern('^(\d+\.\d+\.\d+|Unreleased)$')][string]$ChangelogSection = ''
    )
    $sectionName = $ChangelogSection
    if (-not $sectionName) { $sectionName = $Version }
    $branch = "$(& git -C $RepoRoot branch --show-current 2>$null)".Trim()
    $commands = [System.Collections.Generic.List[string]]::new()
    # One -m per CHANGELOG bullet line gives the bullet body CLAUDE.md asks for (git puts a blank line between
    # -m values). The bullets are single-quoted for PowerShell, so backticks and $ stay literal; every
    # character PowerShell treats as a single quote (' and the curly forms) is doubled.
    $commit = "git commit -m `"Release $Version`""
    foreach ($line in [regex]::Split((Get-ChangelogSection -RepoRoot $RepoRoot -Version $sectionName), '\r?\n')) {
        if ($line -cmatch '^- ') {
            $commit += " -m '" + [regex]::Replace($line.TrimEnd(), '[''\u2018\u2019\u201A\u201B]', '$0$0') + "'"
        }
    }
    $commands.Add("$commit -- ToolFetcher.ps1 README.md CHANGELOG.md")
    if ($branch -cne 'main') {
        if (-not $branch) {
            Write-Warning "HEAD is detached in $RepoRoot; replace <branch> with the branch that holds the release commit."
            $branch = '<branch>'
        }
        $commands.Add("git checkout main && git merge --no-ff $branch")
    }
    $commands.Add("git tag -a v$Version -m `"ToolFetcher $Version`"")
    $commands.Add('git push --dry-run origin main')
    $commands.Add("git push --dry-run origin v$Version")
    $commands.Add("gh release create v$Version `"$ZipPath`" --title `"ToolFetcher $Version`" --notes-file `"$NotesPath`"")
    return $commands.ToArray()
}

if ($AsLibrary) { return }

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'

# 1. Version and date format.
if (-not [regex]::IsMatch($Version, '^\d+\.\d+\.\d+$')) {
    throw "-Version must look like X.Y.Z (for example 2.2.3), got '$Version'"
}
$parsedDate = [datetime]::MinValue
$dateStyle = [System.Globalization.DateTimeStyles]::None
if (-not [regex]::IsMatch($Date, '^\d{4}-\d{2}-\d{2}$') -or
    -not [datetime]::TryParseExact($Date, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, $dateStyle, [ref]$parsedDate)) {
    throw "-Date must be a calendar date as yyyy-MM-dd, got '$Date'"
}
if (-not $RepoRoot) { $RepoRoot = Get-RepoRoot }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
$scriptPath = Join-Path $RepoRoot 'ToolFetcher.ps1'
$changelogPath = Join-Path $RepoRoot 'CHANGELOG.md'
Write-Host "New-Release $Version ($Date) in $RepoRoot" -ForegroundColor Cyan

$problems = [System.Collections.Generic.List[string]]::new()

# 2. Clean working tree.
if ($WhatIfPreference) {
    Write-Host '  clean tree: not checked under -WhatIf' -ForegroundColor Yellow
}
else {
    $status = @(& git -C $RepoRoot status --porcelain 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) {
        $problems.Add("git status failed in ${RepoRoot}: $($status -join ' ')")
    }
    elseif ($status.Count -gt 0) {
        $problems.Add("the working tree is not clean (git status --porcelain): $(($status | Select-Object -First 5) -join '; ')")
    }
}

# 2b. main is an ancestor of HEAD. The printed commands merge this branch into main with --no-ff; only a
# fast-forwardable branch gives that merge commit the tree the zip was built from, so the tag matches the zip.
$mainCommit = "$(& git -C $RepoRoot rev-parse --verify --quiet 'main^{commit}' 2>$null)".Trim()
if (-not $mainCommit) {
    $problems.Add("no local 'main' branch in ${RepoRoot}; the release flow merges into main")
}
else {
    & git -C $RepoRoot merge-base --is-ancestor main HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {
        $head = "$(& git -C $RepoRoot branch --show-current 2>$null)".Trim()
        if (-not $head) { $head = 'detached HEAD' }
        $problems.Add("main is not an ancestor of HEAD ($head): merge or rebase main into this branch first, or the tag would land on a merge commit whose tree differs from the zip")
    }
}

# 3. $script:Version and the README title agree.
try {
    $scriptVersion = Get-ScriptSetting -Name Version -ScriptPath $scriptPath
    $title = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -TotalCount 1)
    $titleMatch = [regex]::Match($title, '^# ToolFetcher \(v(\d+\.\d+\.\d+)\)\s*$')
    if (-not $titleMatch.Success) {
        $problems.Add("README.md line 1 is not '# ToolFetcher (vX.Y.Z)': $title")
    }
    elseif ($titleMatch.Groups[1].Value -ne $scriptVersion) {
        $problems.Add("`$script:Version is $scriptVersion but the README title says v$($titleMatch.Groups[1].Value)")
    }
}
catch {
    $problems.Add($_.Exception.Message)
}

# 4. CHANGELOG: Unreleased has a bullet and the new version has no section yet.
try {
    $unreleased = Get-ChangelogSection -RepoRoot $RepoRoot -Version 'Unreleased'
    if (-not ([regex]::Split($unreleased, '\r?\n') -cmatch '^- ')) {
        $problems.Add("CHANGELOG.md: the '## [Unreleased]' section has no bullet (a line starting with '- ')")
    }
    if ((Get-Content -LiteralPath $changelogPath) -cmatch ('^## \[' + [regex]::Escape($Version) + '\]')) {
        $problems.Add("CHANGELOG.md already has a '## [$Version]' section")
    }
}
catch {
    $problems.Add($_.Exception.Message)
}

if ($problems.Count -gt 0) {
    throw ("Release preconditions failed:`n" + (($problems | ForEach-Object { "  - $_" }) -join "`n"))
}
Write-Host '  preconditions: passed' -ForegroundColor Green

# 5. Invoke-Checks.ps1 of the checkout being released, analyzer included.
if ($SkipChecks) {
    Write-Host '  Invoke-Checks.ps1: skipped (-SkipChecks, for a rehearsal only)' -ForegroundColor Yellow
}
else {
    $checksScript = Join-Path $RepoRoot 'build\Invoke-Checks.ps1'
    if (-not (Test-Path -LiteralPath $checksScript -PathType Leaf)) {
        throw "$checksScript not found; it must pass before a release (-SkipChecks is for a rehearsal only)"
    }
    Write-Host "  running $checksScript (analyzer included)" -ForegroundColor Cyan
    # A separate process, so this script's -WhatIf does not reach the checks.
    & pwsh -NoProfile -File $checksScript '-SkipAnalyzer:$false' | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Invoke-Checks.ps1 failed with exit code $LASTEXITCODE; fix the failing rows before releasing"
    }
}

# Bump the three files, then make sure the script still parses. Under -WhatIf nothing is written and the
# flow goes on as a rehearsal; a refused -Confirm prompt stops here with nothing changed.
$bumped = Update-ReleaseVersion -RepoRoot $RepoRoot -Version $Version -Date $Date
if (-not $bumped -and -not $WhatIfPreference) {
    throw 'The version bump was declined at the confirmation prompt; nothing was changed.'
}
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    throw "ToolFetcher.ps1 does not parse after the version bump: line $($parseErrors[0].Extent.StartLineNumber): $($parseErrors[0].Message)"
}

# Zip and verification.
$distFolder = Join-Path $RepoRoot 'dist'
$zipPath = New-ReleaseZip -RepoRoot $RepoRoot -Version $Version -OutDir $distFolder
if (-not $WhatIfPreference) {
    if (-not (Test-ReleaseZip -ZipPath $zipPath -RepoRoot $RepoRoot -Version $Version)) {
        throw "Verification of $zipPath failed (warnings above). The version edits stay in the working tree; undo them with: git checkout -- ToolFetcher.ps1 README.md CHANGELOG.md"
    }
    $fileCount = @(Get-ReleaseFileList -RepoRoot $RepoRoot).Count
    Write-Host "  verified $zipPath ($fileCount files, CR-stripped SHA256 match the working tree, script reports $Version)" -ForegroundColor Green
}

# Release notes: the new CHANGELOG section (the Unreleased one under -WhatIf, where nothing was renamed).
$notesPath = Join-Path $distFolder "release-notes-$Version.md"
if ($WhatIfPreference) { $sectionName = 'Unreleased' } else { $sectionName = $Version }
$section = Get-ChangelogSection -RepoRoot $RepoRoot -Version $sectionName
$notes = $section + "`r`n`r`n" + 'Full changelog: https://github.com/kev365/ToolFetcher/blob/main/CHANGELOG.md' + "`r`n"
if ($PSCmdlet.ShouldProcess($notesPath, 'Write the release notes')) {
    if (-not (Test-Path -LiteralPath $distFolder -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $distFolder -Force -Confirm:$false
    }
    [System.IO.File]::WriteAllText($notesPath, $notes, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  wrote $notesPath" -ForegroundColor Green
}

$commands = [string[]](Get-ReleaseCommands -RepoRoot $RepoRoot -Version $Version -ZipPath $zipPath -NotesPath $notesPath -ChangelogSection $sectionName)
Write-Host ''
if ($WhatIfPreference) {
    Write-Host '-WhatIf: no file was changed or written; the zip and notes paths below do not exist.' -ForegroundColor Yellow
}
Write-Host "Nothing has been committed, tagged, pushed or published. From $RepoRoot run:" -ForegroundColor Cyan
foreach ($command in $commands) { Write-Host "  $command" }
Write-Host 'When both dry runs look right, push main and the tag without --dry-run before the gh release line.' -ForegroundColor Cyan

[pscustomobject]@{
    Version   = $Version
    ZipPath   = $zipPath
    NotesPath = $notesPath
    Commands  = $commands
}
