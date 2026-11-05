BeforeAll {
    . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Format-RedactedMessage' {
    BeforeAll { Set-ToolFetcherRunState -State @{ GitHubPAT = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789AB'; LoggingEnabled = $false; VerboseOutput = $false; TraceOutput = $false; LogFile = ''; LogMutexName = '' } }
    AfterAll  { Set-ToolFetcherRunState -State @{ GitHubPAT = ''; LoggingEnabled = $false; VerboseOutput = $false; TraceOutput = $false; LogFile = ''; LogMutexName = '' } }
    It 'removes the literal token from a URL' { Format-RedactedMessage -Text 'https://ghp_abcdefghijklmnopqrstuvwxyz0123456789AB@github.com/x' | Should -Not -Match 'ghp_abcdef' }
    It 'removes an Authorization header value' { Format-RedactedMessage -Text 'Authorization: token ghp_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz' | Should -Not -Match 'ghp_zzzz' }
    It 'removes a fine-grained token' { Format-RedactedMessage -Text 'token github_pat_11AAAAAAA0bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' | Should -Not -Match 'github_pat_11' }
    It 'leaves ordinary text alone' { Format-RedactedMessage -Text 'Downloaded 3 files' | Should -Be 'Downloaded 3 files' }
}
