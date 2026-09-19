$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$modulePath = Join-Path $PSScriptRoot '..\src\WoWBackup.Core.psm1'
$module = Import-Module $modulePath -Force -PassThru
& $module { function script:Get-Process { @() } }
. (Join-Path $PSScriptRoot 'Test-Helpers.ps1')
$testRoot = New-TestRoot
try {
    $game = New-TestGame $testRoot
    $destination = Join-Path $testRoot 'backups'
    $backup = New-WabBackup $game $destination
    $before = Get-TestTree $game
    $denied = Join-Path $testRoot 'permission denied'
    [IO.Directory]::CreateDirectory($denied) | Out-Null
    $acl = Get-Acl -LiteralPath $denied
    $originalAcl = Get-Acl -LiteralPath $denied
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid, [Security.AccessControl.FileSystemRights]::Write, [Security.AccessControl.AccessControlType]::Deny)
    try {
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $denied -AclObject $acl
        Assert-Throws { New-WabBackup $game $denied } 'DESTINATION_UNWRITABLE'
        Assert-Throws { Restore-WabBackup -GamePath $game -ArchivePath $backup.ArchivePath -BackupDirectory $denied -Confirm:$false } 'DESTINATION_UNWRITABLE'
        Assert-Test ((Get-TestTree $game) -ceq $before) 'permission failure cannot change settings'
    } finally { Set-Acl -LiteralPath $denied -AclObject $originalAcl }

    # Simulate a hard exit between moving the old folder and installing its replacement.
    # This child can touch only the disposable fixture and never runs the dummy game.
    $child = Join-Path $testRoot 'interrupted-restore.ps1'
    $template = @'
$ErrorActionPreference = 'Stop'
$m = Import-Module '__MODULE__' -Force -PassThru
& $m {
    function script:Get-Process { @() }
    $script:moveCount = 0
    function script:Move-WabDirectory([string]$Source, [string]$Destination) {
        $script:moveCount++
        if ($script:moveCount -eq 2) { [Environment]::Exit(23) }
        [IO.Directory]::Move($Source, $Destination)
    }
}
Restore-WabBackup -GamePath '__GAME__' -ArchivePath '__ARCHIVE__' -BackupDirectory '__DESTINATION__' -Confirm:$false
'@
    $template = $template.Replace('__MODULE__', $modulePath.Replace("'", "''")).Replace('__GAME__', $game.Replace("'", "''")).Replace('__ARCHIVE__', $backup.ArchivePath.Replace("'", "''")).Replace('__DESTINATION__', $destination.Replace("'", "''"))
    [IO.File]::WriteAllText($child, $template, [Text.UTF8Encoding]::new($false))
    $engine = (Get-Process -Id $PID).Path
    & $engine -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child
    Assert-Test ($LASTEXITCODE -eq 23) 'child was interrupted during replacement'
    $markers = @(Get-ChildItem -LiteralPath $game -Directory -Force -Filter '.wow-addon-backup-restore-*')
    Assert-Test ($markers.Count -eq 1) 'hard interruption leaves a recovery marker'
    Assert-Test ([IO.File]::Exists((Join-Path $markers[0].FullName 'old\Interface\AddOns\Sample\Sample.lua'))) 'original addon data survives a hard interruption'
    $recovery = @(Get-WabBackups $destination | Where-Object { $_.Name -like 'wow-recovery-*' })
    Assert-Test ((Test-WabArchive $recovery[0].ArchivePath).Verified) 'recovery archive survives a hard interruption'
    Assert-Throws { New-WabBackup $game $destination } 'RESTORE_RECOVERY_REQUIRED'
    Assert-Throws { Restore-WabBackup -GamePath $game -ArchivePath $backup.ArchivePath -BackupDirectory $destination -Confirm:$false } 'RESTORE_RECOVERY_REQUIRED'

    $otherRoot = Join-Path $testRoot 'rollback failure'
    $otherGame = New-TestGame $otherRoot
    & $module {
        $script:testMoves = 0
        function script:Move-WabDirectory([string]$Source, [string]$Destination) {
            $script:testMoves++
            if ($script:testMoves -ge 4) { throw [IO.IOException]::new('Simulated unavailable filesystem') }
            [IO.Directory]::Move($Source, $Destination)
        }
    }
    Assert-Throws { Restore-WabBackup -GamePath $otherGame -ArchivePath $backup.ArchivePath -BackupDirectory $destination -Confirm:$false } 'ROLLBACK_FAILED'
    $failed = @(Get-ChildItem -LiteralPath $otherGame -Directory -Force -Filter '.wow-addon-backup-restore-*')
    Assert-Test ($failed.Count -eq 1) 'failed rollback retains its transaction'
    Assert-Test ([IO.File]::ReadAllText((Join-Path $failed[0].FullName 'old\WTF\Config.wtf')) -ceq 'SET synthetic "yes"') 'failed rollback preserves original settings'
    Assert-Throws { New-WabBackup $otherGame $destination } 'RESTORE_RECOVERY_REQUIRED'
    Write-TestSummary 'Lifecycle'
} finally { Remove-TestRoot $testRoot; Remove-Module $module -Force }
