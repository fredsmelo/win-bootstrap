# uninstall-state-sync.ps1
#
# Reversao limpa do state-sync no device. Nao toca no GitHub (revogue
# a deploy key manualmente quando quiser: gh api repos/.../keys/<id> -X DELETE).
#
# Uso:
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/uninstall-state-sync.ps1 | iex

$ErrorActionPreference = 'Continue'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

$taskName   = 'DeviceBootstrap.StateSync'
$baseDir    = 'C:\ProgramData\device-bootstrap'
$repoDir    = "$baseDir\repo"
$sshDir     = "$baseDir\ssh"
$syncScript = "$baseDir\state-sync.ps1"

Write-Host "==> uninstall-state-sync" -ForegroundColor Cyan
Write-Host ""

# 1. Scheduled Task
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "[task] removida." -ForegroundColor DarkGray
} else {
    Write-Host "[task] nao existe." -ForegroundColor DarkGray
}

# 2. Repo local
if (Test-Path $repoDir) {
    Remove-Item -Path $repoDir -Recurse -Force
    Write-Host "[repo] $repoDir removido." -ForegroundColor DarkGray
}

# 3. state-sync.ps1
if (Test-Path $syncScript) {
    Remove-Item -Path $syncScript -Force
    Write-Host "[script] $syncScript removido." -ForegroundColor DarkGray
}

# 4. SSH keys (so as do state-sync, mantem id_<host>_state.*; outras chaves do bootstrap intocadas)
Get-ChildItem -Path $sshDir -Filter 'id_*_state*' -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -Path $_.FullName -Force
    Write-Host "[ssh] $($_.Name) removido." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "uninstall-state-sync OK." -ForegroundColor Green
Write-Host ""
Write-Host "Nao esqueca de revogar a deploy key no GitHub:" -ForegroundColor Yellow
Write-Host "  gh api repos/<owner>/<repo>/keys --jq '.[] | {id,title}'" -ForegroundColor DarkGray
Write-Host "  gh api repos/<owner>/<repo>/keys/<id> -X DELETE" -ForegroundColor DarkGray
