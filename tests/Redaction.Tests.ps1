BeforeAll {
    . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Format-RedactedMessage' {
    BeforeAll { Set-ToolFetcherRunState -State @{ GitHubPAT = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789AB'; LoggingEnabled = $false; VerboseOutput = $false; TraceOutput = $false; LogFile = ''; LogMutexName = '' } }
    AfterAll  { Set-ToolFetcherRunState -State @{ GitHubPAT = ''; LoggingEnabled = $false; VerboseOutput = $false; TraceOutput = $false; LogFile = ''; LogMutexName = '' } }
    # Each case also checks the marker and the surrounding text, so an empty result cannot pass.
    It 'removes the literal token from a URL' {
        $out = Format-RedactedMessage -Text 'https://ghp_abcdefghijklmnopqrstuvwxyz0123456789AB@github.com/x'
        $out | Should -Not -Match 'ghp_abcdef'
        $out | Should -Be 'https://<REDACTED>@github.com/x'
    }
    It 'removes an Authorization header value' {
        $out = Format-RedactedMessage -Text 'Authorization: token ghp_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'
        $out | Should -Not -Match 'ghp_zzzz'
        $out | Should -Be 'Authorization: token <REDACTED>'
    }
    It 'removes a fine-grained token' {
        $out = Format-RedactedMessage -Text 'token github_pat_11AAAAAAA0bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        $out | Should -Not -Match 'github_pat_11'
        $out | Should -Be 'token <REDACTED>'
    }
    It 'leaves ordinary text alone' { Format-RedactedMessage -Text 'Downloaded 3 files' | Should -Be 'Downloaded 3 files' }
}
