# install-ntp-boot-task.ps1
#
# Cria/atualiza Scheduled Task `DeviceBootstrap.NtpOnBoot` que dispara
# `w32tm /resync /force` ~1min apos cada cold boot. Util pra CMOS bat fraca
# que reseta clock no boot -- garante que NTP recupere logo, sem esperar o
# polling preguicoso default do Windows.
#
# Idempotente: re-register OK.
#
# Uso (PowerShell admin):
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/install-ntp-boot-task.ps1 | iex
#
# Validar dps:
#   Get-ScheduledTask DeviceBootstrap.NtpOnBoot
#   Get-Content C:\Users\Public\device-bootstrap-ntp-boot.log -Tail 20

$ErrorActionPreference = 'Stop'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

Write-Host "==> install-ntp-boot-task" -ForegroundColor Cyan
Write-Host ""

$taskName = "DeviceBootstrap.NtpOnBoot"
$scriptDir = "C:\ProgramData\device-bootstrap"
$bootScript = "$scriptDir\boot-ntp.ps1"
$bootLog = "C:\Users\Public\device-bootstrap-ntp-boot.log"

# 1. Garantir diretorio
if (-not (Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
}

# 2. Escrever boot script (idempotente, sobrescreve)
Write-Host "[1/3] Escrevendo boot script em $bootScript..." -ForegroundColor Cyan
$bootScriptContent = @'
# boot-ntp.ps1 -- disparado por Scheduled Task DeviceBootstrap.NtpOnBoot.
# Faz: w32tm /resync /force, logando timestamp + output em $bootLog.
$ErrorActionPreference = 'Continue'
$log = "C:\Users\Public\device-bootstrap-ntp-boot.log"
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$ts] boot resync triggered" | Out-File -Append -FilePath $log -Encoding ASCII
try {
    $out = & "$env:windir\System32\w32tm.exe" /resync /force 2>&1 | Out-String
    "$out".TrimEnd() | Out-File -Append -FilePath $log -Encoding ASCII
} catch {
    "[$ts] ERROR: $($_.Exception.Message)" | Out-File -Append -FilePath $log -Encoding ASCII
}
'@
[System.IO.File]::WriteAllText($bootScript, $bootScriptContent, [System.Text.Encoding]::ASCII)
Write-Host "    OK" -ForegroundColor DarkGray

# 3. Register Scheduled Task
Write-Host "[2/3] Registrando Scheduled Task '$taskName'..." -ForegroundColor Cyan
$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$bootScript`""

# AtStartup com delay de 60s pra dar tempo de network estar pronto
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = "PT1M"

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Force NTP resync 1min apos cold boot (CMOS bat workaround)" `
    -Force | Out-Null

Write-Host "    OK" -ForegroundColor DarkGray

# 4. Confirmar
Write-Host "[3/3] Validacao..." -ForegroundColor Cyan
Get-ScheduledTask -TaskName $taskName |
    Select-Object TaskName, State, @{N="LastRun";E={(Get-ScheduledTaskInfo -TaskName $_.TaskName).LastRunTime}} |
    Format-List | Out-String | Write-Host

Write-Host ""
Write-Host "install-ntp-boot-task OK." -ForegroundColor Green
Write-Host ""
Write-Host "Como validar no proximo cold boot:" -ForegroundColor DarkGray
Write-Host "  Get-Content $bootLog -Tail 10" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Pra disparar manualmente agora (sem reboot):" -ForegroundColor DarkGray
Write-Host "  Start-ScheduledTask -TaskName $taskName" -ForegroundColor DarkGray
