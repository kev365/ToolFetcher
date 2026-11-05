# Shared helpers for the Pester suite. Dot-source after ToolFetcher.ps1 (-SourceOnly).

function New-TestFile {
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Bytes,
        [int]$Seed = 1
    )
    $buffer = New-Object byte[] $Bytes
    if ($Bytes -gt 0) { (New-Object System.Random $Seed).NextBytes($buffer) }
    [System.IO.File]::WriteAllBytes($Path, $buffer)
    return $Path
}

# Entry names are stored exactly as given (no normalization), so hostile names such as
# '../evil.txt' reach the extractor. A $null value (or a name ending in / or \) is a directory entry.
function New-TestZip {
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Entries
    )
    Add-Type -AssemblyName System.IO.Compression
    $fileStream = [System.IO.File]::Create($Path)
    try {
        $archive = New-Object System.IO.Compression.ZipArchive($fileStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            foreach ($name in $Entries.Keys) {
                $entry = $archive.CreateEntry([string]$name)
                $content = $Entries[$name]
                if ($null -ne $content -and -not ($name.EndsWith('/') -or $name.EndsWith('\'))) {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$content)
                    $entryStream = $entry.Open()
                    try { $entryStream.Write($bytes, 0, $bytes.Length) } finally { $entryStream.Dispose() }
                }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $fileStream.Dispose() }
    return $Path
}

function New-FakeAsset {
    param ([Parameter(Mandatory)][string]$Name)
    [pscustomobject]@{ name = $Name; browser_download_url = "https://example.invalid/$Name" }
}

# Stand-in for the exception Invoke-WebRequest throws on an HTTP error. Get-HttpErrorInfo only reads
# Exception.Response.StatusCode and Response.Headers (Get-ResponseHeader accepts an IDictionary), so a
# PowerShell class with a Response property drives it identically on Windows PowerShell 5.1 and 7+.
class FakeHttpException : System.Exception {
    [object]$Response
    FakeHttpException([string]$Message, [object]$Response) : base($Message) { $this.Response = $Response }
}

function New-FakeHttpException {
    param (
        [Parameter(Mandatory)][int]$StatusCode,
        [string]$RetryAfter = $null
    )
    $headers = @{}
    if ($RetryAfter) { $headers['Retry-After'] = $RetryAfter }
    $response = [pscustomobject]@{ StatusCode = $StatusCode; Headers = $headers }
    return [FakeHttpException]::new("HTTP $StatusCode", $response)
}
