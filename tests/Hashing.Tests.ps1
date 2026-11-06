BeforeAll {
    . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Get-FileHashHex' {
    It 'matches Get-FileHash for SHA256 on a 3 MB file' { $f = New-TestFile "$TestDrive\big.bin" 3MB; Get-FileHashHex -Path $f | Should -Be (Get-FileHash $f -Algorithm SHA256).Hash }
    It 'matches Get-FileHash for MD5' { $f = New-TestFile "$TestDrive\m.bin" 4096; Get-FileHashHex -Path $f -Algorithm MD5 | Should -Be (Get-FileHash $f -Algorithm MD5).Hash }
    It 'hashes an empty file' { $f = New-TestFile "$TestDrive\e.bin" 0; Get-FileHashHex -Path $f | Should -Be 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855' }
    It 'returns uppercase hex' { $f = New-TestFile "$TestDrive\u.bin" 10; Get-FileHashHex -Path $f | Should -MatchExactly '^[0-9A-F]{64}$' }
}
Describe 'Get-ManifestEntryAlgorithm' {
    It 'returns MD5 for a 32-character digest' { Get-ManifestEntryAlgorithm -Digest ('A' * 32) -Declared 'SHA256' | Should -Be 'MD5' }
    It 'returns SHA256 for a 64-character digest' { Get-ManifestEntryAlgorithm -Digest ('A' * 64) -Declared 'MD5' | Should -Be 'SHA256' }
}
Describe 'ConvertTo-ManifestTable' {
    It 'is case-insensitive on paths' { (ConvertTo-ManifestTable -Manifest @{ 'Sub\File.txt' = 'X' })['sub\file.txt'] | Should -Be 'X' }
    It 'accepts a PSCustomObject from ConvertFrom-Json' { $m = '{"a.txt":"1","b.txt":"2"}' | ConvertFrom-Json; (ConvertTo-ManifestTable -Manifest $m).Count | Should -Be 2 }
    It 'returns an empty table for null' { (ConvertTo-ManifestTable -Manifest $null).Count | Should -Be 0 }
}
