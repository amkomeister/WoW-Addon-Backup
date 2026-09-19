[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$files = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release-files.json') -Raw | ConvertFrom-Json
& (Join-Path $root 'tests\Check-Privacy.ps1')
$output = Join-Path $root 'dist'
[IO.Directory]::CreateDirectory($output) | Out-Null
if (([IO.File]::GetAttributes($output) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Release output cannot be a link.' }
$name = 'wow-addon-backup-v1.0.0-windows.zip'
$zipPath = Join-Path $output $name
$stream = [IO.File]::Open($zipPath, 'Create', 'ReadWrite', 'None')
$zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
try {
    foreach ($relative in ($files | Sort-Object)) {
        $source = [IO.Path]::GetFullPath((Join-Path $root $relative))
        if (-not $source.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or $relative -match '\\|(^|/)\.\.(/|$)') { throw 'Unsafe release source path.' }
        if (([IO.File]::GetAttributes($source) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Release source cannot be a link.' }
        $entry = $zip.CreateEntry(('WoW-Addon-Backup/' + $relative), [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $writer = $entry.Open()
        try { $bytes = [IO.File]::ReadAllBytes($source); $writer.Write($bytes, 0, $bytes.Length) } finally { $writer.Dispose() }
    }
} finally { $zip.Dispose(); $stream.Dispose() }
& (Join-Path $root 'tests\Check-Privacy.ps1') -ArchivePath $zipPath
$checksumPath = Join-Path $output 'SHA256SUMS.txt'
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($checksumPath, ($hash + '  ' + $name + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ ZipPath = $zipPath; ChecksumPath = $checksumPath; Sha256 = $hash; FileCount = $files.Count }
