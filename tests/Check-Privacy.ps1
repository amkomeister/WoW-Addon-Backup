[CmdletBinding()]
param([switch]$Staged, [string]$ArchivePath, [string[]]$PrivateTerms = @())
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$allowedSource = Get-Content -LiteralPath (Join-Path $root 'scripts\source-files.json') -Raw | ConvertFrom-Json
$allowedRelease = Get-Content -LiteralPath (Join-Path $root 'scripts\release-files.json') -Raw | ConvertFrom-Json
$patterns = @{
    'personal Windows path' = '(?i)[a-z]:[\\/]Users[\\/][^\\/\s]+'
    'personal Unix path' = '(?i)/(?:home|Users)/[^/\s]+'
    'private key' = '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
    'GitHub credential' = '\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b'
    'cloud credential' = '\bAKIA[A-Z0-9]{16}\b'
    'machine SID' = '\bS-1-5-21-(?:\d+-){2}\d+\b'
    'network adapter identifier' = '(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b'
    'email address' = '(?i)\b[A-Z0-9._%+-]+@(?!users\.noreply\.github\.com\b)[A-Z0-9.-]+\.[A-Z]{2,}\b'
}
$terms = @($PrivateTerms) + @($env:USERNAME, $env:COMPUTERNAME)
function Test-PublicText([string]$Name, [string]$Text) {
    foreach ($label in $patterns.Keys) {
        if ($Text -match $patterns[$label]) { throw ('Privacy check failed: ' + $Name + ' contains a possible ' + $label + '. Matched data is not printed.') }
    }
    # The user-approved public repository URL is allowed as a project identity.
    $termText = $Text.Replace('https://github.com/amkomeister/WoW-Addon-Backup', 'PUBLIC_REPOSITORY')
    foreach ($term in $terms) {
        if ($term -and $term.Length -ge 4 -and $termText -match ('(?<![\w-])' + [regex]::Escape($term) + '(?![\w-])')) {
            throw ('Privacy check failed: ' + $Name + ' contains a private identifier. Matched data is not printed.')
        }
    }
}
if ($ArchivePath) {
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::OpenRead([IO.Path]::GetFullPath($ArchivePath))
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
    try {
        $expected = @($allowedRelease | ForEach-Object { 'WoW-Addon-Backup/' + $_ } | Sort-Object)
        $actual = @($zip.Entries | ForEach-Object { $_.FullName } | Sort-Object)
        if (($actual -join '|') -cne ($expected -join '|')) { throw 'Release file allowlist mismatch.' }
        foreach ($entry in $zip.Entries) {
            if ($entry.Length -gt 2MB) { throw 'Unexpectedly large release source file.' }
            $reader = [IO.StreamReader]::new($entry.Open(), [Text.UTF8Encoding]::new($false, $true))
            try { Test-PublicText $entry.FullName $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        Write-Output ('PASS: release privacy and allowlist - ' + $actual.Count + ' files')
    } finally { $zip.Dispose(); $stream.Dispose() }
} else {
    Push-Location $root
    try {
        if ($Staged) { $names = @(git ls-files --cached) }
        else { $names = @(git ls-files --cached --others --exclude-standard | Sort-Object -Unique) }
        if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate repository files.' }
        foreach ($name in $names) {
            if ($name -cnotin $allowedSource) { throw ('Unexpected public source file: ' + $name) }
            if ($Staged) {
                $content = git show (':' + $name)
                if ($LASTEXITCODE -ne 0) { throw 'Could not read staged source.' }
                Test-PublicText $name ($content -join [Environment]::NewLine)
            } else { Test-PublicText $name ([IO.File]::ReadAllText((Join-Path $root $name))) }
        }
        Write-Output ('PASS: repository privacy and allowlist - ' + $names.Count + ' files')
    } finally { Pop-Location }
}
