# remove-bloatware.ps1
#
# Remove pacotes AppX/UWP considerados bloatware no Win 11 25H2.
# Aplica em todos os users (-AllUsers) e remove o provisioning
# (pra nao reaparecer em users novos).
#
# 19 pacotes na lista default. Mantidos por decisao:
#   - ApplicationCompatibilityEnhancements (shims pra apps legacy)
#   - CommandPalette (novidade 25H2)
#   - PowerAutomateDesktop (caso seja usado)
#   - Microsoft.Todos (To Do)
#   - YourPhone + CrossDevice (Phone Link)
#   - WindowsSoundRecorder (Voice Recorder)
#
# Idempotente: SKIP se nao instalado.
#
# Uso (PowerShell admin via SSH):
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/remove-bloatware.ps1 | iex

$ErrorActionPreference = 'Stop'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

$packages = @(
    "Clipchamp.Clipchamp",
    "Microsoft.BingNews",
    "Microsoft.BingSearch",
    "Microsoft.BingWeather",
    "Microsoft.GamingApp",
    "Microsoft.GetHelp",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.StartExperiencesApp",
    "Microsoft.StorePurchaseApp",
    "Microsoft.Windows.DevHome",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.ZuneMusic",
    "MicrosoftCorporationII.QuickAssist",
    "MicrosoftWindows.Client.WebExperience"
)

Write-Host "Removendo $($packages.Count) pacotes AppX/UWP..." -ForegroundColor Cyan
Write-Host ""

$ok = 0; $fail = 0; $skip = 0

foreach ($name in $packages) {
    $pkg = Get-AppxPackage -AllUsers $name -ErrorAction SilentlyContinue
    if (-not $pkg) {
        Write-Host "[SKIP] $name -- nao instalado" -ForegroundColor DarkGray
        $skip++
        continue
    }
    try {
        $pkg | Remove-AppxPackage -AllUsers -ErrorAction Stop
        Write-Host "[OK]   $name" -ForegroundColor Green
        $ok++
    } catch {
        Write-Host "[FAIL] $name -- $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host "=== Removendo provisioning (impede reaparecer em users novos) ===" -ForegroundColor Cyan

$provOk = 0; $provFail = 0
foreach ($name in $packages) {
    $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $name }
    if (-not $prov) { continue }
    try {
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
        Write-Host "[OK]   provisioning: $name"
        $provOk++
    } catch {
        Write-Host "[FAIL] provisioning: $name -- $($_.Exception.Message)" -ForegroundColor Red
        $provFail++
    }
}

Write-Host ""
Write-Host "=== Resumo ===" -ForegroundColor Cyan
Write-Host "AppX:          $ok ok / $fail fail / $skip skip"
Write-Host "Provisioning:  $provOk ok / $provFail fail"
