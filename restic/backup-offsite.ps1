$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$restic = 'C:\Tools\restic\restic.exe'
$rclone = 'C:\Users\Hall\AppData\Local\Microsoft\WinGet\Packages\Rclone.Rclone_Microsoft.Winget.Source_8wekyb3d8bbwe\rclone-v1.76.0-windows-amd64\rclone.exe'
$cfg    = "$env:USERPROFILE\.restic"
$logDir = "$cfg\logs-offsite"
$log    = "$logDir\offsite-$(Get-Date -Format 'yyyy-MM-dd_HHmm').log"
$hc     = Get-Content "$cfg\hc-url-offsite" -ErrorAction SilentlyContinue | Select-Object -First 1
$paths  = 'D:\Files\Documents\CVs', 'D:\Scripts', 'D:\Backups', "$env:USERPROFILE\.ssh"

$env:RESTIC_REPOSITORY      = 'rclone:gdrive-offsite:restic-offsite'
$env:RESTIC_PASSWORD_FILE   = "$cfg\password-offsite"
$env:RCLONE_DRIVE_USE_TRASH = 'false'   # pruned data must not sit in Drive's trash and count against the 15GB
$env:Path = (Split-Path $rclone) + ';' + $env:Path

New-Item -ItemType Directory -Force $logDir | Out-Null

function Ping($suffix, $body) {
    if (-not $hc) { return }
    try { Invoke-RestMethod -Uri "$hc$suffix" -Method Post -Body $body -TimeoutSec 10 | Out-Null } catch { "[$(Get-Date -Format s)] ping failed: $($_.Exception.Message)" | Out-File -Append -Encoding utf8 $log }
}
function Run($label, [scriptblock]$cmd) {
    "[$(Get-Date -Format s)] $label" | Out-File -Append -Encoding utf8 $log
    & $cmd 2>&1 | Out-File -Append -Encoding utf8 $log
    return $LASTEXITCODE
}

Ping '/start' 'started'
$failed = $null

Run 'unlock stale locks' { & $restic unlock } | Out-Null

$rc = Run 'backup' { & $restic backup $paths --exclude-file "$cfg\excludes-offsite.txt" }
if ($rc -ne 0 -and $rc -ne 3) { $failed = "backup exited with code $rc" }

if (-not $failed) {
    $rc = Run 'forget and prune' { & $restic forget --keep-weekly 4 --keep-monthly 6 --prune }
    if ($rc -ne 0) { $failed = "forget/prune exited with code $rc" }
}

if (-not $failed -and (Get-Date).Day -le 7) {   # first run of each month
    $rc = Run 'check' { & $restic check --read-data-subset=10% }
    if ($rc -ne 0) { $failed = "check exited with code $rc" }
}

$tail = (Get-Content $log -Tail 30) -join "`n"
if ($failed) { Ping '/fail' "$failed`n$tail" } else { Ping '' $tail }

Get-ChildItem $logDir -Filter 'offsite-*.log' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 12 | Remove-Item
if ($failed) { exit 1 }

