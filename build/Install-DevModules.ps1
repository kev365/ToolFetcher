#Requires -Version 7
<#
.SYNOPSIS
    Installs the modules the dev tooling needs, for the current user.
.DESCRIPTION
    powershell-yaml (the version pinned in ToolFetcher.ps1), PSScriptAnalyzer 1.25.0 and
    Pester 5.x (5.5 up to, but not including, 6). Modules already present at a matching
    version are skipped, so a repeat run changes nothing.
.PARAMETER Edition
    pwsh, desktop (Windows PowerShell 5.1) or both.
#>
[CmdletBinding()]
param(
    [ValidateSet('pwsh', 'desktop', 'both')][string]$Edition = 'both'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DevCommon.ps1')

$yamlVersion = Get-ScriptSetting -Name RequiredYamlVersion

# Name, minimum version, maximum version ('' for exact-pin modules).
$modules = @(
    @{ Name = 'powershell-yaml'; Min = $yamlVersion; Max = $yamlVersion; Exact = $true }
    @{ Name = 'PSScriptAnalyzer'; Min = '1.25.0'; Max = '1.25.0'; Exact = $true }
    @{ Name = 'Pester'; Min = '5.5'; Max = '5.99.99'; Exact = $false }
)

# The same logic runs in both editions; it is passed to Windows PowerShell as text.
$installBlock = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { Write-Verbose 'TLS setting skipped' }
if ($PSVersionTable.PSVersion.Major -lt 6 -and -not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
}
foreach ($spec in @(__SPECS__)) {
    $name, $min, $max = $spec -split '\|'
    $have = Get-Module -ListAvailable -Name $name | Where-Object { $_.Version -ge [version]$min -and $_.Version -le [version]$max } | Select-Object -First 1
    if ($have) {
        Write-Host ("{0} {1} already installed" -f $name, $have.Version)
        continue
    }
    Install-Module -Name $name -MinimumVersion $min -MaximumVersion $max -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
    $now = Get-Module -ListAvailable -Name $name | Sort-Object Version -Descending | Select-Object -First 1
    Write-Host ("{0} {1} installed" -f $name, $now.Version)
}
'@

$specs = ($modules | ForEach-Object { "'{0}|{1}|{2}'" -f $_.Name, $_.Min, $_.Max }) -join ','
$block = $installBlock.Replace('__SPECS__', $specs)

if ($Edition -in 'pwsh', 'both') {
    Write-Output '== pwsh =='
    & ([scriptblock]::Create($block))
}

if ($Edition -in 'desktop', 'both') {
    Write-Output '== desktop =='
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $block
    if ($LASTEXITCODE -ne 0) { throw "Windows PowerShell module install failed with exit code $LASTEXITCODE" }
}
