Describe 'Invoke-Checks' -Tag Build {
    BeforeAll {
        $script = "$PSScriptRoot\..\build\Invoke-Checks.ps1"
        $json = "$TestDrive\checks.json"
    }

    It 'passes on the current tree and writes JSON' {
        & pwsh -NoProfile -File $script -OutJson $json | Out-Null
        $LASTEXITCODE | Should -Be 0
        $rows = Get-Content $json -Raw | ConvertFrom-Json
        ($rows.Name | Sort-Object -Unique) | Should -Be @('analyzer', 'dryrun', 'encoding', 'gitclean', 'groups', 'listtools', 'parse')
        ($rows | Where-Object Name -eq 'listtools').Edition | Sort-Object | Should -Be @('desktop', 'pwsh')
        ($rows | Where-Object Name -eq 'dryrun').Edition | Sort-Object | Should -Be @('desktop', 'pwsh')
        $rows[0].PSObject.Properties.Name | Should -Be @('Name', 'Edition', 'Passed', 'Detail', 'Seconds')
        $rows.Edition | Where-Object { $_ -notin 'pwsh', 'desktop', 'n/a' } | Should -BeNullOrEmpty
        $rows.Passed | Should -Not -Contain $false
    }

    It 'works when started from another directory' {
        Push-Location $TestDrive
        try {
            & pwsh -NoProfile -File $script -SkipAnalyzer -Edition pwsh | Out-Null
            $LASTEXITCODE | Should -Be 0
        }
        finally { Pop-Location }
    }

    It 'fails when the tool count in listtools disagrees with tools.yaml' {
        # A copy of the tree without .git whose ToolFetcher.ps1 prints a wrong total.
        $root = (Resolve-Path "$PSScriptRoot\..").Path
        $copy = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path $copy | Out-Null
        Get-ChildItem -LiteralPath $root -Force |
            Where-Object { $_.Name -notin '.git', '.superpowers', 'dist' } |
            Copy-Item -Destination $copy -Recurse -Force
        $results = Join-Path $copy 'tests\TestResults'
        if (Test-Path -LiteralPath $results) { Remove-Item -LiteralPath $results -Recurse -Force }

        $text = Get-Content "$copy\ToolFetcher.ps1" -Raw
        $text.Contains('Total Tools: $($Tools.Count)') | Should -BeTrue -Because 'the test patches this exact line'
        $text.Replace('Total Tools: $($Tools.Count)', 'Total Tools: 1') | Set-Content "$copy\ToolFetcher.ps1" -NoNewline

        $copyJson = Join-Path $TestDrive 'copy.json'
        & pwsh -NoProfile -File "$copy\build\Invoke-Checks.ps1" -SkipAnalyzer -Edition pwsh -OutJson $copyJson | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        $rows = Get-Content $copyJson -Raw | ConvertFrom-Json
        ($rows | Where-Object Name -eq 'listtools').Passed | Should -Be $false
        $gitclean = $rows | Where-Object Name -eq 'gitclean'
        $gitclean.Passed | Should -Be $true
        $gitclean.Detail | Should -Be 'not a git repository'
    }
}
