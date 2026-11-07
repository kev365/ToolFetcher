#Requires -Version 7.4
# Shared helpers dot-sourced by the scripts under build/ and by the Build-tagged tests.

function Get-RepoRoot {
    # ScriptBlock.File is the file that defines this function, so the result does not
    # depend on the caller's $PSScriptRoot or current directory.
    $buildFolder = Split-Path -Parent $MyInvocation.MyCommand.ScriptBlock.File
    return (Split-Path -Parent $buildFolder)
}

function Get-ScriptSetting {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$ScriptPath = (Join-Path (Get-RepoRoot) 'ToolFetcher.ps1')
    )
    $pattern = '^\$script:' + [regex]::Escape($Name) + '\s*=\s*"([^"]+)"'
    foreach ($line in [System.IO.File]::ReadAllLines($ScriptPath)) {
        $m = [regex]::Match($line, $pattern)
        if ($m.Success) { return $m.Groups[1].Value }
    }
    throw "Setting '$Name' not found in $ScriptPath"
}

function Import-PinnedYaml {
    $version = Get-ScriptSetting -Name RequiredYamlVersion
    Import-Module powershell-yaml -RequiredVersion $version -ErrorAction Stop
}

function Invoke-Edition {
    param(
        [Parameter(Mandatory)][ValidateSet('pwsh', 'desktop')][string]$Edition,
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ArgumentList = @()
    )
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lines = @()
    $code = -1
    try {
        if ($Edition -eq 'pwsh') {
            $lines = @(& pwsh -NoProfile -File $ScriptPath @ArgumentList 2>&1 | ForEach-Object { "$_" })
        } else {
            $lines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ArgumentList 2>&1 | ForEach-Object { "$_" })
        }
        $code = $LASTEXITCODE
    } catch {
        $lines += "Invoke-Edition failed: $($_.Exception.Message)"
        $code = -1
    }
    $watch.Stop()
    [pscustomobject]@{
        Edition  = $Edition
        ExitCode = [int]$code
        Output   = [string[]]$lines
        Seconds  = $watch.Elapsed.TotalSeconds
    }
}

function Test-TextEncoding {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $ascii = $true
    $crlf = $false
    $loneLf = $false
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $b = $bytes[$i]
        if ($b -ge 0x80) { $ascii = $false }
        elseif ($b -eq 0x0A) {
            if ($i -gt 0 -and $bytes[$i - 1] -eq 0x0D) { $crlf = $true } else { $loneLf = $true }
        }
    }
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    [pscustomobject]@{ Ascii = $ascii; Bom = $bom; Crlf = $crlf; LoneLf = $loneLf }
}

function Get-ToolEntryCount {
    param([Parameter(Mandatory)][string]$YamlPath)
    Import-PinnedYaml
    $data = Get-Content -LiteralPath $YamlPath -Raw | ConvertFrom-Yaml
    # A missing key must not read as an empty file: the listing checks would compare against 0 and pass.
    if (-not ($data -is [System.Collections.IDictionary]) -or -not $data.Contains('tools')) {
        throw "$YamlPath has no top-level 'tools' key, so its entries cannot be counted"
    }
    return [int]$data['tools'].Count
}
