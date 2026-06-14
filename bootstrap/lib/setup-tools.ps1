# Setup das ferramentas base pra automacao remota:
#   - NuGet provider (pra PowerShellGet instalar modulos)
#   - ExecutionPolicy RemoteSigned (LocalMachine)
#   - Modulo PSWindowsUpdate (Windows Update via SSH)
#   - Modulo Microsoft.WinGet.Client (winget via SSH non-interactive)
#
# Uso (PowerShell admin):
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/setup-tools.ps1 | iex
#
# Idempotente: -Force em Install-* sobrescreve sem prompt.

$ErrorActionPreference = 'Stop'

# Sanity: admin?
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

Write-Host "==> setup-tools" -ForegroundColor Cyan
Write-Host ""

Write-Host "1/4 NuGet provider..." -ForegroundColor Cyan
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
Write-Host "    OK" -ForegroundColor DarkGray

Write-Host "2/4 ExecutionPolicy LocalMachine = RemoteSigned..." -ForegroundColor Cyan
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force
Write-Host "    $(Get-ExecutionPolicy -Scope LocalMachine)" -ForegroundColor DarkGray

Write-Host "3/4 Modulo PSWindowsUpdate..." -ForegroundColor Cyan
Install-Module PSWindowsUpdate -Force -Scope AllUsers -Confirm:$false -AllowClobber
$ver = (Get-Module PSWindowsUpdate -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
Write-Host "    v$ver" -ForegroundColor DarkGray

Write-Host "4/4 Modulo Microsoft.WinGet.Client..." -ForegroundColor Cyan
Install-Module Microsoft.WinGet.Client -Force -Scope AllUsers -Confirm:$false -AllowClobber
$ver = (Get-Module Microsoft.WinGet.Client -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
Write-Host "    v$ver" -ForegroundColor DarkGray

Write-Host ""
Write-Host "setup-tools OK." -ForegroundColor Green
