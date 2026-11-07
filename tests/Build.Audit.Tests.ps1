Describe 'Audit functions' -Tag Build {
    BeforeAll {
        . "$PSScriptRoot\..\ToolFetcher.ps1" -SourceOnly
        . "$PSScriptRoot\..\build\DevCommon.ps1"
        . "$PSScriptRoot\..\build\AuditFunctions.ps1"
        . "$PSScriptRoot\TestHelpers.ps1"
    }
    It 'parses owner and repo from <_>' -ForEach 'https://github.com/O/R', 'https://github.com/O/R/', 'https://github.com/O/R.git', 'https://github.com/O/R/releases/latest/download/x.exe' {
        $ref = ConvertTo-GitHubRepoRef -Url $_
        $ref.Owner | Should -Be 'O'
        $ref.Repo | Should -Be 'R'
    }
    It 'returns null for a non-GitHub URL' { ConvertTo-GitHubRepoRef -Url 'https://www.nirsoft.net/utils/x.zip' | Should -BeNullOrEmpty }
    It 'returns null for the lookalike or repo-less URL <_>' -ForEach 'https://github.com.evil.example/O/R', 'https://notgithub.com/O/R', 'https://raw.githubusercontent.com/O/R/main/x.ps1', 'https://github.com/O', 'https://github.com/' {
        ConvertTo-GitHubRepoRef -Url $_ | Should -BeNullOrEmpty
    }
    It 'accepts www., a query string and a /raw/ path' {
        (ConvertTo-GitHubRepoRef -Url 'https://www.github.com/O/R').Repo | Should -Be 'R'
        (ConvertTo-GitHubRepoRef -Url 'https://github.com/O/R?tab=readme').Repo | Should -Be 'R'
        (ConvertTo-GitHubRepoRef -Url 'https://github.com/O/R/raw/main/x.ps1').Owner | Should -Be 'O'
    }
    It 'keeps first-appearance order and folds case into one key' {
        $u = Get-UniqueToolEntries -Tools @(
            @{ Name = 'z'; RepoUrl = 'https://github.com/O/R2'; DownloadMethod = 'branchZip'; Branch = 'main'; SourceFile = 'a.yaml' },
            @{ Name = 'a'; RepoUrl = 'https://github.com/O/R1'; DownloadMethod = 'branchZip'; Branch = 'main'; SourceFile = 'a.yaml' },
            @{ Name = 'a'; RepoUrl = 'https://GitHub.com/o/r1/'; DownloadMethod = 'branchZip'; Branch = 'MAIN'; SourceFile = 'b.yaml' }
        )
        $u.Count | Should -Be 2
        $u[0].Name | Should -Be 'z'
        $u[1].Sources | Should -Be @('a.yaml:a', 'b.yaml:a')
        Get-ToolEntryKey -Tool $u[1] | Should -Be 'https://github.com/o/r1|branchzip|main||||'
    }
    It 'dedupes entries that differ only by trailing slash or .git' {
        $t = @(
            @{ Name = 'a'; RepoUrl = 'https://github.com/O/R'; DownloadMethod = 'branchZip'; Branch = 'main' },
            @{ Name = 'b'; RepoUrl = 'https://github.com/O/R/'; DownloadMethod = 'branchZip'; Branch = 'main' },
            @{ Name = 'c'; RepoUrl = 'https://github.com/O/R.git'; DownloadMethod = 'branchZip'; Branch = 'main' }
        )
        $u = Get-UniqueToolEntries -Tools $t
        $u.Count | Should -Be 1
        $u[0].Sources.Count | Should -Be 3
    }
    It 'keeps entries with different selectors apart' {
        (Get-UniqueToolEntries -Tools @(
            @{ Name = 'a'; RepoUrl = 'https://github.com/O/R'; DownloadMethod = 'latestRelease'; DownloadName = 'x.exe' },
            @{ Name = 'b'; RepoUrl = 'https://github.com/O/R'; DownloadMethod = 'latestRelease'; DownloadName = 'y.exe' }
        )).Count | Should -Be 2
    }
    It 'flags a signature file selected first' {
        $s = Get-AuditSelection -Tool @{ AssetFilename = 'tool.*\.7z' } -AssetNames 'tool.7z.asc', 'tool.7z'
        $s.SignatureFirst | Should -BeTrue
        $s.Ambiguous | Should -BeTrue
    }
    It 'reports a clean single match' {
        $s = Get-AuditSelection -Tool @{ DownloadName = 'a.zip' } -AssetNames 'a.zip', 'b.zip'
        $s.Selected | Should -Be 'a.zip'
        $s.Ambiguous | Should -BeFalse
    }
    It 'reports no match and a single match precisely' {
        $none = Get-AuditSelection -Tool @{ DownloadName = 'nope.zip' } -AssetNames 'a.zip'
        $none.Matches.Count | Should -Be 0; $none.Selected | Should -BeNullOrEmpty; $none.Ambiguous | Should -BeFalse; $none.SignatureFirst | Should -BeFalse
        (Get-AuditSelection -Tool @{} -AssetNames @()).Matches.Count | Should -Be 0
        $one = Get-AuditSelection -Tool @{ AssetFilename = 'win-x64\.zip$' } -AssetNames 't-win-x64.zip', 't-win-x64.zip.sha256', 't-linux.tar.gz'
        $one.Matches.Count | Should -Be 1; $one.Matches[0] | Should -Be 't-win-x64.zip'; $one.Ambiguous | Should -BeFalse
    }
    It 'detects a version in a URL' {
        Test-VersionLockedUrl -Url 'https://sourceforge.net/projects/exiftool/files/exiftool-13.59_64.zip/download' | Should -Be '13.59'
        Test-VersionLockedUrl -Url 'https://download.sysinternals.com/files/SysinternalsSuite.zip' | Should -BeNullOrEmpty
    }
    It 'applies the status rules' {
        (Get-AuditStatus -Record @{ SkipDownload = $true; RepoMissing = $true }) | Should -Be 'skipped'
        (Get-AuditStatus -Record @{ Transient = $true }) | Should -Be 'transient'
        (Get-AuditStatus -Record @{ Moved = $true }) | Should -Be 'warn'
        (Get-AuditStatus -Record @{ Blocked = $true; DownloadMethod = 'latestRelease' }) | Should -Be 'warn'
        (Get-AuditStatus -Record @{ SignatureFirst = $true; Selected = 'x.asc' }) | Should -Be 'broken'
        (Get-AuditStatus -Record @{ HttpStatus = 206; ExpectBinary = $true; ContentType = 'application/zip' }) | Should -Be 'ok'
        (Get-AuditStatus -Record @{ HttpStatus = 200; ExpectBinary = $true; ContentType = 'text/html; charset=utf-8' }) | Should -Be 'broken'
    }
    It 'ranks BranchMissing as broken and keeps the rule precedence' {
        (Get-AuditStatus -Record @{ BranchMissing = $true; DownloadMethod = 'branchZip' }) | Should -Be 'broken'
        (Get-AuditStatus -Record @{ SkipDownload = $true; Transient = $true }) | Should -Be 'skipped'
        (Get-AuditStatus -Record @{ Transient = $true; RepoMissing = $true }) | Should -Be 'transient'
        (Get-AuditStatus -Record @{ RepoMissing = $true; Moved = $true }) | Should -Be 'broken'
        (Get-AuditStatus -Record @{ DownloadMethod = 'latestRelease' }) | Should -Be 'broken'
        (Get-AuditStatus -Record @{ DownloadMethod = 'branchZip' }) | Should -Be 'ok'
        (Get-AuditStatus -Record @{ HttpStatus = 404 }) | Should -Be 'broken'
        (Get-AuditStatus -Record @{ HttpStatus = 200; ContentType = 'text/html' }) | Should -Be 'ok'
        foreach ($flag in 'Archived', 'Ambiguous', 'VersionLocked') { (Get-AuditStatus -Record @{ $flag = $true }) | Should -Be 'warn' }
    }
    It 'trips the rate-limit gate' {
        $g = New-RateLimitGate
        $g.Observe(@{ RateLimited = $false })
        $g.Tripped | Should -BeFalse
        $g.Observe(@{ RateLimited = $true })
        $g.Tripped | Should -BeTrue
    }
    It 'keeps the gate tripped after a later clean response' {
        $g = New-RateLimitGate
        $g.Observe(@{ RateLimited = $true }); $g.Observe(@{ RateLimited = $false }); $g.Observe($null)
        $g.Tripped | Should -BeTrue
    }
    It 'loads the regression fixture through the product validator' {
        Import-PinnedYaml
        $cfg = Add-ConfigurationDefaults -Config (ConvertFrom-Yaml (Get-Content "$PSScriptRoot\fixtures\audit-regressions.yaml" -Raw))
        (Test-ToolConfiguration -Config $cfg).IsValid | Should -BeTrue
        $cfg.tools.Count | Should -Be 5
    }
}

