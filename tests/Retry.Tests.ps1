BeforeAll {
    . (Join-Path $PSScriptRoot '..\ToolFetcher.ps1') -SourceOnly
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Invoke-WithRetry' {
    BeforeAll {
        # No real waiting and no console noise: the delay is proven through the mock's parameters.
        Mock Start-Sleep {}
        Mock Write-LogWarning {}
    }
    BeforeEach { $script:n = 0 }

    It 'returns the result on first success' {
        Invoke-WithRetry -ScriptBlock { 42 } -DelaysSeconds @(0) | Should -Be 42
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }
    It 'does not retry a 404' {
        { Invoke-WithRetry -ScriptBlock { $script:n++; throw (New-FakeHttpException 404) } -DelaysSeconds @(0, 0) } | Should -Throw -ExpectedMessage 'HTTP 404'
        $script:n | Should -Be 1
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }
    It 'does not retry a 403' {
        { Invoke-WithRetry -ScriptBlock { $script:n++; throw (New-FakeHttpException 403) } -DelaysSeconds @(0, 0) } | Should -Throw -ExpectedMessage 'HTTP 403'
        $script:n | Should -Be 1
    }
    It 'retries a 500 up to MaxAttempts with the configured delays' {
        { Invoke-WithRetry -ScriptBlock { $script:n++; throw (New-FakeHttpException 500) } -MaxAttempts 3 -DelaysSeconds @(3, 5, 7) } | Should -Throw -ExpectedMessage 'HTTP 500'
        $script:n | Should -Be 3
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 3 }
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 5 }
        Should -Invoke Start-Sleep -Times 2 -Exactly
        Should -Invoke Write-LogWarning -Times 2 -Exactly
    }
    It 'retries a connection error and then succeeds' {
        $result = Invoke-WithRetry -ScriptBlock { $script:n++; if ($script:n -lt 2) { throw [System.Net.WebException]::new('reset') }; 'ok' } -DelaysSeconds @(4, 0)
        $result | Should -Be 'ok'
        $script:n | Should -Be 2
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 4 }
    }
    It 'honours a short Retry-After on 429' {
        $result = Invoke-WithRetry -ScriptBlock { $script:n++; if ($script:n -lt 2) { throw (New-FakeHttpException 429 -RetryAfter '1') }; 'ok' } -DelaysSeconds @(9, 9)
        $result | Should -Be 'ok'
        $script:n | Should -Be 2
        # Retry-After wins over the configured delay.
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 1 }
    }
    It 'does not honour a long Retry-After on 429' {
        { Invoke-WithRetry -ScriptBlock { $script:n++; throw (New-FakeHttpException 429 -RetryAfter '600') } -DelaysSeconds @(0, 0) } | Should -Throw -ExpectedMessage 'HTTP 429'
        $script:n | Should -Be 1
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }
}
