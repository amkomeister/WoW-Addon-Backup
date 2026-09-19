$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = Import-Module (Join-Path $PSScriptRoot '..\src\WoWBackup.Core.psm1') -Force -PassThru
& $module { function script:Get-Process { @() } }
. (Join-Path $PSScriptRoot 'Test-Helpers.ps1')

function Edit-TestArchive([string]$Source, [string]$Target, [string]$NewPath, [switch]$Corrupt, [switch]$Link, [scriptblock]$ChangeManifest) {
    [IO.File]::Copy($Source, $Target)
    $stream = [IO.File]::Open($Target, 'Open', 'ReadWrite', 'None')
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Update, $true)
    try {
        $manifestEntry = $zip.GetEntry('manifest.json')
        $reader = [IO.StreamReader]::new($manifestEntry.Open())
        try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        if ($ChangeManifest) { & $ChangeManifest $manifest }
        if ($Link) { $zip.GetEntry('WTF/Config.wtf').ExternalAttributes = -1610612736; return }
        $record = @($manifest.Entries | Where-Object { $_.Path -eq 'WTF/Config.wtf' })[0]
        $old = $zip.GetEntry($record.Path)
        $reader = [IO.StreamReader]::new($old.Open())
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $old.Delete()
        if ($NewPath) { $record.Path = $NewPath }
        if ($Corrupt) { $text = 'X' * $text.Length }
        $replacement = $zip.CreateEntry($record.Path)
        $writer = [IO.StreamWriter]::new($replacement.Open(), [Text.UTF8Encoding]::new($false))
        try { $writer.Write($text) } finally { $writer.Dispose() }
        $manifestEntry.Delete()
        $writer = [IO.StreamWriter]::new($zip.CreateEntry('manifest.json').Open(), [Text.UTF8Encoding]::new($false))
        try { $writer.Write(($manifest | ConvertTo-Json -Depth 8)) } finally { $writer.Dispose() }
    } finally { $zip.Dispose(); $stream.Dispose() }
}

$testRoot = New-TestRoot
try {
    $game = New-TestGame $testRoot
    $destination = Join-Path $testRoot 'backups'
    $backup = New-WabBackup $game $destination
    $paths = @('../escape.txt', '/absolute.txt', 'C:/escape.txt', 'WTF/../escape.txt', 'WTF/CON.txt', 'WTF/NUL', 'WTF/file:stream', 'WTF/dot.', 'WTF/space ', 'WTF//empty.txt', 'WTF\backslash.txt')
    $index = 0
    foreach ($path in $paths) {
        $bad = Join-Path $testRoot ('bad-' + $index + '.zip')
        Edit-TestArchive $backup.ArchivePath $bad -NewPath $path
        Assert-Throws { Test-WabArchive $bad } 'UNSAFE_ARCHIVE_PATH'
        $index++
    }
    $bad = Join-Path $testRoot 'checksum.zip'
    Edit-TestArchive $backup.ArchivePath $bad -Corrupt
    $before = Get-TestTree $game
    Assert-Throws { Restore-WabBackup -GamePath $game -ArchivePath $bad -BackupDirectory $destination -Confirm:$false } 'CHECKSUM_MISMATCH'
    Assert-Test ((Get-TestTree $game) -ceq $before) 'corrupt archive cannot change game folders'
    $bad = Join-Path $testRoot 'zip-link.zip'
    Edit-TestArchive $backup.ArchivePath $bad -Link
    Assert-Throws { Test-WabArchive $bad } 'LINK_NOT_ALLOWED'
    $blocked = Join-Path $testRoot 'destination-is-file'
    [IO.File]::WriteAllText($blocked, 'preserve me')
    Assert-Throws { New-WabBackup $game $blocked } 'DESTINATION_UNWRITABLE'
    Assert-Test ([IO.File]::ReadAllText($blocked) -ceq 'preserve me') 'invalid destination is never overwritten'
    $outside = Join-Path $testRoot 'outside'
    [IO.Directory]::CreateDirectory($outside) | Out-Null
    [IO.File]::WriteAllText((Join-Path $outside 'private.txt'), 'synthetic outside data')
    $junction = Join-Path $game 'Interface\AddOns\link'
    New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
    try {
        Assert-Throws { New-WabBackup $game $destination } 'LINK_NOT_ALLOWED'
        Assert-Throws { Restore-WabBackup -GamePath $game -ArchivePath $backup.ArchivePath -BackupDirectory $destination -Confirm:$false } 'LINK_NOT_ALLOWED'
    } finally { [IO.Directory]::Delete($junction) }
    Assert-Test ([IO.File]::ReadAllText((Join-Path $outside 'private.txt')) -ceq 'synthetic outside data') 'outside data is untouched when rejecting a junction'
    $driveRoot = [IO.Path]::GetPathRoot($testRoot)
    $normalized = & $module { param($Path) Get-WabFullPath $Path } $driveRoot
    Assert-Test ($normalized -ceq $driveRoot) 'normalization keeps an absolute drive root absolute'
    foreach ($change in @({ param($m) $m.Entries[0].Size = $false }, { param($m) $m.Entries[0].Attributes = 1.5 })) {
        $bad = Join-Path $testRoot ('bad-number-' + [guid]::NewGuid().ToString('N') + '.zip')
        Edit-TestArchive $backup.ArchivePath $bad -ChangeManifest $change
        Assert-Throws { Test-WabArchive $bad } 'INVALID_ARCHIVE'
    }
    $bad = Join-Path $testRoot 'manifest-size.zip'
    [IO.File]::Copy($backup.ArchivePath, $bad)
    $bytes = [IO.File]::ReadAllBytes($bad)
    $patched = $false
    for ($i = 0; $i -lt $bytes.Length - 46; $i++) {
        if ([BitConverter]::ToUInt32($bytes, $i) -eq 0x02014b50) {
            $length = [BitConverter]::ToUInt16($bytes, $i + 28)
            if ([Text.Encoding]::UTF8.GetString($bytes, $i + 46, $length) -ceq 'manifest.json') {
                [BitConverter]::GetBytes([int]1).CopyTo($bytes, $i + 24)
                $patched = $true
                break
            }
        }
    }
    Assert-Test $patched 'fixture has a manifest central directory entry'
    [IO.File]::WriteAllBytes($bad, $bytes)
    $caught = $null
    try { Test-WabArchive $bad | Out-Null } catch { $caught = $_ }
    Assert-Test ($null -ne $caught -and $caught.Exception.Message -match '^(SIZE_MISMATCH|INVALID_ARCHIVE):') 'dishonest manifest size is rejected'
    Write-TestSummary 'Safety'
} finally { Remove-TestRoot $testRoot; Remove-Module $module -Force }
