# Bootstrap remoto generico
#
# One-liner (PowerShell admin no Windows recem-instalado):
#   $env:DEVICE_PUBKEY = 'ssh-ed25519 AAAA... mydevice'; irm <domain>/bootstrap/device.ps1 | iex
#
# O que faz:
#   1. Verifica que esta rodando como Administrator (sai se nao)
#   2. Verifica $env:DEVICE_PUBKEY (sai se ausente, com instrucao clara)
#   3. Habilita OpenSSH Server (Windows optional feature)
#   4. Inicia sshd + set startup automatico
#   5. Firewall: regra inbound TCP 22 em todos perfis
#   6. Injeta $env:DEVICE_PUBKEY em administrators_authorized_keys
#   7. Default shell sshd = PowerShell
#   8. Instala funcao 'setup-device' no PowerShell profile (PS 5.1 + PS 7)
#   9. Reporta hostname / IP / user pra completar config no admin host
#
# Pubkey NAO embutida no script -- vem via env var. Ver overlay privado
# para one-liners pre-prontos por device.

$ErrorActionPreference = 'Stop'

# ---- 0. Sanity: rodando como Administrator? ----
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($me)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode este script em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    Write-Host "      Clique direito no PowerShell -> Run as administrator." -ForegroundColor Red
    exit 1
}

# ---- 0b. Sanity: pubkey via env var ----
if (-not $env:DEVICE_PUBKEY) {
    Write-Host "ERRO: variavel `$env:DEVICE_PUBKEY ausente." -ForegroundColor Red
    Write-Host ""
    Write-Host "Cole sua pubkey ANTES do irm. Exemplo:" -ForegroundColor Yellow
    Write-Host '  $env:DEVICE_PUBKEY = "ssh-ed25519 AAAA... mydevice"; irm <domain>/bootstrap/device.ps1 | iex' -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "A pubkey deve estar no formato OpenSSH (uma linha)." -ForegroundColor Yellow
    exit 1
}
$pubkey = $env:DEVICE_PUBKEY.Trim()
if ($pubkey -notmatch '^ssh-(ed25519|rsa|ecdsa-sha2-\w+)\s+\S+') {
    Write-Host "ERRO: `$env:DEVICE_PUBKEY nao parece pubkey SSH valida:" -ForegroundColor Red
    Write-Host "  $pubkey" -ForegroundColor DarkGray
    Write-Host "Esperado formato: 'ssh-<tipo> <base64> [comment]'" -ForegroundColor Yellow
    exit 1
}

Write-Host "==> Bootstrap iniciando..." -ForegroundColor Cyan
Write-Host ""

# ---- 1. Habilitar OpenSSH Server ----
Write-Host "1/7 Habilitando OpenSSH Server..." -ForegroundColor Cyan
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
if ($cap.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
}

# ---- 2. Servico sshd ----
Write-Host "2/7 Iniciando servico sshd (startup automatico)..." -ForegroundColor Cyan
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# ---- 3. Firewall ----
Write-Host "3/7 Liberando firewall TCP 22 (todos perfis)..." -ForegroundColor Cyan
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
        -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP `
        -Action Allow -LocalPort 22 -Profile Any | Out-Null
} else {
    Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile Any -Enabled True | Out-Null
}

# ---- 4. Pubkey em administrators_authorized_keys ----
# Pegadinha: Windows ignora ~/.ssh/authorized_keys pra contas admin.
# Usa C:\ProgramData\ssh\administrators_authorized_keys (compartilhado entre todos admins).
# Padrao defensivo: ASCII puro sem BOM (sshd nao tolera UTF-16 BOM); idempotencia via -like
# (regex -notmatch teve issue silencioso em alguns runs).
Write-Host "4/7 Adicionando pubkey (caminho admin)..." -ForegroundColor Cyan
$adminKeys = "$env:ProgramData\ssh\administrators_authorized_keys"
$adminKeysDir = Split-Path $adminKeys -Parent

if (-not (Test-Path $adminKeysDir)) {
    New-Item -ItemType Directory -Path $adminKeysDir -Force | Out-Null
}

# Ler estado atual (defensivo: null/vazio/BOM)
$existing = ""
if (Test-Path $adminKeys) {
    $raw = Get-Content -Path $adminKeys -Raw -Encoding ASCII -ErrorAction SilentlyContinue
    if ($null -ne $raw) { $existing = $raw }
}

$keyBody = $pubkey.Split(' ')[1]
if ($existing -like "*$keyBody*") {
    Write-Host "    pubkey ja presente (idempotente)." -ForegroundColor Yellow
} else {
    if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) {
        $newContent = $existing + "`n" + $pubkey + "`n"
    } elseif ($existing.Length -gt 0) {
        $newContent = $existing + $pubkey + "`n"
    } else {
        $newContent = $pubkey + "`n"
    }
    [System.IO.File]::WriteAllText($adminKeys, $newContent, [System.Text.Encoding]::ASCII)
    Write-Host "    pubkey escrita ($($newContent.Length) bytes)." -ForegroundColor Green
}

