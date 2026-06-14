# orchestrate-local.ps1 -- orquestrador rodando localmente no proprio device
#
# Executa todos os lib scripts em sequencia dentro do proprio Windows,
# sem precisar de admin host SSH-ando. Equivalente local do orchestrate.sh.
#
# Uso (PowerShell admin):
#   irm <domain>/bootstrap/orchestrate-local.ps1 | iex
#
# Ou via alias (instalado pelo device.ps1 no PowerShell profile):
#   setup-device
#
# Com Tailscale:
#   $env:TAILSCALE_AUTH_KEY = "tskey-auth-..."
#   setup-device
#
# Com lista de apps customizada (sobreescreve `$Apps padrao vazio):
#   $env:APPS = '@("Microsoft.PowerToys", "AgileBits.1Password", "GitHub.cli")'
#   setup-device
#
# NAO inclui win-update -- aquele step pode reboot e mata a sessao
# atual de PowerShell. Rodar separadamente:
#   irm <domain>/bootstrap/lib/win-update.ps1 | iex

$ErrorActionPreference = 'Stop'

# Sanity: admin?
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

# Transcript pra disco -- append ao log global. Inspecionar:
#   Get-Content C:\Users\Public\device-bootstrap-orchestrate.log -Tail 100
$logFile = "C:\Users\Public\device-bootstrap-orchestrate.log"
try { Start-Transcript -Path $logFile -Append -Force | Out-Null } catch {}

# Config -- editar pra adaptar ao device, OU sobrescrever via $env:APPS antes do iex.
# Default = vazio (skip install-apps step).
$Apps = @()
if ($env:APPS) {
    try { $Apps = & ([scriptblock]::Create($env:APPS)) } catch { Write-Host "WARN: \$env:APPS inv lido, ignorado." -ForegroundColor Yellow }
}
$DisableTouchscreen = $false
if ($env:DISABLE_TOUCHSCREEN -eq 'true') { $DisableTouchscreen = $true }
$UrlBase = "https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib"

function Step($title) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "==> $title" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
}

function RunRemote($script) {
    Step "$env:COMPUTERNAME :: $script"
    irm "$UrlBase/$script" | iex
}

function RunRemoteWithArgs($script, $argsHash) {
    Step "$env:COMPUTERNAME :: $script"
    $sb = [scriptblock]::Create((irm "$UrlBase/$script").Trim())
    & $sb @argsHash
}

Write-Host ""
Write-Host "==> ORCHESTRATING $env:COMPUTERNAME (local)" -ForegroundColor Green
Write-Host "    started:  $(Get-Date)"

# 1. Inventory
RunRemote "inventory.ps1"

# 2. Setup tools
RunRemote "setup-tools.ps1"

# 3. NTP / W32Time hardening (1x setup) + Scheduled Task pra ressync no boot
# Rodar ANTES de installs: se CMOS bat morta, clock errado quebra TLS cert validation.
RunRemote "fix-ntp.ps1"
RunRemote "install-ntp-boot-task.ps1"

# 4. Install apps (skip se $Apps vazio)
if ($Apps.Count -gt 0) {
    RunRemoteWithArgs "install-apps.ps1" @{ Apps = $Apps }
}

# 5. Tailscale (opt-in via env)
if ($env:TAILSCALE_AUTH_KEY) {
    RunRemoteWithArgs "tailscale-up.ps1" @{ AuthKey = $env:TAILSCALE_AUTH_KEY }
}

# 6. Touchscreen (per-device, opt-in via $env:DISABLE_TOUCHSCREEN=true)
if ($DisableTouchscreen) {
    RunRemoteWithArgs "touchscreen.ps1" @{ Action = "disable" }
}

# 7. Hardening
RunRemote "remove-bloatware.ps1"
RunRemote "harden-taskbar.ps1"
RunRemote "clean-desktop.ps1"
RunRemote "tweaks-qol.ps1"
RunRemote "start-menu.ps1"

# 8. Inventario final
Step "$env:COMPUTERNAME :: inventory final"
RunRemote "inventory.ps1"

Write-Host ""
Write-Host "==> ORCHESTRATION COMPLETE for $env:COMPUTERNAME" -ForegroundColor Green
Write-Host "    finished: $(Get-Date)"
Write-Host ""
Write-Host "Win Update nao foi rodado (mata sessao no reboot)." -ForegroundColor Yellow
Write-Host "Pra atualizar Windows separadamente:" -ForegroundColor Yellow
Write-Host "  irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/win-update.ps1 | iex" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Pra ligar drift detection (state sync via repo privado, do admin host):" -ForegroundColor Yellow
Write-Host "  STATE_REPO=<owner>/<repo> ./state-sync-setup.sh $env:COMPUTERNAME" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Log completo desta run + anteriores em:" -ForegroundColor DarkGray
Write-Host "  $logFile" -ForegroundColor DarkGray

try { Stop-Transcript | Out-Null } catch {}
