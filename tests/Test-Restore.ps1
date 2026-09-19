$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = Import-Module (Join-Path $PSScriptRoot '..\src\WoWBackup.Core.psm1') -Force -PassThru
& $module { function script:Get-Process { @() } }
. (Join-Path $PSScriptRoot 'Test-Helpers.ps1')
if (-not (Get-Command Restore-WabBackup -ErrorAction SilentlyContinue)) { throw 'RED: restore has not been implemented.' }
$testRoot = New-TestRoot
try {
    $game = New-TestGame $testRoot
    $destination = Join-Path $testRoot 'backups'
    $backup = New-WabBackup $game $destination
    $originalWtf = Get-TestTree (Join-Path $game 'WTF')
    [IO.File]::WriteAllText((Join-Path $game 'WTF\Config.wtf'), 'newer settings')
    [IO.File]::WriteAllText((Join-Path $game 'WTF\later.lua'), 'later data')
    $before = Get-TestTree $game
    Restore-WabBackup -GamePath $game -ArchivePath $backup.ArchivePath -BackupDirectory $destination -WhatIf
    Assert-Test ((Get-TestTree $game) -ceq $before) 'WhatIf does not change game files'
    Assert-Test (@(Get-WabBackups $destination).Count -eq 1) 'WhatIf does not create a recovery archive'
    $result = Restore-WabBackup -GamePath $game -ArchivePath $backup.ArchivePath -BackupDirectory $destination -Confirm:$false
    Assert-Test ((Get-TestTree (Join-Path $game 'WTF')) -ceq $originalWtf) 'restore exactly replaces selected payload'
    Assert-Test ([IO.File]::ReadAllText((Join-Path $game 'Logs\skip.txt')) -ceq 'not included') 'restore preserves unrelated folders'
    Assert-Test ([IO.File]::ReadAllText((Join-Path $result.PreviousFolder 'old\WTF\later.lua')) -ceq 'later data') 'previous folders remain available after restore'
    Assert-Test ((Test-WabArchive $result.RecoveryArchive).Verified) 'recovery archive is complete and verified'
    Assert-Test (([IO.File]::GetAttributes((Join-Path $game 'Interface\AddOns\Sample\hidden.lua')) -band [IO.FileAttributes]::Hidden) -ne 0) 'restore preserves hidden file attribute'
    $other = New-TestGame $testRoot '_retail_'
    Assert-Throws { Restore-WabBackup -GamePath $other -ArchivePath $backup.ArchivePath -BackupDirectory $destination -Confirm:$false } 'CLIENT_MISMATCH'
    & $module { function script:Get-Process { [pscustomobject]@{ ProcessName = 'Wow' } } }
    Assert-Throws { Restore-WabBackup -GamePath $game -ArchivePath $backup.ArchivePath -BackupDirectory $destination -Confirm:$false } 'GAME_RUNNING'
    & $module { function script:Get-Process { @() } }
    # Fail an actual directory rename after a previous folder has been installed.
    # All successful renames, extraction, recovery backup and rollback are real.
    [IO.File]::WriteAllText((Join-Path $game 'WTF\Config.wtf'), 'must survive failed restore')
    $beforeWtf = Get-TestTree (Join-Path $game 'WTF')
    $beforeInterface = Get-TestTree (Join-Path $game 'Interface')
    & $module {
        $script:testMoves = 0
        function script:Move-WabDirectory([string]$Source, [string]$Destination) {
            $script:testMoves++
            if ($script:testMoves -eq 4) { throw [IO.IOException]::new('Simulated rename interruption') }
            [IO.Directory]::Move($Source, $Destination)
        }
    }
    Assert-Throws { Restore-WabBackup -GamePath $game -ArchivePath $backup.ArchivePath -BackupDirectory $destination -Confirm:$false } 'RESTORE_ROLLED_BACK'
    Assert-Test ((Get-TestTree (Join-Path $game 'WTF')) -ceq $beforeWtf) 'rollback restores newer settings after a failed replacement'
    Assert-Test ((Get-TestTree (Join-Path $game 'Interface')) -ceq $beforeInterface) 'rollback restores already-replaced addon folders'
    Assert-Test (@(Get-ChildItem -LiteralPath $game -Directory -Filter '.wow-addon-backup-restore-*').Count -eq 0) 'successful rollback clears the incomplete-operation marker'
    & $module { function script:Move-WabDirectory([string]$Source, [string]$Destination) { [IO.Directory]::Move($Source, $Destination) } }
    $marker = Join-Path $game '.wow-addon-backup-restore-interrupted'
    [IO.Directory]::CreateDirectory($marker) | Out-Null
    Assert-Throws { New-WabBackup $game $destination } 'RESTORE_RECOVERY_REQUIRED'
    Assert-Throws { Restore-WabBackup -GamePath $game -ArchivePath $backup.ArchivePath -BackupDirectory $destination -Confirm:$false } 'RESTORE_RECOVERY_REQUIRED'
    [IO.Directory]::Delete($marker)
    # Restoring onto a clean installed client must not require pre-existing settings.
    $cleanRoot = Join-Path $testRoot 'fresh install'
    $clean = Join-Path $cleanRoot '_classic_beta_'
    [IO.Directory]::CreateDirectory($clean) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $clean 'WowB.exe'), [byte[]]@(0))
    $cleanResult = Restore-WabBackup -GamePath $clean -ArchivePath $backup.ArchivePath -BackupDirectory $destination -Confirm:$false
    Assert-Test ((Get-TestTree (Join-Path $clean 'WTF')) -ceq $originalWtf) 'restore works on a fresh client with no settings folders'
    Assert-Test ((Test-WabArchive $cleanResult.RecoveryArchive).Manifest.Entries.Count -eq 0) 'empty recovery archive records an initially empty client'
    Write-TestSummary 'Restore'
} finally { Remove-TestRoot $testRoot; Remove-Module $module -Force }
