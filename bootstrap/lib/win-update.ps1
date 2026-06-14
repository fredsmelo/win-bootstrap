# Windows Update via Scheduled Task SYSTEM.
#
# Workaround necessario: sessao SSH e admin mas SEM token elevado (UAC),
# e Get-WindowsUpdate -Install precisa elevation real. Roda como SYSTEM
# via scheduled task one-shot.
#
# Uso (PowerShell admin via SSH):
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/win-update.ps1 | iex
#
# Idempotencia:
#   - Pre-check pending reboot -> agenda reboot e sai (re-rodar depois)
#   - Pre-check updates pending -> se nada, sai limpo
#   - Task name fixo (DeviceBootstrap.WinUpdate) -> sobrescreve runs anteriores

$ErrorActionPreference = 'Stop'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

Write-Host "==> win-update" -ForegroundColor Cyan
Write-Host ""

# 1. Pre-check: pending reboot bloqueia WU
Write-Host "1/4 Checando pending reboot..." -ForegroundColor Cyan
$cbs  = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$wu   = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
$pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
if ($cbs -or $wu -or $pfro) {
    Write-Host "    pending reboot detectado (cbs=$cbs wu=$wu pfro=$($pfro -ne $null))." -ForegroundColor Yellow
    Write-Host "    agendando reboot em 30s e saindo. RE-RODAR depois do reboot." -ForegroundColor Yellow
    shutdown /r /t 30 /c "win-update.ps1: limpando pending reboot" | Out-Null
    exit 0
}
Write-Host "    sem pending reboot." -ForegroundColor DarkGray

# 2. Garantir modulo
Write-Host "2/4 Carregando PSWindowsUpdate..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
    Write-Host "    PSWindowsUpdate ausente. Rode setup-tools.ps1 primeiro." -ForegroundColor Red
    exit 1
}
Import-Module PSWindowsUpdate
Write-Host "    OK" -ForegroundColor DarkGray

# 3. Pre-check: existem updates pendentes?
Write-Host "3/4 Checando updates pendentes..." -ForegroundColor Cyan
try {
    $pending = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop
} catch {
    # UAC pode bloquear direto; nesse caso vamos pro scheduled task de qualquer forma
    Write-Host "    Get-WindowsUpdate direto falhou ($($_.Exception.Message)). Tentando via task." -ForegroundColor Yellow
    $pending = $null
}
if ($pending -and $pending.Count -eq 0) {
    Write-Host "    nada pendente. Saindo limpo." -ForegroundColor Green
    exit 0
}
if ($pending) {
    Write-Host "    $($pending.Count) update(s) pendente(s)." -ForegroundColor DarkGray
    $pending | Select-Object @{N='Size';E={'{0:N1} MB' -f ($_.Size/1MB)}}, Title |
        Format-Table -AutoSize | Out-String | Write-Host
}

# 4. Executar via Scheduled Task SYSTEM
Write-Host "4/4 Disparando install via Scheduled Task SYSTEM..." -ForegroundColor Cyan
$taskName = 'DeviceBootstrap.WinUpdate'
$taskScript = 'C:\Users\Public\device-bootstrap-winupdate-task.ps1'
$taskLog    = 'C:\Users\Public\device-bootstrap-winupdate.log'

$inner = @"
Import-Module PSWindowsUpdate
Start-Transcript -Path '$taskLog' -Append
Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -AutoReboot -Verbose 2>&1 | Out-Default
Stop-Transcript
"@
[System.IO.File]::WriteAllText($taskScript, $inner, [System.Text.Encoding]::ASCII)

$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$taskScript`""
$trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

Write-Host ""
Write-Host "Task '$taskName' rodando. Monitorar:" -ForegroundColor Green
Write-Host "  Get-ScheduledTask $taskName | Select State" -ForegroundColor DarkGray
Write-Host "  Get-Content $taskLog -Tail 20" -ForegroundColor DarkGray
Write-Host ""
Write-Host "AutoReboot ligado: maquina pode reiniciar sozinha se WU pedir." -ForegroundColor Yellow
