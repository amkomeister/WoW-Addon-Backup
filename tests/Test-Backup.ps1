param([string]$ModulePath = (Join-Path $PSScriptRoot '..\src\WoWBackup.Core.psm1'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not (Test-Path -LiteralPath $ModulePath)) { throw 'RED: the backup module has not been implemented.' }
$module = Import-Module $ModulePath -Force -PassThru
# The filesystem and ZIP operations remain real. Only the OS process list is
# isolated so this suite cannot depend on (or interfere with) an actual game.
& $module { function script:Get-Process { @() } }
. (Join-Path $PSScriptRoot 'Test-Helpers.ps1')
$testRoot = New-TestRoot
try {
    $game = New-TestGame $testRoot
    $destination = Join-Path $testRoot 'archive store'
    $original = Get-TestTree $game
    $backup = New-WabBackup -GamePath $game -BackupDirectory $destination
    Assert-Test (Test-Path -LiteralPath $backup.ArchivePath) 'backup creates an archive'
    $verified = Test-WabArchive -ArchivePath $backup.ArchivePath
    Assert-Test ($verified.ClientType -eq 'classic-beta') 'archive identifies its client type'
    Assert-Test (@($verified.Manifest.Entries | Where-Object { $_.Path -eq 'Interface/AddOns/Sample/hidden.lua' }).Count -eq 1) 'hidden addon files are included'
    Assert-Test (@($verified.Manifest.Entries | Where-Object { $_.Path -eq 'WTF/empty/' }).Count -eq 1) 'empty directories are included'
    Assert-Test (@($verified.Manifest.Entries | Where-Object { $_.Path -like 'Logs/*' -or $_.Path -like 'Data/*' }).Count -eq 0) 'logs and game assets are excluded'
    Assert-Test ((Get-TestTree $game) -ceq $original) 'backup leaves source bytes and names unchanged'
    Assert-Test (($verified.Manifest | ConvertTo-Json -Depth 8) -notlike ('*' + $testRoot + '*')) 'manifest excludes absolute source paths'
    $second = New-WabBackup -GamePath $game -BackupDirectory $destination
    Assert-Test ($second.ArchivePath -ne $backup.ArchivePath) 'backups never overwrite earlier archives'
    Assert-Test (@(Get-WabBackups -BackupDirectory $destination).Count -eq 2) 'listing finds both completed archives'
    [IO.File]::WriteAllText((Join-Path $destination 'unfinished.zip.partial'), 'interrupted')
    Assert-Test (@(Get-WabBackups -BackupDirectory $destination).Count -eq 2) 'listing excludes incomplete archives'
    Assert-Throws { New-WabBackup -GamePath $game -BackupDirectory (Join-Path $game 'WTF\backups') } 'SOURCE_DESTINATION_OVERLAP'
    & $module { function script:Get-Process { [pscustomobject]@{ ProcessName = 'WowB' } } }
    Assert-Throws { New-WabBackup -GamePath $game -BackupDirectory $destination } 'GAME_RUNNING'
    & $module { function script:Get-Process { throw 'Process query unavailable' } }
    Assert-Throws { New-WabBackup -GamePath $game -BackupDirectory $destination } 'PROCESS_CHECK_FAILED'
    & $module { function script:Get-Process { @() } }
    $bad = Join-Path $testRoot 'broken.zip'
    [IO.File]::WriteAllText($bad, 'not a zip')
    Assert-Throws { Test-WabArchive -ArchivePath $bad } 'INVALID_ARCHIVE'
    $locked = [IO.File]::Open((Join-Path $game 'WTF\Config.wtf'), 'Open', 'ReadWrite', 'None')
    try { Assert-Throws { New-WabBackup -GamePath $game -BackupDirectory $destination } 'SOURCE_UNREADABLE' } finally { $locked.Dispose() }
    Assert-Test (@(Get-WabBackups -BackupDirectory $destination).Count -eq 2) 'failed backups do not create completed archives'
    Write-TestSummary 'Backup'
} finally {
    Remove-TestRoot $testRoot
    Remove-Module $module -Force
}
