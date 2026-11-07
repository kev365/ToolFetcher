BeforeAll {
    . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Initialize-OutputFolder' {
    It 'creates a nested relative folder under the tools directory' {
        $p = Initialize-OutputFolder -ToolConfig @{ Name = 'T'; OutputFolder = 'a\b' } -ToolsDirectory "$TestDrive\tools"
        $p | Should -Be (Join-Path "$TestDrive\tools" 'a\b\T')
        Test-Path $p | Should -BeTrue
    }
    It 'returns null for a traversal OutputFolder' { Initialize-OutputFolder -ToolConfig @{ Name = 'T'; OutputFolder = '..\x' } -ToolsDirectory "$TestDrive\tools" | Should -BeNullOrEmpty }
    It 'returns null for a drive-prefixed OutputFolder' { Initialize-OutputFolder -ToolConfig @{ Name = 'T'; OutputFolder = 'D:\x' } -ToolsDirectory "$TestDrive\tools" | Should -BeNullOrEmpty }
    It 'creates nothing for a drive-prefixed OutputFolder' {
        $null = Initialize-OutputFolder -ToolConfig @{ Name = 'T'; OutputFolder = 'D:\x' } -ToolsDirectory "$TestDrive\tools2"
        Get-ChildItem "$TestDrive\tools2" -Recurse -Directory -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}
