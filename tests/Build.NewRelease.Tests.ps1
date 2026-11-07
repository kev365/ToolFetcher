Describe 'New-Release' -Tag Build {
    BeforeAll {
        . "$PSScriptRoot\..\build\New-Release.ps1" -AsLibrary
        $clone = Join-Path $TestDrive 'clone'; git clone -q (Resolve-Path "$PSScriptRoot\..") $clone
        git -C $clone config user.email 't@example.invalid'; git -C $clone config user.name 't'
        # A clone has a local branch only for the checkout's HEAD; the release flow merges into main, so
        # give the clone one (at HEAD, which the seed commit below then moves ahead of).
        if (-not (git -C $clone rev-parse --verify --quiet main)) { git -C $clone branch main HEAD }
        # Right after a release the CHANGELOG has no Unreleased section, and New-Release refuses to run
        # without one. Seed a minimal section in the clone and commit it there, so these tests do not
        # depend on where the repo is in its release cycle.
        $changelog = Join-Path $clone 'CHANGELOG.md'
        $text = [IO.File]::ReadAllText($changelog)
        if ($text -notmatch '(?m)^## \[Unreleased\]') {
            $seed = "## [Unreleased]`r`n`r`n### Changed`r`n`r`n- Seeded by Build.NewRelease.Tests.ps1 so the release flow has an entry to release.`r`n`r`n"
            $first = [regex]::Match($text, '(?m)^## \[\d')
            if (-not $first.Success) { throw 'CHANGELOG.md has no version heading to seed before' }
            [IO.File]::WriteAllText($changelog, $text.Insert($first.Index, $seed), [Text.UTF8Encoding]::new($false))
            git -C $clone add CHANGELOG.md
            git -C $clone commit -q -m 'Seed an Unreleased section for the release tests'
        }
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
    It 'refuses when main is not an ancestor of HEAD' {
        # main moved on after the branch was cut: merging the branch would give the tag a tree the zip was not built from.
        $behind = Join-Path $TestDrive 'clone-behind'; git clone -q $clone $behind
        git -C $behind config user.email 't@example.invalid'; git -C $behind config user.name 't'
        git -C $behind checkout -q -b feature
        git -C $behind branch -f main HEAD
        git -C $behind checkout -q main
        Set-Content (Join-Path $behind 'hotfix.txt') 'main moved on'
        git -C $behind add hotfix.txt; git -C $behind commit -q -m 'main moves ahead of the feature branch'
        git -C $behind checkout -q feature
        { & "$PSScriptRoot\..\build\New-Release.ps1" -Version 9.9.9 -RepoRoot $behind -SkipChecks } | Should -Throw '*ancestor*'
        git -C $behind status --porcelain | Should -BeNullOrEmpty
    }
    It 'Update-ReleaseVersion reports whether it wrote' {
        git -C $clone checkout -q -- .
        Update-ReleaseVersion -RepoRoot $clone -Version 7.7.7 -Date 2026-01-02 -WhatIf | Should -Be $false
        git -C $clone status --porcelain | Should -BeNullOrEmpty
        Update-ReleaseVersion -RepoRoot $clone -Version 7.7.7 -Date 2026-01-02 | Should -Be $true
        Get-ScriptSetting -Name Version -ScriptPath "$clone\ToolFetcher.ps1" | Should -Be '7.7.7'
        git -C $clone checkout -q -- .
    }
    It 'names the files to undo when a later write fails' {
        git -C $clone checkout -q -- .
        $readme = Get-Item "$clone\README.md"
        $readme.IsReadOnly = $true
        try {
            # ToolFetcher.ps1 is written first, then README.md fails: the error must say what to undo.
            { Update-ReleaseVersion -RepoRoot $clone -Version 6.6.6 -Date 2026-01-02 } | Should -Throw '*git checkout -- ToolFetcher.ps1*'
            Get-ScriptSetting -Name Version -ScriptPath "$clone\ToolFetcher.ps1" | Should -Be '6.6.6'
        }
        finally {
            $readme.IsReadOnly = $false
            git -C $clone checkout -q -- .
        }
    }
    It 'leaves the tree untouched when the confirmation cannot be answered' {
        git -C $clone checkout -q -- .
        # -Confirm in a non-interactive host cannot prompt; the run must stop before any write.
        & pwsh -NoProfile -NonInteractive -File "$PSScriptRoot\..\build\New-Release.ps1" -Version 5.5.5 -RepoRoot $clone -SkipChecks -Confirm 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        git -C $clone status --porcelain | Should -BeNullOrEmpty
        Test-Path "$clone\dist\ToolFetcher-5.5.5.zip" | Should -BeFalse
    }
    It 'bumps version, heading and writes notes and commands' {
        $r = & "$PSScriptRoot\..\build\New-Release.ps1" -Version 9.9.9 -Date 2026-01-02 -RepoRoot $clone -SkipChecks
        Get-ScriptSetting -Name Version -ScriptPath "$clone\ToolFetcher.ps1" | Should -Be '9.9.9'
        (Get-Content "$clone\README.md")[0] | Should -Be '# ToolFetcher (v9.9.9)'
        Get-Content "$clone\CHANGELOG.md" | Should -Contain '## [9.9.9] - 2026-01-02'
        Test-Path $r.ZipPath | Should -BeTrue; Test-Path $r.NotesPath | Should -BeTrue
        (Get-Content $r.NotesPath -Raw) | Should -Match 'Full changelog: https://github.com/kev365/ToolFetcher/blob/main/CHANGELOG.md'
        # The commit carries a bullet body: one -m per bullet line of the new CHANGELOG section.
        $r.Commands[0] | Should -BeLike "git commit -m `"Release 9.9.9`" -m '- *' -- ToolFetcher.ps1 README.md CHANGELOG.md"
        $bullets = @([regex]::Split((Get-ChangelogSection -RepoRoot $clone -Version 9.9.9), '\r?\n') -cmatch '^- ')
        [regex]::Matches($r.Commands[0], " -m '- ").Count | Should -Be $bullets.Count
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
