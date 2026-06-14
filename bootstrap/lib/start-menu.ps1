# start-menu.ps1
#
# Customiza Start Menu do Win 11 25H2:
#   1. Pin lista de apps (Settings, WhatsApp, Calculator, Clock, Notepad, Snipping Tool)
#      via policy ConfigureStartPins (Win 11 Home/Pro). Despina o que nao esta na lista.
#   2. Folders ao lado do power button: Personal Folder + Settings
#      via VisiblePlaces REG_BINARY (HKCU).
#   3. Restart StartMenuExperienceHost pra aplicar.
#
# Uso (PowerShell admin via SSH):
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/start-menu.ps1 | iex
#
# Ou customizar pin list:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/start-menu.ps1).Trim())) `
#       -AppIds @("Microsoft.WindowsCalculator_8wekyb3d8bbwe!App", ...)
#
# Pode precisar logout/login pra policy aplicar totalmente.

param(
    [Parameter(Mandatory=$false)]
    [string[]]$AppIds = @(
        "windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel",
        "5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App",
        "Microsoft.WindowsCalculator_8wekyb3d8bbwe!App",
        "Microsoft.WindowsAlarms_8wekyb3d8bbwe!App",
        "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App",
        "Microsoft.ScreenSketch_8wekyb3d8bbwe!App"
    )
)

$ErrorActionPreference = 'Stop'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

Write-Host "==> start-menu" -ForegroundColor Cyan
Write-Host ""

# ---- 1. Pin lista via policy ConfigureStartPins ----
Write-Host "[1/3] Aplicando ConfigureStartPins policy ($($AppIds.Count) apps)..." -ForegroundColor Cyan

$pinnedListObj = @{
    pinnedList = @($AppIds | ForEach-Object { @{ packagedAppId = $_ } })
}
$pinnedListJson = $pinnedListObj | ConvertTo-Json -Depth 4 -Compress

$policyKey = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
if (-not (Test-Path $policyKey)) { New-Item -Path $policyKey -Force | Out-Null }
New-ItemProperty -Path $policyKey -Name "ConfigureStartPins" -Value $pinnedListJson -PropertyType String -Force | Out-Null
New-ItemProperty -Path $policyKey -Name "ConfigureStartPins_ProviderSet" -Value 1 -PropertyType DWord -Force | Out-Null
# WinningProvider necessario pra policy ser respeitada
New-ItemProperty -Path $policyKey -Name "ConfigureStartPins_WinningProvider" -Value "B5292708-1619-419B-9923-E5D9F3925E71" -PropertyType String -Force | Out-Null
Write-Host "    OK" -ForegroundColor Green

# ---- 2. VisiblePlaces (Folders ao lado do Power) ----
# Cada folder ocupa 16 bytes (GUID em formato REG_BINARY).
# Ordem definida no array = ordem de exibicao no Start menu.
Write-Host "[2/3] VisiblePlaces (Personal Folder + Settings ao lado do Power)..." -ForegroundColor Cyan

# Personal Folder: {5E6C858F-0E22-4760-9AFE-EA3317B67173}
$personalBytes = [byte[]](0x8F, 0x85, 0x6C, 0x5E, 0x22, 0x0E, 0x60, 0x47, 0x9A, 0xFE, 0xEA, 0x33, 0x17, 0xB6, 0x71, 0x73)
# Settings:        {F8A1F80E-D72A-D411-BDAF-00C04F60B9F0}
$settingsBytes = [byte[]](0x0E, 0xF8, 0xA1, 0xF8, 0x2A, 0xD7, 0x11, 0xD4, 0xBD, 0xAF, 0x00, 0xC0, 0x4F, 0x60, 0xB9, 0xF0)

$visiblePlaces = $personalBytes + $settingsBytes

$startKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
if (-not (Test-Path $startKey)) { New-Item -Path $startKey -Force | Out-Null }
New-ItemProperty -Path $startKey -Name "VisiblePlaces" -Value $visiblePlaces -PropertyType Binary -Force | Out-Null
Write-Host "    OK ($($visiblePlaces.Length) bytes = $($visiblePlaces.Length / 16) folders)" -ForegroundColor Green

# ---- 3. Restart StartMenuExperienceHost ----
Write-Host "[3/3] Restart StartMenuExperienceHost (despinar atuais + carregar policy)..." -ForegroundColor Cyan

# Deletar start2.bin pra forcar Windows a regenerar a partir da policy
$start2 = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin"
if (Test-Path $start2) {
    try {
        Remove-Item $start2 -Force -ErrorAction Stop
        Write-Host "    start2.bin removido" -ForegroundColor DarkGray
    } catch {
        # Pode estar locked pelo processo -- vamos matar o processo primeiro
        Write-Host "    start2.bin locked, vai resetar via kill do processo" -ForegroundColor DarkGray
    }
}

Get-Process StartMenuExperienceHost -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Tentar deletar de novo depois do kill
if (Test-Path $start2) {
    Remove-Item $start2 -Force -ErrorAction SilentlyContinue
}

Write-Host "    OK (StartMenuExperienceHost respawn automatico)" -ForegroundColor Green

Write-Host ""
Write-Host "start-menu aplicado." -ForegroundColor Green
Write-Host "Pode ser necessario logout/login pra policy ConfigureStartPins ser aplicada." -ForegroundColor Yellow
Write-Host "Validar: abrir Start menu apos relogin." -ForegroundColor DarkGray
