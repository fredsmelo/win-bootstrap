# tweaks-qol.ps1
#
# Aplica tweaks de Quality of Life no Windows 11 25H2.
# Fontes: ChrisTitusTech winutil, privacy.sexy, The Register, XDA, elevenforum.com.
#
# Categorias:
#   - Conveniencia / UX
#   - Performance (shutdown/startup mais rapidos)
#   - Privacy (Copilot, Recall, Activity History, Bing search)
#   - Lock screen sem noticias/tips/spotlight overlays
#
# HKCU (per-user) sempre aplica. HKLM (machine-wide) tenta;
# se nao tiver elevation, ignora silenciosamente.
# Idempotente.
#
# Uso (PowerShell admin via SSH):
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/tweaks-qol.ps1 | iex

$ErrorActionPreference = 'Stop'

function Set-Reg {
    param($Path, $Name, $Value, $Type = "DWord")
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        Write-Host "  OK   $Path :: $Name = $Value"
    } catch {
        Write-Host "  SKIP $Path :: $Name -- $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

Write-Host "=== Conveniencia / UX ===" -ForegroundColor Cyan

# 1. Menus sem delay (default 400ms -> 0ms)
Set-Reg "HKCU:\Control Panel\Desktop" "MenuShowDelay" "0" "String"

# 2. Segundos no relogio
Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock" 1

# 3. 1-clique na taskbar ativa ultima janela (em vez de mostrar thumbnails)
Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LastActiveClick" 1

# 4. Settings pula tela Home, abre direto em System
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "SettingsPageVisibility" "hide:home" "String"

# 5. Mostrar file extensions (HideFileExt=0)
Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0

# 6. Verbose status no boot/shutdown
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "verbosestatus" 1

# 7. Right-click taskbar -> End Task
Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" "TaskbarEndTask" 1

Write-Host ""
Write-Host "=== Performance ===" -ForegroundColor Cyan

# 8. Shutdown rapido (5000ms -> 2000ms)
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout" "2000" "String"

# 9. Apps travados encerram automaticamente
Set-Reg "HKCU:\Control Panel\Desktop" "AutoEndTasks" "1" "String"
Set-Reg "HKCU:\Control Panel\Desktop" "WaitToKillAppTimeout" "2000" "String"
Set-Reg "HKCU:\Control Panel\Desktop" "HungAppTimeout" "2000" "String"

# 10. Startup apps sem delay
Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec" 0

Write-Host ""
Write-Host "=== Privacy ===" -ForegroundColor Cyan

# 11. Desabilita Copilot
Set-Reg "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1

# 12. Desabilita Recall (AI screenshots)
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "AllowRecallEnablement" 0
Set-Reg "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1

# 13. Bing fora do Search (Win+S)
Set-Reg "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1

# 14. Desabilita Activity History (timeline)
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 0

Write-Host ""
Write-Host "=== Lock screen sem noticias / tips / spotlight overlays ===" -ForegroundColor Cyan

# 15. Desabilita "fun facts, tips, tricks" e overlay rotativo
$cdmKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
Set-Reg $cdmKey "SubscribedContent-338387Enabled" 0
Set-Reg $cdmKey "RotatingLockScreenOverlayEnabled" 0
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" "LockScreenWidgetsEnabled" 0

Write-Host ""
Write-Host "=== Tema + Start menu UX ===" -ForegroundColor Cyan

# 16. Tema Light (apps + system)
$themeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
Set-Reg $themeKey "AppsUseLightTheme" 1
Set-Reg $themeKey "SystemUsesLightTheme" 1

# 17. Start menu All apps = Grid view (Win 11 25H2+ feature)
# Win 11 25H2 introduziu o toggle "Show all apps as grid" em Settings > Personalization > Start
Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_AllAppsView" 1

Write-Host ""
Write-Host "tweaks-qol OK. Algumas mudancas requerem logout/reboot pra refletir." -ForegroundColor Green
