BeforeAll { . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly }
Describe 'ToolFetcher -SourceOnly' {
    It 'defines the hashing helper' { Get-Command Get-FileHashHex -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty }
    It 'defines Select-ReleaseAsset' { Get-Command Select-ReleaseAsset -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty }
    It 'exposes the YAML pin' { $script:RequiredYamlVersion | Should -Match '^\d+\.\d+\.\d+$' }
}
