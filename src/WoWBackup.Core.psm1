Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
$script:ToolVersion = '1.0.0'
$script:PayloadFolders = @('Interface', 'WTF', 'Fonts')
$script:MaxEntries = 100000
$script:MaxBytes = 100GB
$script:MaxFileBytes = 2GB - 1
$script:ClientTypes = @{
    '_retail_' = 'retail'; '_ptr_' = 'retail-ptr'; '_xptr_' = 'retail-xptr'; '_beta_' = 'retail-beta'
    '_classic_' = 'classic'; '_classic_ptr_' = 'classic-ptr'; '_classic_beta_' = 'classic-beta'
    '_classic_era_' = 'classic-era'; '_classic_era_ptr_' = 'classic-era-ptr'
    '_forever_' = 'forever'; '_forever_beta_' = 'forever-beta'
}

function Stop-Wab([string]$Code, [string]$Message) { throw ($Code + ': ' + $Message) }

function Get-WabFullPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { Stop-Wab 'INVALID_PATH' 'Choose a local filesystem path.' }
    try { $full = [IO.Path]::GetFullPath($Path) } catch { Stop-Wab 'INVALID_PATH' 'The path is invalid.' }
    if ($full.StartsWith('\\') -or $full -notmatch '^[A-Za-z]:\\') { Stop-Wab 'LOCAL_PATH_REQUIRED' 'Network and device paths are not supported.' }
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))
    if ($drive.DriveType -eq [IO.DriveType]::Network) { Stop-Wab 'LOCAL_PATH_REQUIRED' 'Choose a local disk or removable drive.' }
    if ($full -eq [IO.Path]::GetPathRoot($full)) { return $full }
    return $full.TrimEnd('\')
}

