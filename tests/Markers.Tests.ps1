BeforeAll {
    . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Write-MarkerFile / Get-ToolMarker' {
    It 'round-trips every field' {
        $dir = New-Item "$TestDrive\t" -ItemType Directory
        Write-MarkerFile -OutputFolder $dir -ToolName 'T' -DownloadMethod 'latestRelease' -DownloadURL 'https://x/y.zip' -Version 'v1' -Manifest @{ 'a.txt' = ('A' * 64) } -HashAlgorithm 'SHA256' -Branch 'main' -ApiETag 'W/"e"'
        $m = Get-ToolMarker -OutputFolder $dir
        $m.Tool | Should -Be 'T'; $m.Version | Should -Be 'v1'; $m.HashAlgorithm | Should -Be 'SHA256'; $m.Branch | Should -Be 'main'; $m.ApiETag | Should -Be 'W/"e"'
        (ConvertTo-ManifestTable $m.Manifest)['a.txt'] | Should -Be ('A' * 64)
    }
    It 'reads a 2.1-style marker with MD5 digests and no HashAlgorithm' {
        $dir = New-Item "$TestDrive\old" -ItemType Directory
        '{"Tool":"Old","Manifest":{"f.txt":"0123456789ABCDEF0123456789ABCDEF"}}' | Set-Content "$dir\.downloaded.json"
        $m = Get-ToolMarker -OutputFolder $dir
        Get-ManifestEntryAlgorithm -Digest $m.Manifest.'f.txt' -Declared (Get-MarkerValue -Marker $m -Name 'HashAlgorithm') | Should -Be 'MD5'
    }
    It 'returns null when no marker exists' { Get-ToolMarker -OutputFolder $TestDrive | Should -BeNullOrEmpty }
}
