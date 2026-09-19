#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Write-Output ('PowerShell: ' + $PSVersionTable.PSVersion.ToString())
$files = Get-Content -LiteralPath (Join-Path $root 'scripts\source-files.json') -Raw | ConvertFrom-Json
foreach ($relative in $files) {
    if ($relative -match '\.ps(m)?1$') {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative), [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw ('PowerShell syntax errors in ' + $relative) }
    }
}
Write-Output 'PASS: PowerShell syntax'
foreach ($suite in @('Test-Backup.ps1', 'Test-Restore.ps1', 'Test-Safety.ps1', 'Test-Lifecycle.ps1', 'Test-Cli.ps1', 'Test-Package.ps1')) {
    & (Join-Path $PSScriptRoot $suite)
}
& (Join-Path $PSScriptRoot 'Check-Privacy.ps1')
Write-Output 'PASS: all required checks'
exit 0
