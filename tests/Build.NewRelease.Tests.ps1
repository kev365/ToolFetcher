Describe 'New-Release' -Tag Build {
    BeforeAll {
        . "$PSScriptRoot\..\build\New-Release.ps1" -AsLibrary
        $clone = Join-Path $TestDrive 'clone'; git clone -q (Resolve-Path "$PSScriptRoot\..") $clone
        git -C $clone config user.email 't@example.invalid'; git -C $clone config user.name 't'
    }
    It 'lists exactly the shipped file set' { (Get-ReleaseFileList -RepoRoot $clone) | Should -Contain 'tool_groups\_tool_template.yaml'; (Get-ReleaseFileList -RepoRoot $clone).Count | Should -Be ((Get-ChildItem "$clone\tool_groups\*.yaml").Count + 5) }
    It 'builds and verifies a zip with the ToolFetcher/ prefix' {
        $zip = New-ReleaseZip -RepoRoot $clone -Version (Get-ScriptSetting -Name Version -ScriptPath "$clone\ToolFetcher.ps1") -OutDir "$TestDrive\dist"
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try { $names = $archive.Entries.FullName } finally { $archive.Dispose() }
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
        # Only dry-runs are printed: no command line may push for real, and both dry-run lines are present.
        ($r.Commands | Where-Object { $_ -match '^git push origin' }) | Should -BeNullOrEmpty
        ($r.Commands | Where-Object { $_ -match '^git push --dry-run origin' }).Count | Should -Be 2
    }
    It 'changes nothing with -WhatIf' {
        git -C $clone checkout -q -- .
        & "$PSScriptRoot\..\build\New-Release.ps1" -Version 8.8.8 -RepoRoot $clone -SkipChecks -WhatIf | Out-Null
        git -C $clone status --porcelain | Should -BeNullOrEmpty
        # dist/ is ignored, so git status cannot see it; check the two outputs directly.
        Test-Path "$clone\dist\ToolFetcher-8.8.8.zip" | Should -BeFalse
        Test-Path "$clone\dist\release-notes-8.8.8.md" | Should -BeFalse
    }
}
