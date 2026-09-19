$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Test-Helpers.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildOutput = @(& (Join-Path $root 'scripts\Build-Release.ps1'))
$build = $buildOutput[-1]
$testRoot = New-TestRoot
try {
    $checksum = ([IO.File]::ReadAllText($build.ChecksumPath) -split '\s+')[0]
    Assert-Test ($checksum -ceq (Get-FileHash -LiteralPath $build.ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()) 'published checksum matches generated ZIP'
    $stream = [IO.File]::OpenRead($build.ZipPath)
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
    try {
        foreach ($entry in $zip.Entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $testRoot $entry.FullName.Replace('/', '\')))
            if (-not $target.StartsWith($testRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture extraction path.' }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
            $source = $entry.Open(); $file = [IO.File]::Open($target, 'CreateNew', 'Write', 'None')
            try { $source.CopyTo($file) } finally { $file.Dispose(); $source.Dispose() }
            $relative = $entry.FullName.Substring('WoW-Addon-Backup/'.Length)
            Assert-Test ((Get-FileHash -LiteralPath $target).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $root $relative)).Hash) 'package source bytes match the working tree'
        }
    } finally { $zip.Dispose(); $stream.Dispose() }
    $entry = Join-Path $testRoot 'WoW-Addon-Backup\WoWAddonBackup.ps1'
    $engine = (Get-Process -Id $PID).Path
    $text = & $engine -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry -Action Help
    Assert-Test ($LASTEXITCODE -eq 0 -and ($text -join '') -match 'Step-by-step') 'extracted release runs without repository dependencies'
    Assert-Test ([IO.File]::Exists((Join-Path $testRoot 'WoW-Addon-Backup\Start-WoWBackup.cmd'))) 'release contains the double-click launcher'
    Write-TestSummary 'Package'
} finally { Remove-TestRoot $testRoot }
