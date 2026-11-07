BeforeAll { . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly }

Describe 'Get-ToolPlan up-to-date marker refresh' {
    BeforeEach {
        $tools = Join-Path $TestDrive ('tools' + (Get-Random))
        $dir = (New-Item (Join-Path $tools 'T') -ItemType Directory -Force).FullName
        Set-Content (Join-Path $dir 'a.txt') 'A'
        # A marker written before ETags were recorded: Version and URL present, ApiETag empty.
        Write-MarkerFile -OutputFolder $dir -ToolName 'T' -DownloadMethod 'latestRelease' -DownloadURL 'https://example.invalid/y.zip' -Version 'v1' -Manifest (Get-FileManifest -Folder $dir) -HashAlgorithm 'SHA256'
        $markerPath = Join-Path $dir '.downloaded.json'
        $before = [IO.File]::ReadAllBytes($markerPath)
        $tool = @{ Name = 'T'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'latestRelease'; DownloadName = 'y.zip' }
        # Upstream unchanged, but it now carries an ETag the marker lacks.
        Mock Resolve-ToolRemote { @{ Ok = $true; NotModified = $false; Method = 'latestRelease'; Version = 'v1'; CommitHash = ''; Branch = ''; DownloadUrl = 'https://example.invalid/y.zip'; ApiETag = 'W/"etag-1"'; RemoteETag = ''; RemoteLastModified = ''; RemoteLength = '' } }
    }
    It 'reports up to date and leaves the marker untouched under -DryRun' {
        $plan = Get-ToolPlan -Tool $tool -ToolsDirectory $tools -UpdateMode 'general' -DryRun 6>$null
        $plan.Status | Should -Be 'up-to-date'
        [IO.File]::ReadAllBytes($markerPath) | Should -Be $before
    }
    It 'records the missing ETag on a real update run' {
        $plan = Get-ToolPlan -Tool $tool -ToolsDirectory $tools -UpdateMode 'general' 6>$null
        $plan.Status | Should -Be 'up-to-date'
        (Get-ToolMarker -OutputFolder $dir).ApiETag | Should -Be 'W/"etag-1"'
    }
}
