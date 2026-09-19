#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Backup', 'List', 'Verify', 'Restore', 'Help')]
    [string]$Action = 'Menu',
    [string]$GamePath,
    [string]$BackupDirectory,
    [string]$ArchivePath,
    [switch]$WhatIf
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-WabInput([string]$Prompt) {
    # ConsoleHost in Windows PowerShell may ignore redirected stdin on CI/service hosts.
    # Explicitly read the supplied line there; interactive windows keep Read-Host.
    if ([Console]::IsInputRedirected) {
        Write-Host ($Prompt + ': ') -NoNewline
        return [Console]::ReadLine()
    }
    return Read-Host $Prompt
}

function Read-WabPath([string]$Prompt) {
    $answer = Read-WabInput $Prompt
    if ($null -eq $answer) { return '' }
    return $answer.Trim().Trim('"')
}
function Select-WabGame {
    if (-not $script:ChosenGame) {
        Write-Host 'Select the CLIENT subfolder containing Wow.exe, WowB.exe or WowClassic.exe.'
        Write-Host 'Examples: _classic_beta_, _retail_, _classic_ or _classic_era_.'
        $script:ChosenGame = Read-WabPath 'Paste its full folder path (blank cancels)'
    }
    if (-not $script:ChosenGame) { return $null }
    try { return Get-WabClient $script:ChosenGame } catch { $script:ChosenGame = ''; throw }
}
function Show-WabList {
    $items = @(Get-WabBackups $script:ChosenDestination)
    Write-Host ('Backup folder: ' + $script:ChosenDestination)
    if ($items.Count -eq 0) { Write-Host 'No completed backups found.' }
    for ($i = 0; $i -lt $items.Count; $i++) {
        Write-Host ('{0}. {1} ({2:N2} MiB; not checked in this list)' -f ($i + 1), $items[$i].Name, ($items[$i].Bytes / 1MB))
    }
    return ,$items
}
function Select-WabArchive {
    if ($ArchivePath) { return $ArchivePath }
    $items = Show-WabList
    $answer = Read-WabPath 'Enter a backup number or full ZIP path (blank cancels)'
    if (-not $answer) { return '' }
    [int]$number = 0
    if ([int]::TryParse($answer, [ref]$number)) {
        if ($number -lt 1 -or $number -gt $items.Count) { throw 'INVALID_SELECTION: Choose a listed number or paste a ZIP path.' }
        return $items[$number - 1].ArchivePath
    }
    return $answer
}
function Show-WabHelp {
    Write-Host @'
Step-by-step:
1. Close every World of Warcraft client.
2. Choose Back Up and paste the client subfolder path.
3. Wait for "Backup verified" before opening WoW.
4. Use List Backups to find saved ZIPs; Verify Backup checks their hashes.
5. To restore, choose the correct client and archive, then type RESTORE.
   A verified recovery backup is created before replacing any folders.
6. Keep WoW closed until restore or rollback finishes.

Included: Interface, WTF and Fonts when present.
Backups contain PRIVATE account/character names and addon settings.
Never attach your backups or local restore state to a public issue.
No uploads, telemetry, game automation or game process termination.

Use option 6 to change the client or destination for this session.
The default destination is %LOCALAPPDATA%\WoWAddonBackup\Backups.
ZIPs are not encrypted. There is no automatic backup deletion.
Read README.md for download instructions, limits and Manual Recovery.
'@
}
function Invoke-WabAction([string]$SelectedAction) {
    switch ($SelectedAction) {
        'Backup' {
            $client = Select-WabGame
            if ($null -eq $client) { Write-Host 'Cancelled.'; return }
            Write-Host ('Reading: ' + $client.Path)
            Write-Host ('Saving to: ' + $script:ChosenDestination)
            Write-Host 'Keep WoW closed. Reading and verifying larger backups can take several minutes.'
            $result = New-WabBackup -GamePath $client.Path -BackupDirectory $script:ChosenDestination
            Write-Host ('Backup verified: ' + $result.ArchivePath)
        }
        'List' { $null = Show-WabList }
        'Verify' {
            $selected = Select-WabArchive
            if (-not $selected) { Write-Host 'Cancelled.'; return }
            $verified = Test-WabArchive $selected
            Write-Host ('Archive verified: ' + $verified.ArchivePath)
            Write-Host ('Client: ' + $verified.ClientType + '; folders: ' + ($verified.Manifest.Folders -join ', '))
        }
        'Restore' {
            $client = Select-WabGame
            if ($null -eq $client) { Write-Host 'Cancelled.'; return }
            $selected = Select-WabArchive
            if (-not $selected) { Write-Host 'Cancelled.'; return }
            $verified = Test-WabArchive $selected
            if ($verified.ClientType -cne $client.ClientType) { throw 'CLIENT_MISMATCH: Select a backup from the same client type.' }
            Write-Host ('Archive: ' + $verified.ArchivePath)
            Write-Host ('Target: ' + $client.Path + ' [' + $client.ClientType + ']')
            Write-Host ('Replace folders: ' + ($verified.Manifest.Folders -join ', '))
            Write-Host ('Recovery ZIP destination: ' + $script:ChosenDestination)
            if ($WhatIf) {
                Restore-WabBackup -GamePath $client.Path -ArchivePath $selected -BackupDirectory $script:ChosenDestination -WhatIf
                return
            }
            Write-Host 'Current versions of these folders will be preserved before replacement.'
            if ((Read-WabInput 'Type RESTORE to continue (anything else cancels)') -cne 'RESTORE') { Write-Host 'Cancelled.'; return }
            $result = Restore-WabBackup -GamePath $client.Path -ArchivePath $selected -BackupDirectory $script:ChosenDestination -Confirm:$false
            Write-Host 'Restore verified.'
            Write-Host ('Recovery ZIP: ' + $result.RecoveryArchive)
            Write-Host ('Previous folders: ' + $result.PreviousFolder)
        }
        'Help' { Show-WabHelp }
    }
}
function Show-WabError($Record) {
    $message = $Record.Exception.Message
    if ($message -match '^[A-Z_]+: ') { Write-Host ('ERROR - ' + $message) -ForegroundColor Red }
    else { Write-Host 'ERROR - Operation failed. Check permissions, free disk space and files in use. If restoring, keep WoW closed and read Manual Recovery in README.md.' -ForegroundColor Red }
}
try {
    Import-Module (Join-Path $PSScriptRoot 'src\WoWBackup.Core.psm1') -Force
    $script:ChosenGame = $GamePath
    $script:ChosenDestination = $BackupDirectory
    if (-not $script:ChosenDestination) { $script:ChosenDestination = Get-WabDefaultBackupDirectory }
    if ($Action -ne 'Menu') { Invoke-WabAction $Action; exit 0 }
    while ($true) {
        Write-Host ''
        Write-Host 'WoW Addon Backup 1.0.0'
        if ($script:ChosenGame) { Write-Host ('Client: ' + $script:ChosenGame) }
        Write-Host ('Backups: ' + $script:ChosenDestination)
        Write-Host '1. Back Up'
        Write-Host '2. List Backups'
        Write-Host '3. Verify Backup'
        Write-Host '4. Restore'
        Write-Host '5. Help'
        Write-Host '6. Change Client / Backup Folder'
        Write-Host '0. Exit'
        $choice = Read-WabInput 'Choose an option'
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice -eq '0') { break }
        try {
            switch ($choice) {
                '1' { Invoke-WabAction 'Backup' }
                '2' { Invoke-WabAction 'List' }
                '3' { Invoke-WabAction 'Verify' }
                '4' { Invoke-WabAction 'Restore' }
                '5' { Invoke-WabAction 'Help' }
                '6' {
                    $script:ChosenGame = Read-WabPath 'Client folder (blank asks next time)'
                    $destination = Read-WabPath 'Backup folder (blank uses the default)'
                    if (-not $destination) { $destination = Get-WabDefaultBackupDirectory }
                    $script:ChosenDestination = $destination
                }
                default { Write-Host 'Choose a number from 0 to 6.' }
            }
        } catch { Show-WabError $_ }
    }
    exit 0
} catch { Show-WabError $_; exit 1 }
