BeforeAll {
    . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Test-ToolIntact' {
    BeforeEach {
        $dir = (New-Item "$TestDrive\tool$(Get-Random)" -ItemType Directory).FullName
        Set-Content "$dir\a.txt" 'A'
        Set-Content "$dir\b.txt" 'B'
        Write-MarkerFile -OutputFolder $dir -ToolName 'T' -DownloadMethod 'branchZip' -DownloadURL 'https://x' -Manifest (Get-FileManifest -Folder $dir) -HashAlgorithm 'SHA256'
        $marker = Get-ToolMarker -OutputFolder $dir
    }
    It 'is true for an untouched install' {
        Test-ToolIntact -Marker $marker -OutputFolder $dir | Should -BeTrue
    }
    It 'is false when a managed file changed' {
        Set-Content "$dir\a.txt" 'changed'
        Test-ToolIntact -Marker $marker -OutputFolder $dir | Should -BeFalse
    }
    It 'is false when a managed file is missing' {
        Remove-Item "$dir\b.txt"
        Test-ToolIntact -Marker $marker -OutputFolder $dir | Should -BeFalse
    }
    It 'ignores user-added files' {
        Set-Content "$dir\notes.txt" 'mine'
        Test-ToolIntact -Marker $marker -OutputFolder $dir | Should -BeTrue
    }
}
