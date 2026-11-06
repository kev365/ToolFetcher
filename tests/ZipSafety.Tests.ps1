BeforeAll {
    . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Expand-ZipSafely' {
    It 'extracts a normal zip and returns the file count' {
        $z = New-TestZip "$TestDrive\ok.zip" @{ 'a.txt' = 'A'; 'sub/b.txt' = 'B' }
        Expand-ZipSafely -ZipPath $z -DestinationPath "$TestDrive\out1" | Should -Be 2
        Get-Content "$TestDrive\out1\sub\b.txt" | Should -Be 'B'
    }
    It 'refuses an entry that escapes with ..' {
        $z = New-TestZip "$TestDrive\slip.zip" @{ '../evil.txt' = 'X' }
        { Expand-ZipSafely -ZipPath $z -DestinationPath "$TestDrive\out2" } | Should -Throw
        Test-Path "$TestDrive\evil.txt" | Should -BeFalse
    }
    It 'refuses an absolute entry path' {
        $z = New-TestZip "$TestDrive\abs.zip" @{ 'C:/Windows/evil.txt' = 'X' }
        { Expand-ZipSafely -ZipPath $z -DestinationPath "$TestDrive\out3" } | Should -Throw
    }
    It 'handles backslash separators and directory entries' {
        $z = New-TestZip "$TestDrive\bs.zip" @{ 'dir\' = $null; 'dir\c.txt' = 'C' }
        Expand-ZipSafely -ZipPath $z -DestinationPath "$TestDrive\out4" | Should -Be 1
        Test-Path "$TestDrive\out4\dir\c.txt" | Should -BeTrue
    }
}
