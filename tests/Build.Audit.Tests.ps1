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
    It 'detects a version in a URL' {
        Test-VersionLockedUrl -Url 'https://sourceforge.net/projects/exiftool/files/exiftool-13.59_64.zip/download' | Should -Be '13.59'
        Test-VersionLockedUrl -Url 'https://download.sysinternals.com/files/SysinternalsSuite.zip' | Should -BeNullOrEmpty
    }
    It 'applies the status rules' {
        (Get-AuditStatus -Record @{ SkipDownload = $true; RepoMissing = $true }) | Should -Be 'skipped'
        (Get-AuditStatus -Record @{ Transient = $true }) | Should -Be 'transient'
        (Get-AuditStatus -Record @{ Moved = $true }) | Should -Be 'warn'
        (Get-AuditStatus -Record @{ SignatureFirst = $true; Selected = 'x.asc' }) | Should -Be 'broken'
        (Get-AuditStatus -Record @{ HttpStatus = 206; ExpectBinary = $true; ContentType = 'application/zip' }) | Should -Be 'ok'
        (Get-AuditStatus -Record @{ HttpStatus = 200; ExpectBinary = $true; ContentType = 'text/html; charset=utf-8' }) | Should -Be 'broken'
    }
    It 'trips the rate-limit gate' {
        $g = New-RateLimitGate
        $g.Observe(@{ RateLimited = $false })
        $g.Tripped | Should -BeFalse
        $g.Observe(@{ RateLimited = $true })
        $g.Tripped | Should -BeTrue
    }
    It 'loads the regression fixture through the product validator' {
        Import-PinnedYaml
        $cfg = Add-ConfigurationDefaults -Config (ConvertFrom-Yaml (Get-Content "$PSScriptRoot\fixtures\audit-regressions.yaml" -Raw))
        (Test-ToolConfiguration -Config $cfg).IsValid | Should -BeTrue
        $cfg.tools.Count | Should -Be 5
    }
}
