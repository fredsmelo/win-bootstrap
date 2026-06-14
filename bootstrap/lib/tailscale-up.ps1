# Instalar Tailscale + conectar tailnet.
#
# Uso (PowerShell admin via SSH, scriptblock pattern):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/tailscale-up.ps1).Trim())) `
#       -AuthKey 'tskey-auth-xxxxxxxxxxxxxxxx'
#
# AuthKey: gerado em https://login.tailscale.com/admin/settings/keys (one-time)
#   - Reusable: off (per device, mais seguro)
#   - Ephemeral: off (device persistente)
#   - Expiration: 90 dias OK
#
# Idempotencia robusta:
#   - Se ja conectado e funcionando -> skip total (sem precisar de -AuthKey).
#     Use -Force pra forcar re-up (vai consumir nova auth key).
#   - Se instalado mas desconectado -> precisa -AuthKey, faz up.
#   - Se nao instalado -> precisa -AuthKey, instala + up.

param(
    [Parameter(Mandatory=$false)]
    [string]$AuthKey,

    [Parameter(Mandatory=$false)]
    [string]$Hostname = $env:COMPUTERNAME,

    [Parameter(Mandatory=$false)]
    [switch]$SshEnable,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

Write-Host "==> tailscale-up" -ForegroundColor Cyan
Write-Host ""

# 0. Idempotencia: ja conectado? Skip a menos que -Force.
$tsExePre = "$env:ProgramFiles\Tailscale\tailscale.exe"
if ((Test-Path $tsExePre) -and -not $Force) {
    $status = & $tsExePre status 2>&1 | Out-String
    if ($status -match 'logged out|not running|stopped') {
        Write-Host "Tailscale instalado mas nao conectado -- continua." -ForegroundColor Yellow
    } elseif ($status -match '^\d+\.\d+\.\d+\.\d+\s' -or $status -match $env:COMPUTERNAME) {
        Write-Host "Tailscale ja conectado (idempotente, skip). Use -Force pra forcar re-up." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "===== status atual =====" -ForegroundColor Green
        Write-Host $status
        exit 0
    }
}

if (-not $AuthKey) {
    Write-Host "ERRO: -AuthKey necessario quando nao ha conexao ativa." -ForegroundColor Red
    Write-Host "      Gera em https://login.tailscale.com/admin/settings/keys" -ForegroundColor Yellow
    exit 1
}

if ($AuthKey -notmatch '^tskey-') {
    Write-Host "ERRO: -AuthKey nao parece um tskey- valido." -ForegroundColor Red
    exit 1
}

# 1. Install Tailscale via winget (se nao instalado)
Write-Host "1/3 Verificando Tailscale instalado..." -ForegroundColor Cyan
$tsExe = "$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $tsExe) {
    Write-Host "    ja instalado." -ForegroundColor Yellow
} else {
    if (-not (Get-Module -ListAvailable Microsoft.WinGet.Client)) {
        Write-Host "    ERRO: Microsoft.WinGet.Client ausente. Rode setup-tools.ps1 primeiro." -ForegroundColor Red
        exit 1
    }
    Import-Module Microsoft.WinGet.Client
    Write-Host "    instalando via winget..." -ForegroundColor DarkGray
    $r = Install-WinGetPackage -Query 'tailscale.tailscale' -Source winget -Mode Silent
    if ($r.Status -ne 'Ok') {
        Write-Host "    install falhou: $($r.Status)" -ForegroundColor Red
        exit 1
    }
    Write-Host "    OK (v$($r.InstalledVersion))" -ForegroundColor Green
}

# 2. Garantir servico Tailscale rodando
Write-Host "2/3 Servico Tailscale..." -ForegroundColor Cyan
$svc = Get-Service Tailscale -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "    servico 'Tailscale' nao registrado ainda. Tentando iniciar manualmente em 5s." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    $svc = Get-Service Tailscale -ErrorAction SilentlyContinue
}
if ($svc -and $svc.Status -ne 'Running') {
    Start-Service Tailscale
}
Set-Service -Name Tailscale -StartupType Automatic -ErrorAction SilentlyContinue
Write-Host "    $((Get-Service Tailscale).Status)" -ForegroundColor DarkGray

# 3. tailscale up
Write-Host "3/3 tailscale up..." -ForegroundColor Cyan
$args = @(
    'up',
    "--auth-key=$AuthKey",
    "--hostname=$Hostname",
    '--accept-routes',
    '--unattended'
)
if ($SshEnable) { $args += '--ssh' }

$output = & $tsExe @args 2>&1 | Out-String
Write-Host $output

# Status final
$status = & $tsExe status 2>&1 | Out-String
Write-Host ""
Write-Host "===== tailscale status =====" -ForegroundColor Green
Write-Host $status