function Assert-WabPlainPath([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $attributes = [IO.File]::GetAttributes($current)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-Wab 'LINK_NOT_ALLOWED' 'Symbolic links, junctions and other reparse points are not supported.' }
        }
        $parent = [IO.Path]::GetDirectoryName($current.TrimEnd('\'))
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

function Test-WabWithin([string]$Path, [string]$Parent) {
    $a = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $b = [IO.Path]::GetFullPath($Parent).TrimEnd('\')
    return $a.Equals($b, [StringComparison]::OrdinalIgnoreCase) -or $a.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Assert-WabGameStopped {
    try { $processes = @(Get-Process -ErrorAction Stop) } catch { Stop-Wab 'PROCESS_CHECK_FAILED' 'Could not check whether WoW is running. No game files were changed.' }
    if (@($processes | Where-Object { $_.ProcessName -match '^(?i:Wow(?:B|T|Classic|ClassicB|ClassicT)?)$' }).Count -gt 0) {
        Stop-Wab 'GAME_RUNNING' 'Close every World of Warcraft client and try again. This tool never closes the game for you.'
    }
}

function Get-WabClient([string]$GamePath) {
    $full = Get-WabFullPath $GamePath
    Assert-WabPlainPath $full
    if (-not [IO.Directory]::Exists($full)) { Stop-Wab 'INVALID_CLIENT' 'The selected client folder does not exist.' }
    $name = [IO.Path]::GetFileName($full).ToLowerInvariant()
    if (-not $script:ClientTypes.ContainsKey($name)) { Stop-Wab 'INVALID_CLIENT' 'Select a supported client subfolder such as _classic_beta_ or _retail_, not the parent installation folder.' }
    $executables = @('Wow.exe', 'WowB.exe', 'WowT.exe', 'WowClassic.exe', 'WowClassicB.exe', 'WowClassicT.exe')
    if (@($executables | Where-Object { [IO.File]::Exists((Join-Path $full $_)) }).Count -eq 0) { Stop-Wab 'INVALID_CLIENT' 'The selected folder does not contain a recognized WoW executable.' }
    return [pscustomobject]@{ Path = $full; ClientType = $script:ClientTypes[$name] }
}

function Get-WabDefaultBackupDirectory {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { Stop-Wab 'DESTINATION_REQUIRED' 'Specify a local backup destination.' }
    return Join-Path $env:LOCALAPPDATA 'WoWAddonBackup\Backups'
}

function Get-WabBackupDirectory([string]$BackupDirectory, [string]$GamePath) {
    if (-not $BackupDirectory) { $BackupDirectory = Get-WabDefaultBackupDirectory }
    $full = Get-WabFullPath $BackupDirectory
    Assert-WabPlainPath $full
    if ($GamePath -and (Test-WabWithin $full $GamePath)) { Stop-Wab 'SOURCE_DESTINATION_OVERLAP' 'Keep backups outside the WoW client folder.' }
    $toolRoot = Split-Path $PSScriptRoot -Parent
    if (Test-WabWithin $full $toolRoot) { Stop-Wab 'PROJECT_DESTINATION' 'Keep private backups outside the tool folder.' }
    if ([IO.File]::Exists($full)) { Stop-Wab 'DESTINATION_UNWRITABLE' 'The destination must be a directory.' }
    return $full
}

function Copy-WabStream($InputStream, $OutputStream, [long]$ExpectedSize) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $buffer = New-Object byte[] 65536
    [long]$total = 0
    try {
        while (($read = $InputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $total += $read
            if ($total -gt $ExpectedSize) { Stop-Wab 'SIZE_MISMATCH' 'A file changed or exceeds its declared size.' }
            [void]$sha.TransformBlock($buffer, 0, $read, $buffer, 0)
            if ($null -ne $OutputStream) { $OutputStream.Write($buffer, 0, $read) }
        }
        if ($total -ne $ExpectedSize) { Stop-Wab 'SIZE_MISMATCH' 'A file is incomplete or changed during the operation.' }
        [void]$sha.TransformFinalBlock([byte[]]@(), 0, 0)
        return ([BitConverter]::ToString($sha.Hash)).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Get-WabFileHash([string]$Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { return Copy-WabStream $stream $null $stream.Length } finally { $stream.Dispose() }
}

function Get-WabInventory([string]$GamePath, [string[]]$Folders = $script:PayloadFolders) {
    $entries = [Collections.Generic.List[object]]::new()
    $found = [Collections.Generic.List[string]]::new()
    [long]$total = 0
    foreach ($folder in $Folders) {
        $root = Join-Path $GamePath $folder
        Assert-WabPlainPath $root
        if ([IO.File]::Exists($root)) { Stop-Wab 'INVALID_PAYLOAD' 'A backup folder name is occupied by a file.' }
        if (-not [IO.Directory]::Exists($root)) { continue }
        $found.Add($folder)
        $pending = [Collections.Generic.Stack[string]]::new()
        $pending.Push($root)
        while ($pending.Count -gt 0) {
            $path = $pending.Pop()
            Assert-WabPlainPath $path
            try { $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop } catch { Stop-Wab 'SOURCE_UNREADABLE' 'A source file or directory could not be read.' }
            $relative = $path.Substring($GamePath.Length + 1).Replace('\', '/')
            $directory = $item.PSIsContainer
            $kind = 'File'; [long]$size = 0; $hash = $null
            if ($directory) {
                $kind = 'Directory'; $relative += '/'
                try { foreach ($child in [IO.Directory]::EnumerateFileSystemEntries($path)) { $pending.Push($child) } } catch { Stop-Wab 'SOURCE_UNREADABLE' 'A source directory could not be enumerated.' }
            } else {
                $size = $item.Length
                $total += $size
                if ($size -gt $script:MaxFileBytes -or $total -gt $script:MaxBytes) { Stop-Wab 'SIZE_LIMIT' 'The source exceeds the documented backup size limits.' }
                try { $hash = Get-WabFileHash $path } catch { Stop-Wab 'SOURCE_UNREADABLE' 'A source file is locked, unreadable or changing. Close programs using it and retry.' }
            }
            Assert-WabArchivePath $relative $kind
            $entries.Add([pscustomobject][ordered]@{
                Path = $relative; Kind = $kind; Size = $size; Sha256 = $hash
                LastWriteUtc = $item.LastWriteTimeUtc.ToString('o'); Attributes = ([int]$item.Attributes -band 39)
            })
            if ($entries.Count -gt $script:MaxEntries) { Stop-Wab 'SIZE_LIMIT' 'Too many entries for one backup.' }
        }
    }
    return [pscustomobject]@{ Folders = @($found.ToArray()); Entries = @($entries.ToArray() | Sort-Object Path); TotalBytes = $total }
}

function Enter-WabClientLock([string]$GamePath) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $id = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($GamePath.ToLowerInvariant())))).Replace('-', '') } finally { $sha.Dispose() }
    $mutex = [Threading.Mutex]::new($false, ('Local\WoWAddonBackup-' + $id))
    try {
        $acquired = $false
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { Stop-Wab 'CLIENT_BUSY' 'Another backup or restore is already using this client.' }
        return $mutex
    } catch { $mutex.Dispose(); throw }
}

function Assert-WabNoInterruptedRestore([string]$GamePath) {
    foreach ($directory in [IO.Directory]::EnumerateDirectories($GamePath, '.wow-addon-backup-restore-*')) {
        Stop-Wab 'RESTORE_RECOVERY_REQUIRED' 'An interrupted restore needs attention. Read the manual recovery guide before continuing.'
    }
}

function New-WabBackupInternal([string]$GamePath, [string]$BackupDirectory, [string[]]$Folders, [string]$Prefix = 'backup') {
    Assert-WabGameStopped
    $client = Get-WabClient $GamePath
    $destination = Get-WabBackupDirectory $BackupDirectory $client.Path
    $inventory = Get-WabInventory $client.Path $Folders
    if ($inventory.Folders.Count -eq 0 -and $Prefix -ne 'recovery') { Stop-Wab 'NO_PAYLOAD' 'There are no selected addon or settings folders to back up.' }
    $manifest = [ordered]@{
        Format = 'WoWAddonBackup'; SchemaVersion = 1; ToolVersion = $script:ToolVersion; Purpose = $Prefix
        ClientType = $client.ClientType; CreatedUtc = [DateTime]::UtcNow.ToString('o')
        Folders = @($inventory.Folders); Entries = @($inventory.Entries)
    }
    $name = 'wow-' + $Prefix + '-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.zip'
    $final = Join-Path $destination $name
    $partial = $final + '.partial'
    $fileStream = $null; $zip = $null
    try {
        try { [IO.Directory]::CreateDirectory($destination) | Out-Null } catch { Stop-Wab 'DESTINATION_UNWRITABLE' 'The backup destination cannot be created.' }
        Assert-WabPlainPath $destination
        try { $fileStream = [IO.File]::Open($partial, 'CreateNew', 'ReadWrite', 'None') } catch { Stop-Wab 'DESTINATION_UNWRITABLE' 'The backup destination is not writable.' }
        $zip = [IO.Compression.ZipArchive]::new($fileStream, [IO.Compression.ZipArchiveMode]::Create, $true)
        foreach ($entry in $inventory.Entries) {
            $zipped = $zip.CreateEntry($entry.Path, [IO.Compression.CompressionLevel]::Optimal)
            if ($entry.Kind -eq 'Directory') { continue }
            $source = Join-Path $client.Path $entry.Path.Replace('/', '\')
            Assert-WabPlainPath $source
            $input = $null; $output = $null
            try {
                $input = [IO.File]::Open($source, 'Open', 'Read', 'Read')
                $output = $zipped.Open()
                $hash = Copy-WabStream $input $output $entry.Size
                if ($hash -cne $entry.Sha256) { Stop-Wab 'SOURCE_CHANGED' 'Source data changed during backup. Retry with WoW closed.' }
            } finally { if ($output) { $output.Dispose() }; if ($input) { $input.Dispose() } }
        }
        $manifestEntry = $zip.CreateEntry('manifest.json')
        $output = $manifestEntry.Open()
        try {
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($manifest | ConvertTo-Json -Depth 8 -Compress))
            $output.Write($bytes, 0, $bytes.Length)
        } finally { $output.Dispose() }
        $zip.Dispose(); $zip = $null
        $fileStream.Flush($true); $fileStream.Dispose(); $fileStream = $null
        $verified = Test-WabArchive $partial
        $after = Get-WabInventory $client.Path $Folders
        if (($inventory | ConvertTo-Json -Depth 8 -Compress) -cne ($after | ConvertTo-Json -Depth 8 -Compress)) { Stop-Wab 'SOURCE_CHANGED' 'Source data changed during backup. The incomplete archive was not kept.' }
        Assert-WabGameStopped
        Assert-WabPlainPath $destination
        [IO.File]::Move($partial, $final)
        return [pscustomobject]@{ ArchivePath = $final; ClientType = $client.ClientType; TotalBytes = $inventory.TotalBytes; EntryCount = $inventory.Entries.Count; Verified = $true }
    } catch {
        if ($zip) { $zip.Dispose(); $zip = $null }
        if ($fileStream) { $fileStream.Dispose(); $fileStream = $null }
        # Delete only this invocation's unfinished file after checking its path.
        if ([IO.File]::Exists($partial)) { Assert-WabPlainPath $partial; if (Test-WabWithin $partial $destination) { [IO.File]::Delete($partial) } }
        throw
    } finally { if ($zip) { $zip.Dispose() }; if ($fileStream) { $fileStream.Dispose() } }
}

function New-WabBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GamePath, [string]$BackupDirectory)
    $client = Get-WabClient $GamePath
    Assert-WabNoInterruptedRestore $client.Path
    $lock = Enter-WabClientLock $client.Path
    try { return New-WabBackupInternal $client.Path $BackupDirectory $script:PayloadFolders } finally { $lock.ReleaseMutex(); $lock.Dispose() }
}

function Get-WabBackups {
    [CmdletBinding()]
    param([string]$BackupDirectory)
    $directory = Get-WabBackupDirectory $BackupDirectory ''
    if (-not [IO.Directory]::Exists($directory)) { return }
    foreach ($file in (Get-ChildItem -LiteralPath $directory -File -Force | Where-Object { $_.Name -match '^wow-(?:backup|recovery)-.*\.zip$' } | Sort-Object LastWriteTimeUtc -Descending)) {
        Assert-WabPlainPath $file.FullName
        [pscustomobject]@{ Name = $file.Name; ArchivePath = $file.FullName; Bytes = $file.Length; LastWriteUtc = $file.LastWriteTimeUtc; Verification = 'Not checked' }
    }
}

. (Join-Path $PSScriptRoot 'Archive.ps1')
. (Join-Path $PSScriptRoot 'Restore.ps1')
Export-ModuleMember -Function New-WabBackup, Test-WabArchive, Restore-WabBackup, Get-WabBackups, Get-WabClient, Get-WabDefaultBackupDirectory