Describe 'Get-DirectUrlState' -Tag Build {
    BeforeAll {
        . "$PSScriptRoot\..\ToolFetcher.ps1" -SourceOnly
        # The probe lives in the audit script, which has no library mode: lift it and its date helper from the AST.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "$PSScriptRoot\..\build\Test-ToolDefinitions.ps1").Path, [ref]$null, [ref]$null)
        foreach ($name in 'Get-DirectUrlState', 'ConvertTo-IsoDate') {
            $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
            if (-not $fn) { throw "$name not found in Test-ToolDefinitions.ps1" }
            . ([scriptblock]::Create($fn.Extent.Text))
        }
        if (-not $script:UserAgent) { $script:UserAgent = 'ToolFetcher-tests' }
        Mock Start-Sleep {}
    }
    It 'reports an HTTPS-to-HTTP downgrade as unresolved without retrying' {
        Mock Invoke-WebRequest {
            $er = [System.Management.Automation.ErrorRecord]::new([System.Net.Http.HttpRequestException]::new('insecure'), 'InsecureRedirection,Microsoft.PowerShell.Commands.InvokeWebRequestCommand', 'InvalidOperation', $null)
            throw $er
        }
        $s = Get-DirectUrlState -Url 'https://example.invalid/x.zip'
        $s.Unresolved | Should -BeTrue; $s.Transient | Should -BeFalse; $s.Responded | Should -BeFalse
        $s.Error | Should -Match 'HTTPS to HTTP'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }
    It 'reports a 3xx after the redirect limit as unresolved and strips the Location query' {
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 302; Headers = @{ Location = 'https://cdn.example.invalid/x.zip?token=SECRET' }; BaseResponse = $null } }
        $s = Get-DirectUrlState -Url 'https://example.invalid/x.zip'
        $s.Unresolved | Should -BeTrue; $s.Responded | Should -BeTrue; $s.HttpStatus | Should -Be 302
        $s.Error | Should -Match 'redirect not resolved after 10 redirects'
        $s.Error | Should -Match 'cdn\.example\.invalid/x\.zip'
        $s.Error | Should -Not -Match 'SECRET'
    }
    It 'retries a 503 once and then reports it transient' {
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 503; Headers = @{}; BaseResponse = $null } }
        $s = Get-DirectUrlState -Url 'https://example.invalid/x.zip'
        $s.Transient | Should -BeTrue; $s.Error | Should -Be 'HTTP 503 after a retry'
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 2 }
    }
    It 'reports a network failure as transient after one retry' {
        Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('No such host is known.') }
        $s = Get-DirectUrlState -Url 'https://nohost.invalid/x.zip'
        $s.Transient | Should -BeTrue; $s.Responded | Should -BeFalse
        $s.Error | Should -Match 'request failed: No such host'
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly
    }
    It 'reads the total length from a ranged 206' {
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 206; Headers = @{ 'Content-Type' = 'application/zip'; 'Content-Range' = 'bytes 0-0/12345' }; BaseResponse = $null } }
        $s = Get-DirectUrlState -Url 'https://example.invalid/x.zip'
        $s.Responded | Should -BeTrue; $s.HttpStatus | Should -Be 206; $s.Length | Should -Be 12345; $s.ContentType | Should -Be 'application/zip'
        $s.Transient | Should -BeFalse; $s.Unresolved | Should -BeFalse
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }
}
