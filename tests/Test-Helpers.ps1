$script:assertions = 0
function Assert-Test($Condition, [string]$Message) {
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:assertions++
}
function Assert-Throws([scriptblock]$Action, [string]$Code) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-Test ($null -ne $caught) ('operation must reject ' + $Code)
    Assert-Test ($caught.Exception.Message -match [regex]::Escape($Code)) ('expected error code ' + $Code + '; got ' + $caught.Exception.Message)
}
function New-TestRoot {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('wab-fixture-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}
function New-TestGame([string]$Root, [string]$Client = '_classic_beta_') {
    $game = Join-Path $Root $Client
    foreach ($folder in @('Interface\AddOns\Sample', 'WTF\empty', 'WTF\Account\SAMPLE\Character', 'Fonts', 'Logs', 'Data')) {
        [IO.Directory]::CreateDirectory((Join-Path $game $folder)) | Out-Null
    }
    [IO.File]::WriteAllBytes((Join-Path $game 'WowB.exe'), [byte[]]@(0))
    [IO.File]::WriteAllText((Join-Path $game 'WTF\Config.wtf'), 'SET synthetic "yes"')
    [IO.File]::WriteAllText((Join-Path $game 'Interface\AddOns\Sample\Sample.lua'), 'Sample = { synthetic = true }')
    $unicodeName = 'note-' + [char]0x00E9 + [char]0x732B + '.lua'
    [IO.File]::WriteAllText((Join-Path $game ('WTF\' + $unicodeName)), 'unicode fixture')
    $hidden = Join-Path $game 'Interface\AddOns\Sample\hidden.lua'
    [IO.File]::WriteAllText($hidden, 'hidden fixture')
    [IO.File]::SetAttributes($hidden, [IO.FileAttributes]::Hidden)
    [IO.File]::WriteAllText((Join-Path $game 'Fonts\sample.ttf'), 'synthetic font placeholder')
    [IO.File]::WriteAllText((Join-Path $game 'Logs\skip.txt'), 'not included')
    [IO.File]::WriteAllText((Join-Path $game 'Data\skip.txt'), 'not included')
    return $game
}
function Get-TestTree([string]$Root) {
    $rows = foreach ($item in (Get-ChildItem -LiteralPath $Root -Force -Recurse | Sort-Object FullName)) {
        $relative = $item.FullName.Substring($Root.Length)
        if ($item.PSIsContainer) { $relative + '/' } else { $relative + ':' + (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash }
    }
    return ($rows -join "`n")
}
function Remove-TestRoot([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $full.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notlike 'wab-fixture-*') { throw 'Unsafe test cleanup path.' }
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force -Recurse }
}
function Write-TestSummary([string]$Suite) { Write-Output ('PASS: ' + $Suite + ' - ' + $script:assertions + ' assertions') }
