# Network tests for build/Test-ToolDefinitions.ps1: they call GitHub and the vendor sites, so they
# carry the Network tag and stay out of the CI checks job. They need a signed-in gh CLI for the token.
Describe 'Test-ToolDefinitions against the fixture' -Tag Build, Network {
    BeforeAll {
        $r = & "$PSScriptRoot\..\build\Test-ToolDefinitions.ps1" -ToolsFile "$PSScriptRoot\fixtures\audit-regressions.yaml" -GitHubPAT (gh auth token) -PassThru
        $exit = $LASTEXITCODE
    }
    It 'exits 1 because the fixture holds broken entries' { $exit | Should -Be 1 }
    It 'reports <Name> as <Status>' -ForEach @(
        @{ Name = 'EZ-net9'; Status = 'broken' },
        @{ Name = 'APT-Hunter-zip'; Status = 'broken' },
        @{ Name = 'Forensic-Timeliner-old'; Status = 'broken' },
        @{ Name = 'Loki2-old'; Status = 'warn' },
        @{ Name = 'ExifTool-13.59'; Status = 'warn' }
    ) { ($r | Where-Object Name -eq $Name).Status | Should -Be $Status }
    It 'names the new location of a moved repository' { ($r | Where-Object Name -eq 'Loki2-old').FullName | Should -Be 'Neo23x0/Loki-RS' }
}
Describe 'Test-ToolDefinitions against the shipped definitions' -Tag Build, Network {
    It 'reports every entry ok, warn or skipped and exits 0' {
        $r = & "$PSScriptRoot\..\build\Test-ToolDefinitions.ps1" -GitHubPAT (gh auth token) -PassThru
        $LASTEXITCODE | Should -Be 0
        ($r.Status | Sort-Object -Unique) | Should -BeIn @('ok', 'warn', 'skipped')
    }
}