# ACL obrigatoria pro sshd aceitar o arquivo
icacls $adminKeys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

# ---- 5a. ExecutionPolicy CurrentUser = RemoteSigned (permite carregar $PROFILE local) ----
# Sem isso, Win 11 Home default = Restricted, e profile com a funcao setup-device nao carrega.
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force

# ---- 5. Default shell = PowerShell (melhor pra automacao que cmd) ----
Write-Host "5/7 Configurando default shell = PowerShell..." -ForegroundColor Cyan
$openSshKey = 'HKLM:\SOFTWARE\OpenSSH'
if (-not (Test-Path $openSshKey)) {
    New-Item -Path $openSshKey -Force | Out-Null
}
New-ItemProperty -Path $openSshKey -Name DefaultShell `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
    -PropertyType String -Force | Out-Null

# ---- 6. Instalar funcao 'setup-device' no PowerShell profile ----
# Permite re-rodar orquestracao local de qualquer hora com 1 comando.
Write-Host "6/7 Instalando alias setup-device no PowerShell profile..." -ForegroundColor Cyan
$aliasFunc = "function setup-device { irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/orchestrate-local.ps1 | iex }"
$profilePaths = @(
    "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",  # PS 5.1
    "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"          # PS 7
)
foreach ($p in $profilePaths) {
    $dir = Split-Path $p -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $existing = ""
    if (Test-Path $p) {
        $raw = Get-Content -Path $p -Raw -Encoding ASCII -ErrorAction SilentlyContinue
        if ($null -ne $raw) { $existing = $raw }
    }
    if ($existing -like "*function setup-device*") {
        Write-Host "    $p (ja presente)" -ForegroundColor DarkGray
    } else {
        $newContent = if ($existing.Length -gt 0) { $existing.TrimEnd() + "`n`n" + $aliasFunc + "`n" } else { $aliasFunc + "`n" }
        [System.IO.File]::WriteAllText($p, $newContent, [System.Text.Encoding]::ASCII)
        Write-Host "    $p (adicionado)" -ForegroundColor DarkGray
    }
}

# ---- 7. Validacao + report ----
Write-Host "7/7 Validando..." -ForegroundColor Cyan
$sshd = Get-Service sshd
Write-Host "    sshd Status: $($sshd.Status), StartType: $($sshd.StartType)"

$ips = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.InterfaceAlias -notlike '*Loopback*' -and $_.IPAddress -notlike '169.*' }).IPAddress

Write-Host ""
Write-Host "===== Info pra completar config no admin host =====" -ForegroundColor Green
Write-Host "  User Windows : $env:USERNAME"
Write-Host "  Hostname     : $env:COMPUTERNAME"
Write-Host "  IPs locais   :"
$ips | ForEach-Object { Write-Host "    $_" }
Write-Host ""
Write-Host "Do admin host, testar:" -ForegroundColor Green
Write-Host "  ssh-keygen -R <ip>          # se ja tinha host key antigo" -ForegroundColor DarkGray
Write-Host "  ssh <alias> 'whoami; hostname'"
Write-Host ""
Write-Host "Se mDNS nao resolver, ajustar HostName no ~/.ssh/config pro IP acima." -ForegroundColor Green
Write-Host ""
Write-Host "Bootstrap OK." -ForegroundColor Green
