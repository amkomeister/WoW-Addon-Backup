function Assert-WabArchivePath([string]$Path, [string]$Kind) {
    if (-not $Path -or $Path.Length -gt 240 -or $Path.Contains('\') -or $Path.StartsWith('/') -or $Kind -notin @('File', 'Directory')) { Stop-Wab 'UNSAFE_ARCHIVE_PATH' 'The archive contains an unsupported path.' }
    if (($Kind -eq 'Directory') -ne $Path.EndsWith('/')) { Stop-Wab 'UNSAFE_ARCHIVE_PATH' 'The archive has conflicting file and directory paths.' }
    $segments = $Path.TrimEnd('/').Split('/')
    if ($segments.Count -lt 1 -or $segments[0] -cnotin $script:PayloadFolders) { Stop-Wab 'UNSAFE_ARCHIVE_PATH' 'Only Interface, WTF and Fonts can be restored.' }
    foreach ($segment in $segments) {
        if (-not $segment -or $segment -in @('.', '..') -or $segment -match '[\x00-\x1f<>:"|?*]' -or $segment -match '[ .]$' -or $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { Stop-Wab 'UNSAFE_ARCHIVE_PATH' 'The archive contains an unsafe filename.' }
    }
    if ($Kind -eq 'File' -and $segments.Count -eq 1) { Stop-Wab 'UNSAFE_ARCHIVE_PATH' 'A payload root must be a directory.' }
}

function Open-WabArchive([string]$ArchivePath) {
    $path = Get-WabFullPath $ArchivePath
    Assert-WabPlainPath $path
    $stream = $null; $zip = $null
    try {
        $stream = [IO.File]::Open($path, 'Open', 'Read', 'Read')
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $true)
        if ($zip.Entries.Count -gt ($script:MaxEntries + 1)) { Stop-Wab 'INVALID_ARCHIVE' 'The archive contains too many entries.' }
        $zipEntries = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            $key = $entry.FullName.TrimEnd('/')
            if ($zipEntries.ContainsKey($key)) { Stop-Wab 'INVALID_ARCHIVE' 'Duplicate or conflicting archive entries are not supported.' }
            # ZIP Unix symlink mode and Windows reparse-point attributes.
            $unixMode = (($entry.ExternalAttributes -shr 16) -band 61440)
            if ($unixMode -eq 40960 -or (($entry.ExternalAttributes -band 1024) -ne 0)) { Stop-Wab 'LINK_NOT_ALLOWED' 'The archive contains a link.' }
            $zipEntries.Add($key, $entry)
        }
        if (-not $zipEntries.ContainsKey('manifest.json')) { Stop-Wab 'INVALID_ARCHIVE' 'Only archives created by WoW Addon Backup can be restored.' }
        $manifestEntry = $zipEntries['manifest.json']
        if ($manifestEntry.FullName -cne 'manifest.json' -or $manifestEntry.Length -gt 64MB) { Stop-Wab 'INVALID_ARCHIVE' 'The archive manifest is invalid or too large.' }
        $manifestStream = $manifestEntry.Open()
        $manifestBuffer = [IO.MemoryStream]::new()
        try {
            [void](Copy-WabStream $manifestStream $manifestBuffer $manifestEntry.Length)
            $manifestText = [Text.UTF8Encoding]::new($false, $true).GetString($manifestBuffer.ToArray())
        } finally { $manifestStream.Dispose(); $manifestBuffer.Dispose() }
        $manifest = $manifestText | ConvertFrom-Json -ErrorAction Stop
        if ($manifest.Format -cne 'WoWAddonBackup' -or $manifest.SchemaVersion -ne 1 -or $manifest.ClientType -cnotin @($script:ClientTypes.Values)) { Stop-Wab 'INVALID_ARCHIVE' 'The archive format, schema or client type is not supported.' }
        $folders = @($manifest.Folders)
        if ($manifest.Purpose -cnotin @('backup', 'recovery')) { Stop-Wab 'INVALID_ARCHIVE' 'Invalid backup purpose.' }
        if (($folders.Count -eq 0 -and $manifest.Purpose -ne 'recovery') -or $folders.Count -gt 3 -or @($folders | Select-Object -Unique).Count -ne $folders.Count) { Stop-Wab 'INVALID_ARCHIVE' 'Invalid payload folder list.' }
        foreach ($folder in $folders) { if ($folder -cnotin $script:PayloadFolders) { Stop-Wab 'INVALID_ARCHIVE' 'Unexpected payload folder.' } }
        $records = @($manifest.Entries)
        if ($records.Count -gt $script:MaxEntries -or $zipEntries.Count -ne ($records.Count + 1)) { Stop-Wab 'INVALID_ARCHIVE' 'The archive contents do not match the manifest.' }
        $seen = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        [long]$totalBytes = 0
        foreach ($record in $records) {
            Assert-WabArchivePath $record.Path $record.Kind
            $key = $record.Path.TrimEnd('/')
            if ($seen.ContainsKey($key) -or -not $zipEntries.ContainsKey($key) -or $zipEntries[$key].FullName -cne $record.Path) { Stop-Wab 'INVALID_ARCHIVE' 'Duplicate, missing or inconsistent manifest entry.' }
            if ($record.Path.Split('/')[0] -cnotin $folders) { Stop-Wab 'INVALID_ARCHIVE' 'An entry is outside the declared payload folders.' }
            if (($record.Size -isnot [int] -and $record.Size -isnot [long]) -or $record.Size -lt 0 -or $record.Size -gt $script:MaxFileBytes -or [long]$record.Size -ne $record.Size) { Stop-Wab 'INVALID_ARCHIVE' 'Invalid file size.' }
            $totalBytes += [long]$record.Size
            if ($totalBytes -gt $script:MaxBytes) { Stop-Wab 'INVALID_ARCHIVE' 'The expanded archive exceeds the size limit.' }
            if (($record.Attributes -isnot [int] -and $record.Attributes -isnot [long]) -or ([int]$record.Attributes -band (-bnot 39)) -ne 0) { Stop-Wab 'INVALID_ARCHIVE' 'Unsupported file attributes.' }
            $date = [DateTime]::MinValue
            if (-not [DateTime]::TryParse($record.LastWriteUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$date) -or $date.Year -lt 1601) { Stop-Wab 'INVALID_ARCHIVE' 'Invalid file timestamp.' }
            $entry = $zipEntries[$key]
            if ($entry.Length -ne $record.Size) { Stop-Wab 'INVALID_ARCHIVE' 'File size does not match the manifest.' }
            if ($record.Kind -eq 'Directory') {
                if ($record.Size -ne 0 -or $record.Sha256) { Stop-Wab 'INVALID_ARCHIVE' 'A directory has unexpected data.' }
            } else {
                if ($record.Sha256 -notmatch '^[a-f0-9]{64}$') { Stop-Wab 'INVALID_ARCHIVE' 'Missing file checksum.' }
                $input = $entry.Open()
                try { $hash = Copy-WabStream $input $null ([long]$record.Size) } finally { $input.Dispose() }
                if ($hash -cne $record.Sha256) { Stop-Wab 'CHECKSUM_MISMATCH' 'An archived file failed its SHA-256 check.' }
            }
            $seen.Add($key, $record)
        }
        foreach ($folder in $folders) {
            if (-not $seen.ContainsKey($folder) -or $seen[$folder].Kind -cne 'Directory') { Stop-Wab 'INVALID_ARCHIVE' 'A declared payload root is missing.' }
        }
        foreach ($key in $seen.Keys) {
            $position = $key.LastIndexOf('/')
            if ($position -ge 0) {
                $parent = $key.Substring(0, $position)
                if (-not $seen.ContainsKey($parent) -or $seen[$parent].Kind -cne 'Directory') { Stop-Wab 'INVALID_ARCHIVE' 'A parent directory is missing or is a file.' }
            }
        }
        return [pscustomobject]@{ Stream = $stream; Zip = $zip; ArchivePath = $path; ClientType = $manifest.ClientType; Manifest = $manifest; TotalBytes = $totalBytes; Entries = $zipEntries }
    } catch {
        if ($zip) { $zip.Dispose() }; if ($stream) { $stream.Dispose() }
        if ($_.Exception.Message -match '^(INVALID_ARCHIVE|UNSAFE_ARCHIVE_PATH|LINK_NOT_ALLOWED|CHECKSUM_MISMATCH|SIZE_MISMATCH):') { throw }
        Stop-Wab 'INVALID_ARCHIVE' 'The archive is unreadable, incomplete or has an invalid manifest.'
    }
}

function Test-WabArchive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ArchivePath)
    $archive = Open-WabArchive $ArchivePath
    try {
        return [pscustomobject]@{ ArchivePath = $archive.ArchivePath; ClientType = $archive.ClientType; Manifest = $archive.Manifest; TotalBytes = $archive.TotalBytes; Verified = $true }
    } finally { $archive.Zip.Dispose(); $archive.Stream.Dispose() }
}
