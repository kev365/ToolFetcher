# Development Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-run verification, release and upstream-audit work on ToolFetcher with scripts in the repo, a Pester suite for the script's pure functions, and GitHub Actions that run them.

**Architecture:** Dev scripts live under `build/` and require PowerShell 7; they drive Windows PowerShell 5.1 through the call operator where a check must run there. Tests under `tests/` dot-source `ToolFetcher.ps1 -SourceOnly`; tests of the dev scripts carry the `Build` tag so the checks script can run the product tests without recursing into itself. The only change to product logic is extracting `Select-ReleaseAsset` from `Resolve-ToolRemote` so asset selection can be tested and reused by the audit.

**Tech Stack:** PowerShell 7.6 and Windows PowerShell 5.1, Pester 5, PSScriptAnalyzer 1.25.0, powershell-yaml at the script's pin, GitHub Actions on `windows-latest`, `System.IO.Compression` for zips.

**Spec:** `docs/superpowers/specs/2026-11-04-dev-tooling-design.md`

## Global Constraints

- Branch `dev-tooling` is created from `perf-hashing`. Commits are local; nothing is pushed without the owner's explicit approval.
- `ToolFetcher.ps1` must run on Windows PowerShell 5.1 and PowerShell 7+; it stays ASCII with no BOM and CRLF in the working tree; PSScriptAnalyzer 1.25.0 must report 0 findings for it and for every `.ps1` under `build/`.
- Functions used by validation or `-ListTools` stay above the first `if (-not $SourceOnly)` gate (line 927). `Select-ReleaseAsset` is not one of them and lives next to `Resolve-ToolRemote`.
- Function names use approved verbs. Never assign to automatic variables. Never print or log a GitHub token.
- Windows PowerShell is invoked as `& powershell.exe -NoProfile -ExecutionPolicy Bypass ...`, never with `Start-Process`.
- The YAML module version is read from `$script:RequiredYamlVersion` in `ToolFetcher.ps1`; nothing hard-codes `0.4.12`.
- Unit tests make no network calls. Tests that need the network carry the `Network` tag and are excluded from the checks script and the checks workflow.
- Dev scripts never run `git push`, `git tag`, `git commit` or `gh release create`; they print those commands.
- New files use CRLF line endings and no BOM, like the rest of the repo. Verify with `file` or `[IO.File]::ReadAllBytes` before each commit.
- Commit messages: imperative subject, bullet body, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. `build/Invoke-Checks.ps1` run from a directory other than the repo root (for example `cd C:\` then `pwsh -File <repo>\build\Invoke-Checks.ps1`) must still find the script and YAML files. Test added to Task 7.
2. `New-Release.ps1` on a CHANGELOG whose `## [Unreleased]` heading exists but has no bullet must refuse and change nothing. Test added to Task 8.
3. The audit must treat `https://github.com/Owner/Repo/` and `https://github.com/Owner/Repo.git` as the same repository as `https://github.com/Owner/Repo` when de-duplicating and when parsing owner and repo. Test added to Task 9.
4. When GitHub answers 403 with `X-RateLimit-Remaining: 0`, the audit must mark the remaining GitHub entries `transient` and stop calling the API, not mark them `broken`. Test added to Task 9.
5. `Expand-ZipSafely` must handle entries that use backslashes as separators and directory-only entries without writing outside the destination or crashing. Test added to Task 3.

---

### Task 1: Branch, hygiene files, Pester 5

**Files:**
- Create: `.gitattributes`, `.editorconfig`, `PSScriptAnalyzerSettings.psd1`, `tests/Smoke.Tests.ps1`
- Modify: `.gitignore`

**Interfaces:**
- Produces: Pester 5 installed for the current user under both editions; `tests/` convention: every test file dot-sources the script with `. (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly` inside `BeforeAll`.

- [ ] **Step 1: Create the branch**

Run: `git checkout -b dev-tooling perf-hashing`
Expected: `Switched to a new branch 'dev-tooling'`

- [ ] **Step 2: Install Pester 5 for both editions**

Run: `pwsh -NoProfile -Command "Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck"` and `& powershell.exe -NoProfile -Command "Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck"`
Expected: `Get-Module -ListAvailable Pester` in each edition lists a 5.x version.

- [ ] **Step 3: Write the failing smoke test**

`tests/Smoke.Tests.ps1`:

```powershell
BeforeAll { . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly }
Describe 'ToolFetcher -SourceOnly' {
    It 'defines the hashing helper' { Get-Command Get-FileHashHex -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty }
    It 'defines Select-ReleaseAsset' { Get-Command Select-ReleaseAsset -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty }
    It 'exposes the YAML pin' { $script:RequiredYamlVersion | Should -Match '^\d+\.\d+\.\d+$' }
}
```

- [ ] **Step 4: Run it to see one failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Smoke.Tests.ps1 -Output Detailed"`
Expected: 2 passed, 1 failed (`Select-ReleaseAsset` does not exist yet; Task 5 makes it pass).

- [ ] **Step 5: Write the hygiene files**

`.gitattributes` (exact content):

```
* text=auto
*.ps1 text eol=crlf
*.psd1 text eol=crlf
*.psm1 text eol=crlf
*.yaml text eol=crlf
*.yml text eol=crlf
*.md text eol=crlf
*.txt text eol=crlf
LICENSE text eol=crlf
*.zip binary
```

`.editorconfig`: `root = true`; `[*]` with `charset = utf-8`, `end_of_line = crlf`, `insert_final_newline = true`, `trim_trailing_whitespace = true`; `[*.ps1]` `indent_style = space`, `indent_size = 4`; `[*.{yaml,yml}]` `indent_size = 2`.

`PSScriptAnalyzerSettings.psd1`: `@{ Severity = @('Error', 'Warning', 'Information'); IncludeDefaultRules = $true; ExcludeRules = @() }`.

`.gitignore`: replace the line `docs/` with `docs/*` followed by `!docs/superpowers/`; add `dist/` and `tests/TestResults/` under the Folders section.

- [ ] **Step 6: Verify renormalization is a no-op and the spec folder is now tracked**

Run: `git add --renormalize . ; git status --short`
Expected: only the new files and `.gitignore` appear; no existing file shows as modified. `git check-ignore -v docs/superpowers/specs/2026-11-04-dev-tooling-design.md` prints nothing.

- [ ] **Step 7: Commit**

```bash
git add .gitattributes .editorconfig PSScriptAnalyzerSettings.psd1 .gitignore tests/Smoke.Tests.ps1 docs/superpowers/specs/2026-11-04-dev-tooling-design.md docs/superpowers/plans/2026-11-05-dev-tooling.md
git commit -m "Add repository hygiene files, Pester smoke test and tracked specs"
```

Body bullets: line-ending attributes so checkout is CRLF on every clone (renormalize was a no-op); analyzer settings file; `docs/superpowers/` tracked while the audit report stays ignored; smoke test for `-SourceOnly`.

---

### Task 2: Test helpers, hashing and marker tests

**Files:**
- Create: `tests/TestHelpers.ps1`, `tests/Hashing.Tests.ps1`, `tests/Markers.Tests.ps1`

**Interfaces:**
- Produces (in `tests/TestHelpers.ps1`, dot-sourced by later test files after the script):
  - `New-TestFile -Path [string] -Bytes [int] -Seed [int] = 1` writes deterministic pseudo-random bytes, returns the path.
  - `New-TestZip -Path [string] -Entries [hashtable]` where keys are entry names (may contain `..`, `\`, or end in `/`) and values are string content (`$null` for a directory entry); returns the path. Built with `[IO.Compression.ZipArchive]` so hostile names are not normalized away.
  - `New-FakeAsset -Name [string]` returns `[pscustomobject]@{ name = $Name; browser_download_url = "https://example.invalid/$Name" }`.

- [ ] **Step 1: Write `tests/TestHelpers.ps1` with the three functions above**

- [ ] **Step 2: Write the failing hashing tests**

`tests/Hashing.Tests.ps1`, `BeforeAll` dot-sources the script and the helpers, then:

```powershell
Describe 'Get-FileHashHex' {
    It 'matches Get-FileHash for SHA256 on a 3 MB file' { $f = New-TestFile "$TestDrive\big.bin" 3MB; Get-FileHashHex -Path $f | Should -Be (Get-FileHash $f -Algorithm SHA256).Hash }
    It 'matches Get-FileHash for MD5' { $f = New-TestFile "$TestDrive\m.bin" 4096; Get-FileHashHex -Path $f -Algorithm MD5 | Should -Be (Get-FileHash $f -Algorithm MD5).Hash }
    It 'hashes an empty file' { $f = New-TestFile "$TestDrive\e.bin" 0; Get-FileHashHex -Path $f | Should -Be 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855' }
    It 'returns uppercase hex' { $f = New-TestFile "$TestDrive\u.bin" 10; Get-FileHashHex -Path $f | Should -MatchExactly '^[0-9A-F]{64}$' }
}
Describe 'Get-ManifestEntryAlgorithm' {
    It 'returns MD5 for a 32-character digest' { Get-ManifestEntryAlgorithm -Digest ('A' * 32) -Declared 'SHA256' | Should -Be 'MD5' }
    It 'returns SHA256 for a 64-character digest' { Get-ManifestEntryAlgorithm -Digest ('A' * 64) -Declared 'MD5' | Should -Be 'SHA256' }
}
Describe 'ConvertTo-ManifestTable' {
    It 'is case-insensitive on paths' { (ConvertTo-ManifestTable -Manifest @{ 'Sub\File.txt' = 'X' })['sub\file.txt'] | Should -Be 'X' }
    It 'accepts a PSCustomObject from ConvertFrom-Json' { $m = '{"a.txt":"1","b.txt":"2"}' | ConvertFrom-Json; (ConvertTo-ManifestTable -Manifest $m).Count | Should -Be 2 }
    It 'returns an empty table for null' { (ConvertTo-ManifestTable -Manifest $null).Count | Should -Be 0 }
}
```

- [ ] **Step 3: Run them; all must pass without code changes**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Hashing.Tests.ps1 -Output Detailed"` and the same under `powershell.exe`.
Expected: all pass on both editions. If `Get-ManifestEntryAlgorithm` disagrees with the 32/64 rule, read its body and fix the test's expectation only if the script's documented rule differs; do not change the script.

- [ ] **Step 4: Write the failing marker tests**

`tests/Markers.Tests.ps1`:

```powershell
Describe 'Write-MarkerFile / Get-ToolMarker' {
    It 'round-trips every field' {
        $dir = New-Item "$TestDrive\t" -ItemType Directory
        Write-MarkerFile -OutputFolder $dir -ToolName 'T' -DownloadMethod 'latestRelease' -DownloadURL 'https://x/y.zip' -Version 'v1' -Manifest @{ 'a.txt' = ('A' * 64) } -HashAlgorithm 'SHA256' -Branch 'main' -ApiETag 'W/"e"'
        $m = Get-ToolMarker -OutputFolder $dir
        $m.Tool | Should -Be 'T'; $m.Version | Should -Be 'v1'; $m.HashAlgorithm | Should -Be 'SHA256'; $m.Branch | Should -Be 'main'; $m.ApiETag | Should -Be 'W/"e"'
        (ConvertTo-ManifestTable $m.Manifest)['a.txt'] | Should -Be ('A' * 64)
    }
    It 'reads a 2.1-style marker with MD5 digests and no HashAlgorithm' {
        $dir = New-Item "$TestDrive\old" -ItemType Directory
        '{"Tool":"Old","Manifest":{"f.txt":"0123456789ABCDEF0123456789ABCDEF"}}' | Set-Content "$dir\.downloaded.json"
        $m = Get-ToolMarker -OutputFolder $dir
        Get-ManifestEntryAlgorithm -Digest $m.Manifest.'f.txt' -Declared (Get-MarkerValue -Marker $m -Name 'HashAlgorithm') | Should -Be 'MD5'
    }
    It 'returns null when no marker exists' { Get-ToolMarker -OutputFolder $TestDrive | Should -BeNullOrEmpty }
}
```

- [ ] **Step 5: Run them on both editions; all pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Markers.Tests.ps1"` and under `powershell.exe`.
Expected: all pass. Check `Write-MarkerFile`'s parameter list (script line 1412) if a named parameter is rejected and use the names it declares.

- [ ] **Step 6: Commit**

```bash
git add tests/TestHelpers.ps1 tests/Hashing.Tests.ps1 tests/Markers.Tests.ps1
git commit -m "Add Pester tests for hashing and marker files"
```

---

### Task 3: Validation, zip safety, path and redaction tests

**Files:**
- Create: `tests/Validation.Tests.ps1`, `tests/ZipSafety.Tests.ps1`, `tests/Paths.Tests.ps1`, `tests/Redaction.Tests.ps1`

**Interfaces:**
- Consumes: `New-TestZip`, `New-FakeAsset` from Task 2; script functions `Test-ToolEntry -Tool`, `Test-ToolConfiguration -Config`, `Test-PlaceholderEntry -Tool`, `Test-ToolHasTag -Tool -TagSet`, `Expand-ZipSafely -ZipPath -DestinationPath` (returns the number of files written), `Initialize-OutputFolder -ToolConfig -ToolsDirectory` (returns the created folder path or `$null`), `Format-RedactedMessage -Text`, `Set-ToolFetcherRunState -State`.

- [ ] **Step 1: Write the validation tests**

`tests/Validation.Tests.ps1`:

```powershell
Describe 'Test-ToolConfiguration on shipped files' {
    It 'accepts <_>' -ForEach ((Get-ChildItem "$PSScriptRoot\..\tool_groups\*.yaml" | Where-Object Name -ne '_tool_template.yaml').FullName + "$PSScriptRoot\..\tools.yaml") {
        Import-Module powershell-yaml -RequiredVersion $script:RequiredYamlVersion
        $cfg = Add-ConfigurationDefaults -Config (ConvertFrom-Yaml (Get-Content $_ -Raw))
        (Test-ToolConfiguration -Config $cfg).IsValid | Should -BeTrue
    }
}
Describe 'Test-ToolEntry' {
    It 'rejects a name with a path separator'  { (Test-ToolEntry -Tool @{ Name = 'a\b'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip' }).IsValid | Should -BeFalse }
    It 'rejects a name with ..'                 { (Test-ToolEntry -Tool @{ Name = '..'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip' }).IsValid | Should -BeFalse }
    It 'rejects an absolute OutputFolder'       { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip'; OutputFolder = 'C:\x' }).IsValid | Should -BeFalse }
    It 'rejects an unknown DownloadMethod'      { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'wget' }).IsValid | Should -BeFalse }
    It 'requires SpecificFilePath or DownloadName for specificFile on GitHub' { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'specificFile' }).IsValid | Should -BeFalse }
    It 'allows specificFile on a GitHub releases URL without DownloadName' { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r/releases/latest/download/x.exe'; DownloadMethod = 'specificFile' }).IsValid | Should -BeTrue }
    It 'warns but accepts http://' { $r = Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'http://example.com/x.zip'; DownloadMethod = 'specificFile'; DownloadName = 'x.zip' }; $r.IsValid | Should -BeTrue }
}
Describe 'Placeholders and tags' {
    It 'treats an entry without RepoUrl as a placeholder' { Test-PlaceholderEntry -Tool @{ Name = 'p'; DownloadMethod = 'branchZip' } | Should -BeTrue }
    It 'treats an entry without DownloadMethod as a placeholder' { Test-PlaceholderEntry -Tool @{ Name = 'p'; RepoUrl = 'https://x' } | Should -BeTrue }
    It 'matches a tag from a list Category' { $set = [Collections.Generic.HashSet[string]]::new([string[]]@('logs'), [StringComparer]::OrdinalIgnoreCase); Test-ToolHasTag -Tool @{ Name = 't'; Category = @('misc', 'Logs') } -TagSet $set | Should -BeTrue }
}
```

Read `Test-ToolEntry` (script line 662) for the exact shape of its return value (`IsValid` and `Errors` are the expected property names; adjust the tests to the real names, not the script).

- [ ] **Step 2: Write the zip safety tests**

`tests/ZipSafety.Tests.ps1`:

```powershell
Describe 'Expand-ZipSafely' {
    It 'extracts a normal zip and returns the file count' {
        $z = New-TestZip "$TestDrive\ok.zip" @{ 'a.txt' = 'A'; 'sub/b.txt' = 'B' }
        Expand-ZipSafely -ZipPath $z -DestinationPath "$TestDrive\out1" | Should -Be 2
        Get-Content "$TestDrive\out1\sub\b.txt" | Should -Be 'B'
    }
    It 'refuses an entry that escapes with ..' {
        $z = New-TestZip "$TestDrive\slip.zip" @{ '../evil.txt' = 'X' }
        { Expand-ZipSafely -ZipPath $z -DestinationPath "$TestDrive\out2" } | Should -Throw
        Test-Path "$TestDrive\evil.txt" | Should -BeFalse
    }
    It 'refuses an absolute entry path' {
        $z = New-TestZip "$TestDrive\abs.zip" @{ 'C:/Windows/evil.txt' = 'X' }
        { Expand-ZipSafely -ZipPath $z -DestinationPath "$TestDrive\out3" } | Should -Throw
    }
    It 'handles backslash separators and directory entries' {
        $z = New-TestZip "$TestDrive\bs.zip" @{ 'dir\' = $null; 'dir\c.txt' = 'C' }
        Expand-ZipSafely -ZipPath $z -DestinationPath "$TestDrive\out4" | Should -Be 1
        Test-Path "$TestDrive\out4\dir\c.txt" | Should -BeTrue
    }
}
```

- [ ] **Step 3: Write the path tests**

`tests/Paths.Tests.ps1`:

```powershell
Describe 'Initialize-OutputFolder' {
    It 'creates a nested relative folder under the tools directory' {
        $p = Initialize-OutputFolder -ToolConfig @{ Name = 'T'; OutputFolder = 'a\b' } -ToolsDirectory "$TestDrive\tools"
        $p | Should -Be (Join-Path "$TestDrive\tools" 'a\b\T')
        Test-Path $p | Should -BeTrue
    }
    It 'returns null for a traversal OutputFolder' { Initialize-OutputFolder -ToolConfig @{ Name = 'T'; OutputFolder = '..\x' } -ToolsDirectory "$TestDrive\tools" | Should -BeNullOrEmpty }
    It 'returns null for a drive-prefixed OutputFolder' { Initialize-OutputFolder -ToolConfig @{ Name = 'T'; OutputFolder = 'D:\x' } -ToolsDirectory "$TestDrive\tools" | Should -BeNullOrEmpty }
}
```

Read `Initialize-OutputFolder` (line 1744) to confirm whether the tool name is appended to the folder it returns; set the expected path accordingly before running.

- [ ] **Step 4: Write the redaction tests**

`tests/Redaction.Tests.ps1`:

```powershell
Describe 'Format-RedactedMessage' {
    BeforeAll { Set-ToolFetcherRunState -State @{ GitHubPAT = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789AB'; LoggingEnabled = $false; VerboseOutput = $false; TraceOutput = $false; LogFile = ''; LogMutexName = '' } }
    AfterAll  { Set-ToolFetcherRunState -State @{ GitHubPAT = ''; LoggingEnabled = $false; VerboseOutput = $false; TraceOutput = $false; LogFile = ''; LogMutexName = '' } }
    It 'removes the literal token from a URL' { Format-RedactedMessage -Text 'https://ghp_abcdefghijklmnopqrstuvwxyz0123456789AB@github.com/x' | Should -Not -Match 'ghp_abcdef' }
    It 'removes an Authorization header value' { Format-RedactedMessage -Text 'Authorization: token ghp_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz' | Should -Not -Match 'ghp_zzzz' }
    It 'removes a fine-grained token' { Format-RedactedMessage -Text 'token github_pat_11AAAAAAA0bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' | Should -Not -Match 'github_pat_11' }
    It 'leaves ordinary text alone' { Format-RedactedMessage -Text 'Downloaded 3 files' | Should -Be 'Downloaded 3 files' }
}
```

Read `$script:SecretRedactPatterns` (near line 340) and align the second and third cases with the shapes it actually targets; if a shape is not covered, keep the test and note it in the task report rather than changing the script.

- [ ] **Step 5: Run all four files on both editions**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Validation.Tests.ps1, tests/ZipSafety.Tests.ps1, tests/Paths.Tests.ps1, tests/Redaction.Tests.ps1 -Output Detailed"` and the same under `powershell.exe`.
Expected: all pass. A failure here is a finding about the script; report it, do not change product code in this task.

- [ ] **Step 6: Commit**

```bash
git add tests/Validation.Tests.ps1 tests/ZipSafety.Tests.ps1 tests/Paths.Tests.ps1 tests/Redaction.Tests.ps1
git commit -m "Add Pester tests for validation, zip safety, output paths and redaction"
```

---

### Task 4: Retry and intact-check tests

**Files:**
- Create: `tests/Retry.Tests.ps1`, `tests/Intact.Tests.ps1`

**Interfaces:**
- Consumes: `Invoke-WithRetry -ScriptBlock -MaxAttempts -DelaysSeconds -Description`; `Get-HttpErrorInfo` reads `$ErrorRecord.Exception.Response.StatusCode` (or the inner exception's), so a test can throw an exception whose `Response` property is an object with `StatusCode` and `Headers`; `Test-ToolIntact -Marker -OutputFolder`; `Write-MarkerFile`, `Get-ToolMarker`, `Get-FileManifest -Folder`.

- [ ] **Step 1: Write a fake HTTP error helper in `tests/TestHelpers.ps1`**

`New-FakeHttpException -StatusCode [int] -RetryAfter [string] = $null` returns a `[System.Exception]` subclass instance (define a small class `FakeHttpException : System.Exception` with a `Response` property holding `[pscustomobject]@{ StatusCode = $StatusCode; Headers = @{ 'Retry-After' = $RetryAfter } }`). Confirm `Get-ResponseHeader -Headers -Name` accepts a hashtable; if it requires a `WebHeaderCollection`, build one instead.

- [ ] **Step 2: Write the retry tests**

```powershell
Describe 'Invoke-WithRetry' {
    It 'returns the result on first success' { Invoke-WithRetry -ScriptBlock { 42 } -DelaysSeconds @(0) | Should -Be 42 }
    It 'does not retry a 404' { $n = 0; { Invoke-WithRetry -ScriptBlock { $n++; throw (New-FakeHttpException 404) } -DelaysSeconds @(0,0) } | Should -Throw; $n | Should -Be 1 }
    It 'does not retry a 403' { $n = 0; { Invoke-WithRetry -ScriptBlock { $n++; throw (New-FakeHttpException 403) } -DelaysSeconds @(0,0) } | Should -Throw; $n | Should -Be 1 }
    It 'retries a 500 up to MaxAttempts' { $n = 0; { Invoke-WithRetry -ScriptBlock { $n++; throw (New-FakeHttpException 500) } -MaxAttempts 3 -DelaysSeconds @(0,0,0) } | Should -Throw; $n | Should -Be 3 }
    It 'retries a connection error and then succeeds' { $n = 0; Invoke-WithRetry -ScriptBlock { $n++; if ($n -lt 2) { throw [System.Net.WebException]::new('reset') }; 'ok' } -DelaysSeconds @(0,0) | Should -Be 'ok'; $n | Should -Be 2 }
    It 'honours a short Retry-After on 429' { $n = 0; Invoke-WithRetry -ScriptBlock { $n++; if ($n -lt 2) { throw (New-FakeHttpException 429 -RetryAfter '1') }; 'ok' } -DelaysSeconds @(0,0) | Should -Be 'ok' }
}
```

The `$n` counters must be visible inside the script blocks: use `$script:n` or a `[ref]`, whichever the first run shows is needed.

- [ ] **Step 3: Write the intact tests**

```powershell
Describe 'Test-ToolIntact' {
    BeforeEach {
        $dir = New-Item "$TestDrive\tool$(Get-Random)" -ItemType Directory
        Set-Content "$dir\a.txt" 'A'; Set-Content "$dir\b.txt" 'B'
        Write-MarkerFile -OutputFolder $dir -ToolName 'T' -DownloadMethod 'branchZip' -DownloadURL 'https://x' -Manifest (Get-FileManifest -Folder $dir) -HashAlgorithm 'SHA256'
        $marker = Get-ToolMarker -OutputFolder $dir
    }
    It 'is true for an untouched install' { Test-ToolIntact -Marker $marker -OutputFolder $dir | Should -BeTrue }
    It 'is false when a managed file changed' { Set-Content "$dir\a.txt" 'changed'; Test-ToolIntact -Marker $marker -OutputFolder $dir | Should -BeFalse }
    It 'is false when a managed file is missing' { Remove-Item "$dir\b.txt"; Test-ToolIntact -Marker $marker -OutputFolder $dir | Should -BeFalse }
    It 'ignores user-added files' { Set-Content "$dir\notes.txt" 'mine'; Test-ToolIntact -Marker $marker -OutputFolder $dir | Should -BeTrue }
}
```

- [ ] **Step 4: Run both files on both editions**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Retry.Tests.ps1, tests/Intact.Tests.ps1 -Output Detailed"` and under `powershell.exe`.
Expected: all pass; total suite run time under 30 s per edition.

- [ ] **Step 5: Commit**

```bash
git add tests/TestHelpers.ps1 tests/Retry.Tests.ps1 tests/Intact.Tests.ps1
git commit -m "Add Pester tests for retry policy and managed-file integrity"
```

---

### Task 5: Extract `Select-ReleaseAsset`

**Files:**
- Modify: `ToolFetcher.ps1` (new function immediately above `function Resolve-ToolRemote`, line 2172; replace the selection block at lines 2220-2236)
- Create: `tests/AssetSelection.Tests.ps1`

**Interfaces:**
- Produces: `Select-ReleaseAsset -ToolConfig <hashtable|object> -Assets <object[]> [-All]` returning the first matching asset object, `$null` when none; with `-All` an array of every match in release order. Rules exactly as today: `DownloadName` by `-eq`, else `AssetFilename` by `-match`, else `AssetType` by `$script:AssetPatterns[AssetType]` (a `Write-LogWarning` and no match for an unknown type), else every asset. Used by Task 9.

- [ ] **Step 1: Write the failing tests**

```powershell
Describe 'Select-ReleaseAsset' {
    BeforeAll { $assets = 'tool-1.0-win-x64.zip', 'tool-1.0-win-x64.zip.asc', 'tool-1.0-linux-x64.tar.gz', 'tool-1.0-win-arm64.zip', 'tool-1.0-macos-x64.zip' | ForEach-Object { New-FakeAsset $_ } }
    It 'selects by exact DownloadName' { (Select-ReleaseAsset -ToolConfig @{ DownloadName = 'tool-1.0-linux-x64.tar.gz' } -Assets $assets).name | Should -Be 'tool-1.0-linux-x64.tar.gz' }
    It 'DownloadName is case-insensitive like -eq' { (Select-ReleaseAsset -ToolConfig @{ DownloadName = 'TOOL-1.0-WIN-X64.ZIP' } -Assets $assets).name | Should -Be 'tool-1.0-win-x64.zip' }
    It 'applies AssetFilename as a regex and returns the first match' { (Select-ReleaseAsset -ToolConfig @{ AssetFilename = 'win-x64\.zip' } -Assets $assets).name | Should -Be 'tool-1.0-win-x64.zip' }
    It 'returns every match with -All' { (Select-ReleaseAsset -ToolConfig @{ AssetFilename = 'win-x64\.zip' } -Assets $assets -All).Count | Should -Be 2 }
    It 'win64 picks the Windows x64 build only' { (Select-ReleaseAsset -ToolConfig @{ AssetType = 'win64' } -Assets $assets -All).name | Should -Be @('tool-1.0-win-x64.zip', 'tool-1.0-win-x64.zip.asc') }
    It 'returns null when nothing matches' { Select-ReleaseAsset -ToolConfig @{ DownloadName = 'nope.zip' } -Assets $assets | Should -BeNullOrEmpty }
    It 'returns the first asset when no selector is set' { (Select-ReleaseAsset -ToolConfig @{} -Assets $assets).name | Should -Be 'tool-1.0-win-x64.zip' }
    It 'returns null for an unknown AssetType' { Select-ReleaseAsset -ToolConfig @{ AssetType = 'amiga' } -Assets $assets | Should -BeNullOrEmpty }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/AssetSelection.Tests.ps1"`
Expected: FAIL, `Select-ReleaseAsset` is not recognized.

- [ ] **Step 3: Implement `Select-ReleaseAsset` in `ToolFetcher.ps1` and call it from `Resolve-ToolRemote`**

Move the four-branch selection (lines 2220-2236) into the new function; `Resolve-ToolRemote` keeps `$asset = Select-ReleaseAsset -ToolConfig $ToolConfig -Assets $releaseInfo.assets` followed by the existing null check and warning. Keep `$null -eq $asset` semantics; with `-All` return `@($matches)` so a single match is still an array.

- [ ] **Step 4: Run the tests, the smoke test and the CLAUDE.md checks**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/AssetSelection.Tests.ps1, tests/Smoke.Tests.ps1"` on both editions; then the parse check, `Invoke-ScriptAnalyzer -Path .\ToolFetcher.ps1 -Settings .\PSScriptAnalyzerSettings.psd1`, `-ListTools` on both editions (78), and `-DryRun -ToolsDirectory <temp>`.
Expected: all pass, 0 analyzer findings, file still ASCII without BOM and CRLF.

- [ ] **Step 5: Prove behavior is unchanged with one real release lookup**

Run: `pwsh -NoProfile -File .\ToolFetcher.ps1 -DryRun -UpdateTools hayabusa -ToolsDirectory <temp> -GitHubPAT (gh auth token)` after a first real download of hayabusa into that temp directory.
Expected: the dry run reports hayabusa up to date and names `hayabusa-<ver>-win-x64.zip`.

- [ ] **Step 6: Commit**

```bash
git add ToolFetcher.ps1 tests/AssetSelection.Tests.ps1
git commit -m "Extract Select-ReleaseAsset from Resolve-ToolRemote"
```

---

### Task 6: Shared dev helpers

**Files:**
- Create: `build/DevCommon.ps1`, `tests/Build.DevCommon.Tests.ps1`

**Interfaces:**
- Produces (dot-sourced by every script under `build/`):
  - `Get-RepoRoot` -> `[string]` (the parent of the `build` folder, from `$PSScriptRoot` of DevCommon).
  - `Get-ScriptSetting -Name [string] -ScriptPath [string] = "<root>\ToolFetcher.ps1"` -> `[string]`; reads `^\$script:<Name>\s*=\s*"([^"]+)"` from the file; throws if absent. Used for `Version` and `RequiredYamlVersion`.
  - `Import-PinnedYaml` imports `powershell-yaml -RequiredVersion (Get-ScriptSetting RequiredYamlVersion)`.
  - `Invoke-Edition -Edition ('pwsh'|'desktop') -ScriptPath [string] -ArgumentList [string[]] = @()` -> `[pscustomobject]@{ Edition; ExitCode [int]; Output [string[]]; Seconds [double] }`; `pwsh` runs `& pwsh -NoProfile -File`, `desktop` runs `& powershell.exe -NoProfile -ExecutionPolicy Bypass -File`; both merge stderr into `Output` and never throw.
  - `Test-TextEncoding -Path [string]` -> `[pscustomobject]@{ Ascii [bool]; Bom [bool]; Crlf [bool]; LoneLf [bool] }`.
  - `Get-ToolEntryCount -YamlPath [string]` -> `[int]` = `tools.Count` after `Import-PinnedYaml` and `ConvertFrom-Yaml`.

- [ ] **Step 1: Write the failing tests** (`-Tag Build` on the Describe)

```powershell
Describe 'DevCommon' -Tag Build {
    BeforeAll { . "$PSScriptRoot\..\build\DevCommon.ps1" }
    It 'finds the repo root' { Test-Path (Join-Path (Get-RepoRoot) 'ToolFetcher.ps1') | Should -BeTrue }
    It 'reads the version and the yaml pin' { Get-ScriptSetting -Name Version | Should -Match '^\d+\.\d+\.\d+$'; Get-ScriptSetting -Name RequiredYamlVersion | Should -Match '^\d+\.\d+\.\d+$' }
    It 'throws for an unknown setting' { { Get-ScriptSetting -Name NoSuchThing } | Should -Throw }
    It 'runs the script under pwsh and desktop' -ForEach 'pwsh', 'desktop' { $r = Invoke-Edition -Edition $_ -ScriptPath (Join-Path (Get-RepoRoot) 'ToolFetcher.ps1') -ArgumentList '-ListTools'; $r.ExitCode | Should -Be 0; ($r.Output -join "`n") | Should -Match 'Total Tools: \d+' }
    It 'reports the script as ASCII, no BOM, CRLF' { $e = Test-TextEncoding -Path (Join-Path (Get-RepoRoot) 'ToolFetcher.ps1'); $e.Ascii | Should -BeTrue; $e.Bom | Should -BeFalse; $e.Crlf | Should -BeTrue; $e.LoneLf | Should -BeFalse }
    It 'counts tools.yaml entries' { Get-ToolEntryCount -YamlPath (Join-Path (Get-RepoRoot) 'tools.yaml') | Should -BeGreaterThan 60 }
}
```

- [ ] **Step 2: Run to verify failure** (file not found)

- [ ] **Step 3: Implement `build/DevCommon.ps1`** with `#Requires -Version 7` and the six functions above.

- [ ] **Step 4: Run the tests and the analyzer on the new file**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Build.DevCommon.Tests.ps1 -Output Detailed; Invoke-ScriptAnalyzer build/DevCommon.ps1 -Settings PSScriptAnalyzerSettings.psd1"`
Expected: all pass, 0 findings.

- [ ] **Step 5: Commit**

```bash
git add build/DevCommon.ps1 tests/Build.DevCommon.Tests.ps1
git commit -m "Add shared helpers for the dev scripts"
```

---

### Task 7: `build/Invoke-Checks.ps1`

**Files:**
- Create: `build/Invoke-Checks.ps1`, `tests/Build.InvokeChecks.Tests.ps1`

**Interfaces:**
- Consumes: everything in `build/DevCommon.ps1`.
- Produces: `Invoke-Checks.ps1 [-Edition pwsh|desktop|both] [-SkipAnalyzer] [-Pester] [-OutJson <path>]`; writes a table to the console and, with `-OutJson`, a JSON array of `{ Name, Edition, Passed, Detail, Seconds }`; exit code 0 only when every row passed. Check names, exactly: `parse`, `encoding`, `analyzer`, `listtools`, `groups`, `dryrun`, `gitclean`, `pester`. `Edition` is `pwsh`, `desktop` or `n/a`.

- [ ] **Step 1: Write the failing tests** (`-Tag Build`)

```powershell
Describe 'Invoke-Checks' -Tag Build {
    BeforeAll { $script = "$PSScriptRoot\..\build\Invoke-Checks.ps1"; $json = "$TestDrive\checks.json" }
    It 'passes on the current tree and writes JSON' {
        & pwsh -NoProfile -File $script -OutJson $json | Out-Null
        $LASTEXITCODE | Should -Be 0
        $rows = Get-Content $json -Raw | ConvertFrom-Json
        ($rows.Name | Sort-Object -Unique) | Should -Be @('analyzer', 'dryrun', 'encoding', 'gitclean', 'groups', 'listtools', 'parse')
        ($rows | Where-Object Name -eq 'listtools').Edition | Sort-Object | Should -Be @('desktop', 'pwsh')
        $rows.Passed | Should -Not -Contain $false
    }
    It 'works when started from another directory' { Push-Location $TestDrive; try { & pwsh -NoProfile -File $script -SkipAnalyzer -Edition pwsh | Out-Null; $LASTEXITCODE | Should -Be 0 } finally { Pop-Location } }
    It 'fails when the tool count in listtools disagrees with tools.yaml' {
        # Simulated by pointing the script at a copy of the repo whose tools.yaml has one extra placeholder entry that the script refuses? No: the count is read from the same file, so instead corrupt a copy of ToolFetcher.ps1 to print a wrong count.
        $copy = Join-Path $TestDrive 'repo'; Copy-Item "$PSScriptRoot\.." $copy -Recurse -Exclude '.git'
        (Get-Content "$copy\ToolFetcher.ps1" -Raw).Replace('Total Tools: $($Tools.Count)', 'Total Tools: 1') | Set-Content "$copy\ToolFetcher.ps1" -NoNewline
        & pwsh -NoProfile -File "$copy\build\Invoke-Checks.ps1" -SkipAnalyzer -Edition pwsh | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
    }
}
```

Keep the first two tests; implement the third only if the copy runs in under a minute, otherwise replace it with a test that `-OutJson` records `Passed = $false` for `gitclean` when a stray file is created in the copy before the run.

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement `build/Invoke-Checks.ps1`**

Each check is a function returning the row object; `listtools` compares the printed `Total Tools: N` with `Get-ToolEntryCount`; `groups` runs `-ListTools -ToolsFile <group>` for every group except `_tool_template.yaml` under pwsh; `dryrun` passes `-ToolsDirectory` under `[IO.Path]::GetTempPath()\ToolFetcherChecks_<pid>` and asserts the folder does not exist afterwards; `gitclean` compares `git status --porcelain` before and after; `pester` runs `Invoke-Pester -Path tests -ExcludeTag Build, Network -PassThru` under each edition via `Invoke-Edition` on a one-line wrapper (`-Command` is acceptable here because the wrapper is not the product script) and passes when `FailedCount` is 0. Console output: `Format-Table Name, Edition, Passed, Seconds, Detail -AutoSize`.

- [ ] **Step 4: Run the tests, then the script itself with `-Pester`**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Build.InvokeChecks.Tests.ps1 -Output Detailed"` then `pwsh -NoProfile -File build/Invoke-Checks.ps1 -Pester`
Expected: tests pass; the script prints a table with every row `True` and exits 0; `Invoke-ScriptAnalyzer build/Invoke-Checks.ps1 -Settings PSScriptAnalyzerSettings.psd1` reports 0.

- [ ] **Step 5: Commit**

```bash
git add build/Invoke-Checks.ps1 tests/Build.InvokeChecks.Tests.ps1
git commit -m "Add Invoke-Checks.ps1 to run the verification steps on both editions"
```

---

### Task 8: `build/New-Release.ps1`

**Files:**
- Create: `build/New-Release.ps1`, `tests/Build.NewRelease.Tests.ps1`

**Interfaces:**
- Consumes: `build/DevCommon.ps1`; `build/Invoke-Checks.ps1` (invoked unless `-SkipChecks`).
- Produces: `New-Release.ps1 -Version <x.y.z> [-Date <yyyy-MM-dd>] [-RepoRoot <path>] [-SkipChecks] [-WhatIf]` returning `[pscustomobject]@{ Version; ZipPath; NotesPath; Commands [string[]] }`. Internal functions, defined in the same file so tests can dot-source it with `-AsLibrary`:
  - `Get-ReleaseFileList -RepoRoot` -> relative paths: `ToolFetcher.ps1`, `tools.yaml`, `README.md`, `CHANGELOG.md`, `LICENSE`, every `tool_groups\*.yaml` (template included), sorted.
  - `New-ReleaseZip -RepoRoot -Version -OutDir` -> zip path; entries named `ToolFetcher/<relative path with forward slashes>`; files copied byte for byte (CRLF kept).
  - `Test-ReleaseZip -ZipPath -RepoRoot -Version` -> `[bool]`; entry set equals `Get-ReleaseFileList`, each entry's CR-stripped SHA256 equals the working file's CR-stripped SHA256, and the embedded script contains `$script:Version = "<Version>"`.
  - `Update-ReleaseVersion -RepoRoot -Version -Date` edits the three files; `Get-ChangelogSection -RepoRoot -Version` -> body text; `Get-ReleaseCommands -RepoRoot -Version -ZipPath -NotesPath` -> the printed commands in this order: commit, merge (only when the current branch is not `main`, as `git checkout main && git merge --no-ff <branch>`), `git tag -a v<V> -m "ToolFetcher <V>"`, `git push --dry-run origin main`, `git push --dry-run origin v<V>`, `gh release create v<V> "<zip>" --title "ToolFetcher <V>" --notes-file "<notes>"`.

- [ ] **Step 1: Write the failing tests** (`-Tag Build`); they work on a throwaway clone so the real tree is never touched

```powershell
Describe 'New-Release' -Tag Build {
    BeforeAll {
        . "$PSScriptRoot\..\build\New-Release.ps1" -AsLibrary
        $clone = Join-Path $TestDrive 'clone'; git clone -q (Resolve-Path "$PSScriptRoot\..") $clone
        git -C $clone config user.email 't@example.invalid'; git -C $clone config user.name 't'
    }
    It 'lists exactly the shipped file set' { (Get-ReleaseFileList -RepoRoot $clone) | Should -Contain 'tool_groups\_tool_template.yaml'; (Get-ReleaseFileList -RepoRoot $clone).Count | Should -Be ((Get-ChildItem "$clone\tool_groups\*.yaml").Count + 5) }
    It 'builds and verifies a zip with the ToolFetcher/ prefix' {
        $zip = New-ReleaseZip -RepoRoot $clone -Version (Get-ScriptSetting -Name Version -ScriptPath "$clone\ToolFetcher.ps1") -OutDir "$TestDrive\dist"
        $names = [IO.Compression.ZipFile]::OpenRead($zip).Entries.FullName
        $names | Should -Contain 'ToolFetcher/ToolFetcher.ps1'; $names | Should -Contain 'ToolFetcher/LICENSE'
        Test-ReleaseZip -ZipPath $zip -RepoRoot $clone -Version (Get-ScriptSetting -Name Version -ScriptPath "$clone\ToolFetcher.ps1") | Should -BeTrue
    }
    It 'refuses when Unreleased has no bullet' {
        $c = (Get-Content "$clone\CHANGELOG.md" -Raw) -replace '(?s)## \[Unreleased\].*?(?=## \[\d)', "## [Unreleased]`r`n`r`n"
        Set-Content "$clone\CHANGELOG.md" $c -NoNewline
        { & "$PSScriptRoot\..\build\New-Release.ps1" -Version 9.9.9 -RepoRoot $clone -SkipChecks } | Should -Throw '*Unreleased*'
        git -C $clone checkout -q -- CHANGELOG.md
    }
    It 'bumps version, heading and writes notes and commands' {
        $r = & "$PSScriptRoot\..\build\New-Release.ps1" -Version 9.9.9 -Date 2026-01-02 -RepoRoot $clone -SkipChecks
        Get-ScriptSetting -Name Version -ScriptPath "$clone\ToolFetcher.ps1" | Should -Be '9.9.9'
        (Get-Content "$clone\README.md")[0] | Should -Be '# ToolFetcher (v9.9.9)'
        Get-Content "$clone\CHANGELOG.md" | Should -Contain '## [9.9.9] - 2026-01-02'
        Test-Path $r.ZipPath | Should -BeTrue; Test-Path $r.NotesPath | Should -BeTrue
        (Get-Content $r.NotesPath -Raw) | Should -Match 'Full changelog: https://github.com/kev365/ToolFetcher/blob/main/CHANGELOG.md'
        ($r.Commands -join "`n") | Should -Match 'git tag -a v9\.9\.9 -m "ToolFetcher 9\.9\.9"'
        ($r.Commands -join "`n") | Should -Match 'gh release create v9\.9\.9'
        ($r.Commands -join "`n") | Should -Not -Match '^git push origin'   # only dry-runs are printed
    }
    It 'changes nothing with -WhatIf' { git -C $clone checkout -q -- . ; & "$PSScriptRoot\..\build\New-Release.ps1" -Version 8.8.8 -RepoRoot $clone -SkipChecks -WhatIf | Out-Null; git -C $clone status --porcelain | Should -BeNullOrEmpty }
}
```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement `build/New-Release.ps1`**

`[CmdletBinding(SupportsShouldProcess)]`; `-AsLibrary` switch returns after defining functions. Preconditions, in order: `-Version` matches `^\d+\.\d+\.\d+$`; `git status --porcelain` empty (skipped when `-WhatIf`); `$script:Version` in the file equals the README title version; `## [Unreleased]` exists and the text up to the next `## [` contains at least one line starting with `- `; `Invoke-Checks.ps1 -SkipAnalyzer:$false` passes unless `-SkipChecks`. Zip via `[IO.Compression.ZipFile]::Open($path, 'Create')` and `CreateEntryFromFile`. `dist/` under `-RepoRoot`.

- [ ] **Step 4: Run tests, analyzer, and a real rehearsal with `-WhatIf` on this tree**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Build.NewRelease.Tests.ps1 -Output Detailed; Invoke-ScriptAnalyzer build/New-Release.ps1 -Settings PSScriptAnalyzerSettings.psd1"` then `pwsh -NoProfile -File build/New-Release.ps1 -Version 2.2.3 -WhatIf`
Expected: tests pass, 0 findings, the rehearsal prints the six commands and `git status --porcelain` stays empty.

- [ ] **Step 5: Commit**

```bash
git add build/New-Release.ps1 tests/Build.NewRelease.Tests.ps1
git commit -m "Add New-Release.ps1 to bump, package and verify a release"
```

---

### Task 9: Audit logic without the network

**Files:**
- Create: `build/AuditFunctions.ps1`, `tests/Build.Audit.Tests.ps1`, `tests/fixtures/audit-regressions.yaml`

**Interfaces:**
- Consumes: `Select-ReleaseAsset -ToolConfig -Assets -All` (Task 5); `$script:AssetPatterns`; `Get-HttpErrorInfo` shape `@{ StatusCode; RetryAfter; RateLimitRemaining; RateLimitReset; RateLimited }`.
- Produces (dot-sourced by Task 10's script after `ToolFetcher.ps1 -SourceOnly`):
  - `ConvertTo-GitHubRepoRef -Url [string]` -> `[pscustomobject]@{ Owner; Repo }` or `$null`; strips a trailing `/`, `.git`, and anything after the repo segment (`/releases/...`, `/raw/...`).
  - `Get-ToolEntryKey -Tool` -> lowercase string joined with `|` from `RepoUrl` (normalized: trailing `/` and `.git` removed), `DownloadMethod`, `Branch`, `DownloadName`, `AssetFilename`, `AssetType`, `SpecificFilePath`.
  - `Get-UniqueToolEntries -Tools [object[]]` -> entries, each with an added `Sources` array of `"<file>:<Name>"`, one per distinct key; order of first appearance.
  - `Get-AuditSelection -Tool -AssetNames [string[]]` -> `[pscustomobject]@{ Matches [string[]]; Selected [string]; Ambiguous [bool]; SignatureFirst [bool] }` where `SignatureFirst` is true when `Selected` ends in `.asc`, `.sig` or `.sha256`.
  - `Test-VersionLockedUrl -Url` -> the version string found in the last two path segments (`\d+\.\d+(\.\d+)*`), else `$null`.
  - `Get-AuditStatus -Record` -> `ok | warn | broken | skipped | transient` from these fields on the record: `SkipDownload`, `Transient`, `RepoMissing`, `BranchMissing`, `Moved`, `Archived`, `Selected`, `Ambiguous`, `SignatureFirst`, `HttpStatus`, `ContentType`, `ExpectBinary`, `VersionLocked`. Rules: `SkipDownload` -> `skipped`; `Transient` -> `transient`; `RepoMissing` or `BranchMissing` or (latestRelease and no `Selected`) or `SignatureFirst` or `HttpStatus -ge 400` or (`ExpectBinary` and `ContentType -like 'text/html*'`) -> `broken`; `Moved` or `Archived` or `Ambiguous` or `VersionLocked` -> `warn`; else `ok`.
  - `New-RateLimitGate` -> an object with `.Tripped` (bool) and `.Observe($info)` that sets `Tripped` when `$info.RateLimited` is true, so callers skip further GitHub calls and mark records `Transient`.

- [ ] **Step 1: Write the fixture** `tests/fixtures/audit-regressions.yaml` with `category: "audit-regressions"` and five entries, each with a comment naming the expected status:

`EZ-net9` specificFile `https://download.ericzimmermanstools.com/net9/PECmd.zip` (broken); `APT-Hunter-zip` latestRelease `https://github.com/ahmedkhlief/APT-Hunter` with `DownloadName: "APT-Hunter.zip"` (broken); `Forensic-Timeliner-old` branchZip `https://github.com/acquiredsecurity/forensic-timeliner` main (broken); `Loki2-old` latestRelease `https://github.com/Neo23x0/Loki2` with `AssetFilename: "loki-windows-x86_64-v.*\\.zip$"` (warn, moved); `ExifTool-13.59` specificFile `https://sourceforge.net/projects/exiftool/files/exiftool-13.59_64.zip/download` with `DownloadName: "exiftool-13.59_64.zip"` (warn, version-locked).

- [ ] **Step 2: Write the failing tests** (`-Tag Build`, no network)

```powershell
Describe 'Audit functions' -Tag Build {
    BeforeAll { . "$PSScriptRoot\..\ToolFetcher.ps1" -SourceOnly; . "$PSScriptRoot\..\build\AuditFunctions.ps1"; . "$PSScriptRoot\TestHelpers.ps1" }
    It 'parses owner and repo from <_>' -ForEach 'https://github.com/O/R', 'https://github.com/O/R/', 'https://github.com/O/R.git', 'https://github.com/O/R/releases/latest/download/x.exe' { $ref = ConvertTo-GitHubRepoRef -Url $_; $ref.Owner | Should -Be 'O'; $ref.Repo | Should -Be 'R' }
    It 'returns null for a non-GitHub URL' { ConvertTo-GitHubRepoRef -Url 'https://www.nirsoft.net/utils/x.zip' | Should -BeNullOrEmpty }
    It 'dedupes entries that differ only by trailing slash or .git' {
        $t = @(@{ Name = 'a'; RepoUrl = 'https://github.com/O/R'; DownloadMethod = 'branchZip'; Branch = 'main' }, @{ Name = 'b'; RepoUrl = 'https://github.com/O/R/'; DownloadMethod = 'branchZip'; Branch = 'main' }, @{ Name = 'c'; RepoUrl = 'https://github.com/O/R.git'; DownloadMethod = 'branchZip'; Branch = 'main' })
        $u = Get-UniqueToolEntries -Tools $t; $u.Count | Should -Be 1; $u[0].Sources.Count | Should -Be 3
    }
    It 'keeps entries with different selectors apart' { (Get-UniqueToolEntries -Tools @(@{ Name='a'; RepoUrl='https://github.com/O/R'; DownloadMethod='latestRelease'; DownloadName='x.exe' }, @{ Name='b'; RepoUrl='https://github.com/O/R'; DownloadMethod='latestRelease'; DownloadName='y.exe' })).Count | Should -Be 2 }
    It 'flags a signature file selected first' { $s = Get-AuditSelection -Tool @{ AssetFilename = 'tool.*\.7z' } -AssetNames 'tool.7z.asc', 'tool.7z'; $s.SignatureFirst | Should -BeTrue; $s.Ambiguous | Should -BeTrue }
    It 'reports a clean single match' { $s = Get-AuditSelection -Tool @{ DownloadName = 'a.zip' } -AssetNames 'a.zip', 'b.zip'; $s.Selected | Should -Be 'a.zip'; $s.Ambiguous | Should -BeFalse }
    It 'detects a version in a URL' { Test-VersionLockedUrl -Url 'https://sourceforge.net/projects/exiftool/files/exiftool-13.59_64.zip/download' | Should -Be '13.59'; Test-VersionLockedUrl -Url 'https://download.sysinternals.com/files/SysinternalsSuite.zip' | Should -BeNullOrEmpty }
    It 'applies the status rules' {
        (Get-AuditStatus -Record @{ SkipDownload = $true; RepoMissing = $true }) | Should -Be 'skipped'
        (Get-AuditStatus -Record @{ Transient = $true }) | Should -Be 'transient'
        (Get-AuditStatus -Record @{ Moved = $true }) | Should -Be 'warn'
        (Get-AuditStatus -Record @{ SignatureFirst = $true; Selected = 'x.asc' }) | Should -Be 'broken'
        (Get-AuditStatus -Record @{ HttpStatus = 206; ExpectBinary = $true; ContentType = 'application/zip' }) | Should -Be 'ok'
        (Get-AuditStatus -Record @{ HttpStatus = 200; ExpectBinary = $true; ContentType = 'text/html; charset=utf-8' }) | Should -Be 'broken'
    }
    It 'trips the rate-limit gate' { $g = New-RateLimitGate; $g.Observe(@{ RateLimited = $false }); $g.Tripped | Should -BeFalse; $g.Observe(@{ RateLimited = $true }); $g.Tripped | Should -BeTrue }
    It 'loads the regression fixture through the product validator' { Import-PinnedYaml; $cfg = Add-ConfigurationDefaults -Config (ConvertFrom-Yaml (Get-Content "$PSScriptRoot\fixtures\audit-regressions.yaml" -Raw)); (Test-ToolConfiguration -Config $cfg).IsValid | Should -BeTrue; $cfg.tools.Count | Should -Be 5 }
}
```

(`Import-PinnedYaml` comes from `build/DevCommon.ps1`; dot-source it in `BeforeAll` too.)

- [ ] **Step 3: Run to verify failure**

- [ ] **Step 4: Implement `build/AuditFunctions.ps1`** with the functions above; `Get-AuditSelection` wraps `Select-ReleaseAsset -All` over `New-FakeAsset`-shaped objects built from the names.

- [ ] **Step 5: Run tests and analyzer**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Build.Audit.Tests.ps1 -Output Detailed; Invoke-ScriptAnalyzer build/AuditFunctions.ps1 -Settings PSScriptAnalyzerSettings.psd1"`
Expected: all pass, 0 findings.

- [ ] **Step 6: Commit**

```bash
git add build/AuditFunctions.ps1 tests/Build.Audit.Tests.ps1 tests/fixtures/audit-regressions.yaml
git commit -m "Add network-free audit logic and the regression fixture"
```

---

### Task 10: `build/Test-ToolDefinitions.ps1`

**Files:**
- Create: `build/Test-ToolDefinitions.ps1`, `tests/Build.AuditNetwork.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 6 and 9; from the product script: `Invoke-GitHubApi` (returns `@{ Ok; StatusCode; Data; ETag; NotModified; RateLimited; Error; FinalUri; Moved }`), `Get-GitHubHeaders`, `Resolve-ToolsFileContent -Path -DefaultUrl`, `Add-ConfigurationDefaults`, `Test-ToolConfiguration`.
- Produces: `Test-ToolDefinitions.ps1 [-ToolsFile <path[]>] [-GitHubPAT <string>] [-OutFile <path>] [-Download] [-PassThru]`; default `-ToolsFile` is `tools.yaml` plus every `tool_groups\*.yaml` except the template; token precedence `-GitHubPAT`, `$env:GH_TOKEN`, `$env:GITHUB_TOKEN`, anonymous with a warning; exit 1 when any record has status `broken`. Record fields: `Name`, `Sources`, `Method`, `RepoUrl`, `Status`, `Detail`, `Latest`, `Published`, `Selected`, `Matches`, `FullName`, `Archived`, `LastCommit`, `HttpStatus`, `FinalUrl`, `Length`, `LastModified`, `ContentType`, `VersionLocked`, `Transient`. Network helpers in the same file: `Get-GitHubRepoState`, `Get-LatestReleaseState`, `Get-BranchState`, `Get-DirectUrlState -Url` (ranged GET via `Invoke-WebRequest -UseBasicParsing -Headers @{ Range = 'bytes=0-0' } -MaximumRedirection 10 -SkipHttpErrorCheck -TimeoutSec 30`, with `-OperationTimeoutSeconds 30`; HEAD is never used). `-Download` runs `ToolFetcher.ps1` once per tools file into `[IO.Path]::GetTempPath()\ToolFetcherAudit_<pid>\<file>` with `-Log` and the token, and appends each run's `Run summary` line and `failed` lines to the report under `Downloads`.

- [ ] **Step 1: Write the failing network tests** (`-Tag Build, Network`)

```powershell
Describe 'Test-ToolDefinitions against the fixture' -Tag Build, Network {
    BeforeAll { $r = & "$PSScriptRoot\..\build\Test-ToolDefinitions.ps1" -ToolsFile "$PSScriptRoot\fixtures\audit-regressions.yaml" -GitHubPAT (gh auth token) -PassThru; $exit = $LASTEXITCODE }
    It 'exits 1 because the fixture holds broken entries' { $exit | Should -Be 1 }
    It 'reports <Name> as <Status>' -ForEach @(@{ Name='EZ-net9'; Status='broken' }, @{ Name='APT-Hunter-zip'; Status='broken' }, @{ Name='Forensic-Timeliner-old'; Status='broken' }, @{ Name='Loki2-old'; Status='warn' }, @{ Name='ExifTool-13.59'; Status='warn' }) { ($r | Where-Object Name -eq $Name).Status | Should -Be $Status }
    It 'names the new location of a moved repository' { ($r | Where-Object Name -eq 'Loki2-old').FullName | Should -Be 'Neo23x0/Loki-RS' }
}
Describe 'Test-ToolDefinitions against the shipped definitions' -Tag Build, Network {
    It 'reports every entry ok, warn or skipped and exits 0' { $r = & "$PSScriptRoot\..\build\Test-ToolDefinitions.ps1" -GitHubPAT (gh auth token) -PassThru; $LASTEXITCODE | Should -Be 0; ($r.Status | Sort-Object -Unique) | Should -BeIn @('ok', 'warn', 'skipped') }
}
```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement `build/Test-ToolDefinitions.ps1`**

Load order: `DevCommon.ps1`, `ToolFetcher.ps1 -SourceOnly`, `AuditFunctions.ps1`. Per unique entry choose the probe by method; one `New-RateLimitGate` shared across GitHub calls; every network call wrapped so exceptions become `Transient = $true` with the message in `Detail`. Console: `Format-Table Status, Name, Method, Detail -AutoSize` sorted `broken`, `warn`, `transient`, `ok`, `skipped`. The token goes only into request headers built by `Get-GitHubHeaders`; it is never written to the report, the console or the log. ExifTool: when the normalized URL host is `sourceforge.net` and the project is `exiftool`, fetch `https://exiftool.org/ver.txt` and put `current <ver>` in `Detail`.

- [ ] **Step 4: Run the network tests, the analyzer, and one `-Download` run on the fixture**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Build.AuditNetwork.Tests.ps1 -Output Detailed; Invoke-ScriptAnalyzer build/Test-ToolDefinitions.ps1 -Settings PSScriptAnalyzerSettings.psd1"` then `pwsh -NoProfile -File build/Test-ToolDefinitions.ps1 -ToolsFile tests/fixtures/audit-regressions.yaml -GitHubPAT (gh auth token) -Download -OutFile $env:TEMP\audit.json`
Expected: tests pass; 0 findings; the download section reports the fixture's failures and the JSON file contains no token (`Select-String -Path $env:TEMP\audit.json -Pattern 'gh[po]_'` finds nothing).

- [ ] **Step 5: Commit**

```bash
git add build/Test-ToolDefinitions.ps1 tests/Build.AuditNetwork.Tests.ps1
git commit -m "Add Test-ToolDefinitions.ps1, the upstream audit of every tool entry"
```

---

### Task 11: Module installer and GitHub Actions workflows

**Files:**
- Create: `build/Install-DevModules.ps1`, `.github/workflows/checks.yml`, `.github/workflows/upstream-audit.yml`

**Interfaces:**
- Produces: `Install-DevModules.ps1 [-Edition pwsh|desktop|both]` installs, for the current user, `powershell-yaml` at `Get-ScriptSetting RequiredYamlVersion`, `PSScriptAnalyzer` 1.25.0 and `Pester` minimum 5.5, each with `-Force -SkipPublisherCheck -AllowClobber`; the `desktop` leg runs the same `Install-Module` line through `& powershell.exe -NoProfile -Command`. Idempotent.

- [ ] **Step 1: Write `build/Install-DevModules.ps1`** and run it locally for both editions

Run: `pwsh -NoProfile -File build/Install-DevModules.ps1`
Expected: completes without error; `Get-Module -ListAvailable powershell-yaml, PSScriptAnalyzer, Pester` under each edition shows the pinned versions.

- [ ] **Step 2: Write `.github/workflows/checks.yml`**

Triggers: `push` (all branches) and `pull_request`. One job on `windows-latest`: `actions/checkout@v4`; `pwsh -File build/Install-DevModules.ps1`; `pwsh -File build/Invoke-Checks.ps1 -Pester -OutJson checks.json`; `pwsh -Command "Invoke-Pester tests -Tag Build -ExcludeTag Network -CI"`; `actions/upload-artifact@v4` with `checks.json` and `tests/TestResults/` using `if: always()`.

- [ ] **Step 3: Write `.github/workflows/upstream-audit.yml`**

Triggers: `schedule: - cron: '0 6 1 * *'` and `workflow_dispatch`. One job on `windows-latest`: checkout; `Install-DevModules.ps1`; `pwsh -File build/Test-ToolDefinitions.ps1 -OutFile audit.json` with `env: GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`; upload `audit.json` with `if: always()`. No download mode.

- [ ] **Step 4: Validate the workflow files locally**

Run: `pwsh -NoProfile -Command "Import-PinnedYaml; Get-ChildItem .github/workflows/*.yml | ForEach-Object { $y = ConvertFrom-Yaml (Get-Content $_ -Raw); '{0}: jobs={1}' -f $_.Name, ($y.jobs.Keys -join ',') }"` and `Invoke-ScriptAnalyzer build/Install-DevModules.ps1 -Settings PSScriptAnalyzerSettings.psd1`
Expected: both files parse with one job each; 0 findings. The workflows cannot be exercised until the branch is pushed, which needs the owner's approval; note this in the task report.

- [ ] **Step 5: Commit**

```bash
git add build/Install-DevModules.ps1 .github/workflows/checks.yml .github/workflows/upstream-audit.yml
git commit -m "Add module installer and GitHub Actions workflows for checks and the monthly audit"
```

---

### Task 12: Documentation

**Files:**
- Modify: `CHANGELOG.md`, `README.md`, `CLAUDE.md` (gitignored, local), `docs/superpowers/specs/2026-11-04-dev-tooling-design.md` (status line only)

- [ ] **Step 1: CHANGELOG** under `## [Unreleased]`, new `### Added` subsection before `### Changed`, one bullet: "Development tooling under `build/`: `Invoke-Checks.ps1` runs the verification steps on both editions, `New-Release.ps1` bumps, packages and verifies a release and prints the publish commands, `Test-ToolDefinitions.ps1` audits every tool entry against its upstream; a Pester suite under `tests/`; GitHub Actions run the checks on every push and the audit monthly. `Select-ReleaseAsset` is extracted from `Resolve-ToolRemote` with unchanged behavior."

- [ ] **Step 2: README** add a short "Development" section after "Security Considerations": how to run `build/Install-DevModules.ps1`, `build/Invoke-Checks.ps1 -Pester`, `build/Test-ToolDefinitions.ps1 -PromptForPAT` style guidance (recommend `-GitHubPAT (gh auth token)` in a local shell, never in docs examples with a literal), and that releases go through `build/New-Release.ps1`.

- [ ] **Step 3: CLAUDE.md** replace the "Verifying changes" list with: run `pwsh -File build/Invoke-Checks.ps1 -Pester`; keep the four manual steps as a fallback paragraph without the tool count; in "Git rules" point releases at `build/New-Release.ps1 -Version X.Y.Z` followed by the printed commands; add a line that `build/Test-ToolDefinitions.ps1` is the upstream audit and the `Network` and `Build` test tags.

- [ ] **Step 4: Design status** change the status line of the design to "Status: implemented 2026-11-xx on branch dev-tooling".

- [ ] **Step 5: Run the full check one last time and commit**

Run: `pwsh -NoProfile -File build/Invoke-Checks.ps1 -Pester` then `pwsh -NoProfile -Command "Invoke-Pester tests -Tag Build -ExcludeTag Network"`
Expected: every row passes; Build tests green.

```bash
git add CHANGELOG.md README.md docs/superpowers/specs/2026-11-04-dev-tooling-design.md
git commit -m "Document the development tooling"
```

---

## Self-review notes

- Spec coverage: components 1 to 6 map to Tasks 7, 8, 9 and 10, 2 to 5, 11 and 1 respectively; the CHANGELOG, README and CLAUDE.md items are Task 12; owner decisions 2 to 5 are encoded in Tasks 1, 8 and 11.
- The fixture replaces the v2.2.1 acceptance test as decided after the builder check; `-Download` is local only (Task 10) and absent from the workflow (Task 11).
- Names used across tasks: `Get-ScriptSetting`, `Import-PinnedYaml`, `Invoke-Edition`, `Test-TextEncoding`, `Get-ToolEntryCount` (Task 6) are consumed by Tasks 7 to 11; `Select-ReleaseAsset -All` (Task 5) by Task 9; `New-FakeAsset`, `New-TestZip`, `New-TestFile`, `New-FakeHttpException` (Tasks 2 and 4) by Tasks 3 to 9.
- Review Focus items 1 to 5 are pinned by tests in Tasks 7, 8, 9, 9 and 3.
