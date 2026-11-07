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
    # Windows resolves these names to the tools directory itself, which the below-root check must not accept.
    It 'returns null and creates nothing for a name that resolves to the tools root: [<_>]' -ForEach '...', '.. ', '   ' {
        $tools = Join-Path $TestDrive ('norm' + (Get-Random))
        Initialize-OutputFolder -ToolConfig @{ Name = $_ } -ToolsDirectory $tools 6>$null | Should -BeNullOrEmpty
        Get-ChildItem $tools -Recurse -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
    It 'returns null for a name with a trailing dot or space: [<_>]' -ForEach 'x.', 'x ' {
        Initialize-OutputFolder -ToolConfig @{ Name = $_ } -ToolsDirectory "$TestDrive\tools3" 6>$null | Should -BeNullOrEmpty
        Test-Path "$TestDrive\tools3\x" | Should -BeFalse
    }
    It 'returns null for an OutputFolder segment that resolves away' {
        Initialize-OutputFolder -ToolConfig @{ Name = 'T'; OutputFolder = 'a\...' } -ToolsDirectory "$TestDrive\tools4" 6>$null | Should -BeNullOrEmpty
        Test-Path "$TestDrive\tools4\a\T" | Should -BeFalse
    }
}
