$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Test-Helpers.ps1')
$entry = Join-Path $PSScriptRoot '..\WoWAddonBackup.ps1'
if (-not [IO.File]::Exists($entry)) { throw 'RED: command-line interface is not implemented.' }
function Invoke-TestCli([string]$Arguments, [string]$InputText = '') {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Process -Id $PID).Path
    $start.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $entry + '" ' + $Arguments
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    try {
        [void]$process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($InputText); $process.StandardInput.Close()
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'CLI test child timed out.' }
        return [pscustomobject]@{ Code = $process.ExitCode; Output = $outTask.Result; ErrorText = $errorTask.Result }
    } finally { $process.Dispose() }
}
$testRoot = New-TestRoot
try {
    $help = Invoke-TestCli '-Action Help'
    Assert-Test ($help.Code -eq 0 -and $help.Output -match 'Step-by-step') 'help works without choosing a client'
    $menu = Invoke-TestCli '' ('0' + [Environment]::NewLine)
    Assert-Test ($menu.Code -eq 0 -and $menu.Output -match 'Back Up' -and $menu.Output -match 'Restore') 'double-click entry shows a menu and exits'
    # Isolate the OS process-list boundary inside a disposable wrapper so a real
    # game session cannot influence tests. Never use this wrapper outside fixtures.
    $wrapper = Join-Path $testRoot 'cli-fixture-wrapper.ps1'
    $wrapperText = @'
param([string]$Action = 'Menu', [string]$GamePath, [string]$BackupDirectory, [string]$ArchivePath, [switch]$WhatIf)
function global:Get-Process { @() }
& '__ENTRY__' @PSBoundParameters
exit $LASTEXITCODE
'@
    $wrapperText = $wrapperText.Replace('__ENTRY__', $entry.Replace("'", "''"))
    [IO.File]::WriteAllText($wrapper, $wrapperText, [Text.UTF8Encoding]::new($false))
    $entry = $wrapper
    $game = New-TestGame $testRoot
    $destination = Join-Path $testRoot 'backups with spaces'
    $backup = Invoke-TestCli ('-Action Backup -GamePath "' + $game + '" -BackupDirectory "' + $destination + '"')
    # The OS boundary is isolated only in the disposable test wrapper.

    Assert-Test ($backup.Code -eq 0 -and $backup.Output -match 'Backup verified') 'CLI creates and verifies a backup'
    $archive = @(Get-ChildItem -LiteralPath $destination -Filter '*.zip')[0].FullName
    $list = Invoke-TestCli ('-Action List -BackupDirectory "' + $destination + '"')
    Assert-Test ($list.Code -eq 0 -and $list.Output -match 'wow-backup-') 'CLI lists backups'
    $verify = Invoke-TestCli ('-Action Verify -ArchivePath "' + $archive + '"')
    Assert-Test ($verify.Code -eq 0 -and $verify.Output -match 'Archive verified') 'CLI verifies a selected archive'
    $before = Get-TestTree $game
    $cancel = Invoke-TestCli ('-Action Restore -GamePath "' + $game + '" -ArchivePath "' + $archive + '" -BackupDirectory "' + $destination + '"') ('no' + [Environment]::NewLine)
    Assert-Test ($cancel.Code -eq 0 -and $cancel.Output -match 'Cancelled') 'restore requires the exact confirmation word'
    Assert-Test ((Get-TestTree $game) -ceq $before) 'cancelled CLI restore leaves all files untouched'
    Assert-Test (@(Get-ChildItem -LiteralPath $destination -Filter '*.zip').Count -eq 1) 'cancelled CLI restore does not write recovery files'
    [IO.File]::WriteAllText((Join-Path $game 'WTF\Config.wtf'), 'later')
    $restore = Invoke-TestCli ('-Action Restore -GamePath "' + $game + '" -ArchivePath "' + $archive + '" -BackupDirectory "' + $destination + '"') ('RESTORE' + [Environment]::NewLine)
    $restoreError = [regex]::Match($restore.Output, 'ERROR - ([A-Z_]+):').Groups[1].Value
    $restoreDetail = 'explicit CLI confirmation restores successfully; exit=' + $restore.Code + '; error=' + $restoreError + '; cancelled=' + ($restore.Output -match 'Cancelled')
    Assert-Test ($restore.Code -eq 0 -and $restore.Output -match 'Restore verified') $restoreDetail
    Assert-Test ([IO.File]::ReadAllText((Join-Path $game 'WTF\Config.wtf')) -ceq 'SET synthetic "yes"') 'CLI restores the saved bytes'
    $invalid = Invoke-TestCli ('-Action Verify -ArchivePath "' + (Join-Path $testRoot 'missing.zip') + '"')
    Assert-Test ($invalid.Code -eq 1 -and $invalid.Output -match 'INVALID_ARCHIVE') 'CLI returns a failure exit code'
    Assert-Test ($invalid.Output -notmatch [regex]::Escape($testRoot)) 'unexpected errors do not print diagnostic paths'
    Write-TestSummary 'CLI'
} finally { Remove-TestRoot $testRoot }
