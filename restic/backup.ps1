$ErrorActionPreference = 'Continue'   # not 'Stop': in PowerShell 5.1 that turns restic's stderr output into fatal errors
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$restic = 'C:\Tools\restic\restic.exe'
$cfg    = "$env:USERPROFILE\.restic"
$logDir = "$cfg\logs"
$log    = "$logDir\backup-$(Get-Date -Format 'yyyy-MM-dd_HHmm').log"
$hc     = Get-Content "$cfg\hc-url" -ErrorAction SilentlyContinue | Select-Object -First 1

$env:RESTIC_REPOSITORY    = 'sftp:prodesk-restic:/mnt/backups/pc-restic'
$env:RESTIC_PASSWORD_FILE = "$cfg\password"

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

$rc = Run 'backup' { & $restic backup D:\ --exclude-file "$cfg\excludes.txt" }
if ($rc -ne 0 -and $rc -ne 3) { $failed = "backup exited with code $rc" }   # 3 = snapshot saved, some files unreadable

if (-not $failed) {
    $rc = Run 'forget and prune' { & $restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune }
    if ($rc -ne 0) { $failed = "forget/prune exited with code $rc" }
}

if (-not $failed -and (Get-Date).DayOfWeek -eq 'Sunday') {
    $rc = Run 'check' { & $restic check --read-data-subset=5% }
    if ($rc -ne 0) { $failed = "check exited with code $rc" }
}

$tail = (Get-Content $log -Tail 30) -join "`n"
if ($failed) { Ping '/fail' "$failed`n$tail" } else { Ping '' $tail }

Get-ChildItem $logDir -Filter 'backup-*.log' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 30 | Remove-Item
if ($failed) { exit 1 }