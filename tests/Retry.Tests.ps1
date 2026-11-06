BeforeAll {
    . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Invoke-WithRetry' {
    BeforeEach { $script:n = 0 }

    It 'returns the result on first success' {
        Invoke-WithRetry -ScriptBlock { 42 } -DelaysSeconds @(0) | Should -Be 42
    }
    It 'does not retry a 404' {
        { Invoke-WithRetry -ScriptBlock { $script:n++; throw (New-FakeHttpException 404) } -DelaysSeconds @(0, 0) } | Should -Throw
        $script:n | Should -Be 1
    }
    It 'does not retry a 403' {
        { Invoke-WithRetry -ScriptBlock { $script:n++; throw (New-FakeHttpException 403) } -DelaysSeconds @(0, 0) } | Should -Throw
        $script:n | Should -Be 1
    }
    It 'retries a 500 up to MaxAttempts' {
        { Invoke-WithRetry -ScriptBlock { $script:n++; throw (New-FakeHttpException 500) } -MaxAttempts 3 -DelaysSeconds @(0, 0, 0) } | Should -Throw
        $script:n | Should -Be 3
    }
    It 'retries a connection error and then succeeds' {
        $result = Invoke-WithRetry -ScriptBlock { $script:n++; if ($script:n -lt 2) { throw [System.Net.WebException]::new('reset') }; 'ok' } -DelaysSeconds @(0, 0)
        $result | Should -Be 'ok'
        $script:n | Should -Be 2
    }
    It 'honours a short Retry-After on 429' {
        $result = Invoke-WithRetry -ScriptBlock { $script:n++; if ($script:n -lt 2) { throw (New-FakeHttpException 429 -RetryAfter '1') }; 'ok' } -DelaysSeconds @(0, 0)
        $result | Should -Be 'ok'
        $script:n | Should -Be 2
    }
}
