function Move-WabDirectory([string]$Source, [string]$Destination) {
    Assert-WabPlainPath $Source
    Assert-WabPlainPath $Destination
    [IO.Directory]::Move($Source, $Destination)
}

function Write-WabRestoreState([string]$TransactionPath, [string]$Phase, $Details) {
    Assert-WabPlainPath $TransactionPath
    $name = 'state-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json'
    $state = [ordered]@{ Phase = $Phase; WrittenUtc = [DateTime]::UtcNow.ToString('o'); Details = $Details }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($state | ConvertTo-Json -Depth 8))
    $stream = [IO.File]::Open((Join-Path $TransactionPath $name), 'CreateNew', 'Write', 'None')
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}

function Expand-WabArchive($Archive, [string]$Destination) {
    foreach ($record in $Archive.Manifest.Entries) {
        $target = Join-Path $Destination $record.Path.TrimEnd('/').Replace('/', '\')
        if (-not (Test-WabWithin $target $Destination)) { Stop-Wab 'UNSAFE_ARCHIVE_PATH' 'An archive entry escapes the staging folder.' }
        Assert-WabPlainPath $target
        if ($record.Kind -eq 'Directory') { [IO.Directory]::CreateDirectory($target) | Out-Null; continue }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        $input = $Archive.Entries[$record.Path].Open()
        $output = $null
        try {
            $output = [IO.File]::Open($target, 'CreateNew', 'Write', 'None')
            $hash = Copy-WabStream $input $output ([long]$record.Size)
            $output.Flush($true)
            if ($hash -cne $record.Sha256) { Stop-Wab 'CHECKSUM_MISMATCH' 'An extracted file failed verification.' }
        } finally { if ($output) { $output.Dispose() }; $input.Dispose() }
    }
    foreach ($record in ($Archive.Manifest.Entries | Sort-Object { $_.Path.Length } -Descending)) {
        $target = Join-Path $Destination $record.Path.TrimEnd('/').Replace('/', '\')
        $date = [DateTime]::Parse($record.LastWriteUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        if ($record.Kind -eq 'Directory') { [IO.Directory]::SetLastWriteTimeUtc($target, $date) } else { [IO.File]::SetLastWriteTimeUtc($target, $date) }
        $attributes = [int]$record.Attributes
        if ($record.Kind -eq 'Directory') { $attributes = $attributes -bor [int][IO.FileAttributes]::Directory }
        [IO.File]::SetAttributes($target, [IO.FileAttributes]$attributes)
    }
}

function Get-WabContentSignature($Entries) {
    return ((@($Entries) | Sort-Object Path | ForEach-Object { $_.Path + '|' + $_.Kind + '|' + $_.Size + '|' + $_.Sha256 + '|' + $_.Attributes }) -join [Environment]::NewLine)
}

function Restore-WabBackup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$GamePath,
        [Parameter(Mandatory)][string]$ArchivePath,
        [string]$BackupDirectory
    )
    $client = Get-WabClient $GamePath
    Assert-WabGameStopped
    Assert-WabNoInterruptedRestore $client.Path
    $lock = Enter-WabClientLock $client.Path
    $archive = $null; $transaction = $null; $mutationStarted = $false
    $movedOld = [Collections.Generic.List[string]]::new()
    $installedNew = [Collections.Generic.List[string]]::new()
    try {
        $archive = Open-WabArchive $ArchivePath
        if ($archive.ClientType -cne $client.ClientType) { Stop-Wab 'CLIENT_MISMATCH' 'The backup belongs to a different client type. Beta, retail and classic archives are not interchangeable.' }
        if (@($archive.Manifest.Folders).Count -eq 0) { Stop-Wab 'NO_PAYLOAD' 'This recovery record describes a previously empty client. It has no folders to restore; use the manual recovery guide.' }
        if (-not $PSCmdlet.ShouldProcess($client.Path, ('Replace ' + ($archive.Manifest.Folders -join ', ') + ' using this backup; first preserve current folders'))) { return }
        $destination = Get-WabBackupDirectory $BackupDirectory $client.Path
        $before = Get-WabInventory $client.Path $archive.Manifest.Folders
        $recovery = New-WabBackupInternal $client.Path $destination $archive.Manifest.Folders 'recovery'
        Assert-WabGameStopped
        $id = [guid]::NewGuid().ToString('N')
        $transaction = Join-Path $client.Path ('.wow-addon-backup-restore-' + $id)
        if (Test-Path -LiteralPath $transaction) { Stop-Wab 'CLIENT_BUSY' 'The staging directory already exists.' }
        [IO.Directory]::CreateDirectory($transaction) | Out-Null
        $newPath = Join-Path $transaction 'new'
        $oldPath = Join-Path $transaction 'old'
        $failedPath = Join-Path $transaction 'failed'
        foreach ($path in @($newPath, $oldPath, $failedPath)) { [IO.Directory]::CreateDirectory($path) | Out-Null }
        $details = [ordered]@{
            ClientPath = $client.Path; Archive = $archive.ArchivePath; RecoveryArchive = $recovery.ArchivePath
            Folders = @($archive.Manifest.Folders); OriginallyPresent = @($before.Folders)
        }
        Write-WabRestoreState $transaction 'Preparing' $details
        Expand-WabArchive $archive $newPath
        $staged = Get-WabInventory $newPath $archive.Manifest.Folders
        if ((Get-WabContentSignature $staged.Entries) -cne (Get-WabContentSignature $archive.Manifest.Entries)) { Stop-Wab 'CHECKSUM_MISMATCH' 'Staged restore contents do not match the backup.' }
        $now = Get-WabInventory $client.Path $archive.Manifest.Folders
        if (($now | ConvertTo-Json -Depth 8 -Compress) -cne ($before | ConvertTo-Json -Depth 8 -Compress)) { Stop-Wab 'SOURCE_CHANGED' 'Current settings changed after the recovery backup. Restore was cancelled.' }
        Write-WabRestoreState $transaction 'Prepared' $details
        Assert-WabGameStopped
        foreach ($folder in $archive.Manifest.Folders) {
            Assert-WabGameStopped
            $target = Join-Path $client.Path $folder
            Assert-WabPlainPath $target
            $mutationStarted = $true
            if ([IO.Directory]::Exists($target)) {
                Move-WabDirectory $target (Join-Path $oldPath $folder)
                $movedOld.Add($folder)
            }
            Move-WabDirectory (Join-Path $newPath $folder) $target
            $installedNew.Add($folder)
            Write-WabRestoreState $transaction ('Installed-' + $folder) $details
        }
        $restored = Get-WabInventory $client.Path $archive.Manifest.Folders
        if ((Get-WabContentSignature $restored.Entries) -cne (Get-WabContentSignature $archive.Manifest.Entries)) { Stop-Wab 'CHECKSUM_MISMATCH' 'Restored contents did not pass verification.' }
        Assert-WabGameStopped
        Write-WabRestoreState $transaction 'Complete' $details
        $previous = Join-Path $client.Path ('.wow-addon-backup-previous-' + $id)
        Move-WabDirectory $transaction $previous
        $transaction = $null
        return [pscustomobject]@{
            Restored = $true; RestoredFolders = @($archive.Manifest.Folders)
            RecoveryArchive = $recovery.ArchivePath; PreviousFolder = $previous
        }
    } catch {
        $originalError = $_
        if ($transaction -and [IO.Directory]::Exists($transaction)) {
            if ($mutationStarted) {
                try {
                    Assert-WabGameStopped
                    for ($i = $installedNew.Count - 1; $i -ge 0; $i--) {
                        $folder = $installedNew[$i]
                        Move-WabDirectory (Join-Path $client.Path $folder) (Join-Path $failedPath $folder)
                    }
                    for ($i = $movedOld.Count - 1; $i -ge 0; $i--) {
                        $folder = $movedOld[$i]
                        Move-WabDirectory (Join-Path $oldPath $folder) (Join-Path $client.Path $folder)
                    }
                    $rolledBack = Get-WabInventory $client.Path $archive.Manifest.Folders
                    if ((Get-WabContentSignature $rolledBack.Entries) -cne (Get-WabContentSignature $before.Entries)) { throw 'Rollback contents did not match the original snapshot.' }
                    Write-WabRestoreState $transaction 'RolledBack' $details
                    Move-WabDirectory $transaction (Join-Path $client.Path ('.wow-addon-backup-rolled-back-' + $id))
                    $transaction = $null
                } catch { Stop-Wab 'ROLLBACK_FAILED' 'Restore stopped and could not finish rollback. Original data and the recovery archive are preserved. Keep WoW closed and follow Manual Recovery in the guide.' }
                Stop-Wab 'RESTORE_ROLLED_BACK' 'Restore failed; the original folders were put back and verified. The recovery archive was retained.'
            } else {
                try { Move-WabDirectory $transaction (Join-Path $client.Path ('.wow-addon-backup-aborted-' + $id)); $transaction = $null } catch { Stop-Wab 'RESTORE_RECOVERY_REQUIRED' 'Preparation stopped. Game settings were not replaced; see the manual recovery guide.' }
            }
        }
        throw $originalError
    } finally {
        if ($archive) { $archive.Zip.Dispose(); $archive.Stream.Dispose() }
        $lock.ReleaseMutex(); $lock.Dispose()
    }
}
