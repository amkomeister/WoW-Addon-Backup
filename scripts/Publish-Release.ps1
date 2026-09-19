[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REF -cne 'refs/tags/v1.0.0') { throw 'Publish only from the checked v1.0.0 tag workflow.' }
if ($env:GITHUB_REPOSITORY -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or -not $env:GITHUB_TOKEN) { throw 'Missing release workflow context.' }
$head = git rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $head -cne $env:GITHUB_SHA) { throw 'Release checkout does not match the tested commit.' }
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$zipPath = Join-Path $root 'dist\wow-addon-backup-v1.0.0-windows.zip'
$checksumPath = Join-Path $root 'dist\SHA256SUMS.txt'
& (Join-Path $root 'tests\Check-Privacy.ps1') -ArchivePath $zipPath
$expected = ([IO.File]::ReadAllText($checksumPath) -split '\s+')[0]
if ($expected -cne (Get-FileHash -LiteralPath $zipPath).Hash.ToLowerInvariant()) { throw 'Release checksum mismatch.' }
$headers = @{ Authorization = 'Bearer ' + $env:GITHUB_TOKEN; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
$repo = $env:GITHUB_REPOSITORY
$body = @'
Download **wow-addon-backup-v1.0.0-windows.zip**, extract it, close WoW and double-click **Start-WoWBackup.cmd**.

The included README contains the numbered backup, verify, restore and manual recovery guide. The ZIP contains generic source code and English documentation only. Real backups stay private on your computer.

Both Windows PowerShell 5.1 and PowerShell 7 CI jobs passed for this release commit. Checks cover synthetic backup/restore, hidden files, Unicode names, corruption, unsafe archive paths, permission failures, interrupted restoration and release privacy. SHA256SUMS.txt contains the download checksum.

Independent local file utility; no gameplay automation, telemetry or game memory access.
'@
$request = @{ tag_name = 'v1.0.0'; target_commitish = $head; name = 'WoW Addon Backup v1.0.0'; body = $body; draft = $true; prerelease = $false } | ConvertTo-Json
$release = Invoke-RestMethod -Method Post -Uri ('https://api.github.com/repos/' + $repo + '/releases') -Headers $headers -ContentType 'application/json' -Body $request
foreach ($path in @($zipPath, $checksumPath)) {
    $fileName = [Uri]::EscapeDataString([IO.Path]::GetFileName($path))
    $uri = 'https://uploads.github.com/repos/' + $repo + '/releases/' + $release.id + '/assets?name=' + $fileName
    $asset = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/octet-stream' -InFile $path
    if ($asset.state -cne 'uploaded') { throw 'Release asset did not finish uploading. Draft retained.' }
}
$published = Invoke-RestMethod -Method Patch -Uri ('https://api.github.com/repos/' + $repo + '/releases/' + $release.id) -Headers $headers -ContentType 'application/json' -Body '{"draft":false}'
Write-Output ('Published: ' + $published.html_url)
