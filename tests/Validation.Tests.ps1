BeforeAll {
    . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Test-ToolConfiguration on shipped files' {
    It 'accepts <_>' -ForEach ((Get-ChildItem "$PSScriptRoot\..\tool_groups\*.yaml" | Where-Object Name -ne '_tool_template.yaml').FullName + "$PSScriptRoot\..\tools.yaml") {
        Import-Module powershell-yaml -RequiredVersion $script:RequiredYamlVersion
        # The script validates a merged config (@{ tooldirectory; tools }), never a raw group file.
        $yaml = ConvertFrom-Yaml (Get-Content $_ -Raw)
        $cfg = Add-ConfigurationDefaults -Config @{ tooldirectory = ''; tools = @($yaml.tools) }
        (Test-ToolConfiguration -Config $cfg).IsValid | Should -BeTrue
    }
}
Describe 'Test-ToolEntry' {
    It 'rejects a name with a path separator'  { (Test-ToolEntry -Tool @{ Name = 'a\b'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip' }).IsValid | Should -BeFalse }
    It 'rejects a name with ..'                 { (Test-ToolEntry -Tool @{ Name = '..'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip' }).IsValid | Should -BeFalse }
    It 'rejects a name that is a single dot'    { (Test-ToolEntry -Tool @{ Name = '.'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip' }).IsValid | Should -BeFalse }
    # Windows strips trailing dots and spaces from a path segment, so '...' or '.. ' resolve to the parent
    # folder itself and 'x.' to 'x'; such names must never reach the file system.
    It 'rejects a name Windows would normalize away: [<_>]' -ForEach '...', '.. ', '   ', 'name.', 'name ', ' name' { (Test-ToolEntry -Tool @{ Name = $_; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip' }).IsValid | Should -BeFalse }
    It 'accepts a name with an inner or leading dot' { (Test-ToolEntry -Tool @{ Name = 'tool.v2'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip' }).IsValid | Should -BeTrue; (Test-ToolEntry -Tool @{ Name = '.hidden'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip' }).IsValid | Should -BeTrue }
    It 'rejects an OutputFolder segment Windows would normalize away: [<_>]' -ForEach 'a\...', 'a\.. \b', 'a.\b', 'a \b', '.\a' { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip'; OutputFolder = $_ }).IsValid | Should -BeFalse }
    It 'accepts a nested OutputFolder with a trailing separator' { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip'; OutputFolder = 'x.y\z/' }).IsValid | Should -BeTrue }
    It 'rejects an unknown AssetType'           { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'latestRelease'; AssetType = 'amiga' }).IsValid | Should -BeFalse }
    It 'accepts a known AssetType in any case'  { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'latestRelease'; AssetType = 'Win64' }).IsValid | Should -BeTrue }
    It 'rejects an absolute OutputFolder'       { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'branchZip'; OutputFolder = 'C:\x' }).IsValid | Should -BeFalse }
    It 'rejects an unknown DownloadMethod'      { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'wget' }).IsValid | Should -BeFalse }
    It 'requires SpecificFilePath or DownloadName for specificFile on GitHub' { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r'; DownloadMethod = 'specificFile' }).IsValid | Should -BeFalse }
    It 'allows specificFile on a GitHub releases URL without DownloadName' { (Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'https://github.com/o/r/releases/latest/download/x.exe'; DownloadMethod = 'specificFile' }).IsValid | Should -BeTrue }
    It 'warns but accepts http://' { $r = Test-ToolEntry -Tool @{ Name = 'a'; RepoUrl = 'http://example.com/x.zip'; DownloadMethod = 'specificFile'; DownloadName = 'x.zip' }; $r.IsValid | Should -BeTrue }
}
Describe 'Placeholders and tags' {
    It 'treats an entry without RepoUrl as a placeholder' { Test-PlaceholderEntry -Tool @{ Name = 'p'; DownloadMethod = 'branchZip' } | Should -BeTrue }
    It 'treats an entry without DownloadMethod as a placeholder' { Test-PlaceholderEntry -Tool @{ Name = 'p'; RepoUrl = 'https://x' } | Should -BeTrue }
    It 'matches a tag from a list Category' { $set = [Collections.Generic.HashSet[string]]::new([string[]]@('logs'), [StringComparer]::OrdinalIgnoreCase); Test-ToolHasTag -Tool @{ Name = 't'; Category = @('misc', 'Logs') } -TagSet $set | Should -BeTrue }
}
