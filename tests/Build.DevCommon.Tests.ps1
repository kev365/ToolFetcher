Describe 'DevCommon' -Tag Build {
    BeforeAll { . "$PSScriptRoot\..\build\DevCommon.ps1" }
    It 'finds the repo root' { Test-Path (Join-Path (Get-RepoRoot) 'ToolFetcher.ps1') | Should -BeTrue }
    It 'reads the version and the yaml pin' { Get-ScriptSetting -Name Version | Should -Match '^\d+\.\d+\.\d+$'; Get-ScriptSetting -Name RequiredYamlVersion | Should -Match '^\d+\.\d+\.\d+$' }
    It 'throws for an unknown setting' { { Get-ScriptSetting -Name NoSuchThing } | Should -Throw }
    It 'runs the script under pwsh and desktop' -ForEach 'pwsh', 'desktop' { $r = Invoke-Edition -Edition $_ -ScriptPath (Join-Path (Get-RepoRoot) 'ToolFetcher.ps1') -ArgumentList '-ListTools'; $r.ExitCode | Should -Be 0; ($r.Output -join "`n") | Should -Match 'Total Tools: \d+' }
    It 'reports the script as ASCII, no BOM, CRLF' { $e = Test-TextEncoding -Path (Join-Path (Get-RepoRoot) 'ToolFetcher.ps1'); $e.Ascii | Should -BeTrue; $e.Bom | Should -BeFalse; $e.Crlf | Should -BeTrue; $e.LoneLf | Should -BeFalse }
    It 'counts tools.yaml entries' { Get-ToolEntryCount -YamlPath (Join-Path (Get-RepoRoot) 'tools.yaml') | Should -BeGreaterThan 60 }
    It 'counts zero entries for an empty tools list' {
        $y = Join-Path $TestDrive 'empty.yaml'; Set-Content $y "tools: []"
        Get-ToolEntryCount -YamlPath $y | Should -Be 0
    }
    It 'throws when a YAML file has no tools key' {
        # A silent 0 would make a misnamed key look like an empty definitions file.
        $y = Join-Path $TestDrive 'notools.yaml'; Set-Content $y "tooldirectory: ''"
        { Get-ToolEntryCount -YamlPath $y } | Should -Throw '*tools*'
    }
}
