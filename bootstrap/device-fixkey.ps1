# Fix-key isolado
#
# Uso (PowerShell admin):
#   $env:DEVICE_PUBKEY = 'ssh-ed25519 AAAA... mydevice'; irm <domain>/bootstrap/device-fixkey.ps1 | iex
#
# Por que existe: o device.ps1 v1 deixou administrators_authorized_keys vazio
# em alguns runs (provavel issue com encoding/idempotencia do Add-Content via iex).
# Este script foca SO em escrever a pubkey + ACL + restart sshd, e mostra
# o conteudo final pra confirmacao visual.

$ErrorActionPreference = 'Stop'

# Sanity: admin?
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($me)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

if (-not $env:DEVICE_PUBKEY) {
    Write-Host "ERRO: variavel `$env:DEVICE_PUBKEY ausente." -ForegroundColor Red
    Write-Host "Cole pubkey ANTES do irm | iex. Exemplo:" -ForegroundColor Yellow
    Write-Host '  $env:DEVICE_PUBKEY = "ssh-ed25519 AAAA... mydevice"; irm <domain>/bootstrap/device-fixkey.ps1 | iex' -ForegroundColor DarkGray
    exit 1
}
$pubkey = $env:DEVICE_PUBKEY.Trim()

$adminKeys = "$env:ProgramData\ssh\administrators_authorized_keys"
$adminKeysDir = Split-Path $adminKeys -Parent

Write-Host "==> device-fixkey: garantindo pubkey no administrators_authorized_keys" -ForegroundColor Cyan
Write-Host ""

# 1. Garantir diretorio existe
if (-not (Test-Path $adminKeysDir)) {
    New-Item -ItemType Directory -Path $adminKeysDir -Force | Out-Null
    Write-Host "Diretorio criado: $adminKeysDir" -ForegroundColor DarkGray
}

# 2. Ler estado atual (defensivo: lida com null, vazio, BOM, etc)
$existing = ""
if (Test-Path $adminKeys) {
    $raw = Get-Content -Path $adminKeys -Raw -Encoding ASCII -ErrorAction SilentlyContinue
    if ($null -ne $raw) { $existing = $raw }
}

$keyBody = $pubkey.Split(' ')[1]  # base64 da pubkey, comparacao estavel

# 3. Decidir: ja presente OU precisa adicionar
if ($existing -like "*$keyBody*") {
    Write-Host "Pubkey ja presente (idempotente). Conteudo:" -ForegroundColor Yellow
    Get-Content $adminKeys
} else {
    # Construir novo conteudo (preserva keys de outros admins se houver)
    if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) {
        $newContent = $existing + "`n" + $pubkey + "`n"
    } elseif ($existing.Length -gt 0) {
        $newContent = $existing + $pubkey + "`n"
    } else {
        $newContent = $pubkey + "`n"
    }

    # IMPORTANTE: ASCII puro sem BOM. sshd nao tolera UTF-16 BOM.
    [System.IO.File]::WriteAllText($adminKeys, $newContent, [System.Text.Encoding]::ASCII)
    Write-Host "Pubkey escrita em: $adminKeys" -ForegroundColor Green
}

# 4. ACL obrigatoria
Write-Host ""
Write-Host "Aplicando ACL (Administrators:F + SYSTEM:F, sem heranca)..." -ForegroundColor Cyan
icacls $adminKeys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

# 5. Restart sshd pra garantir
Write-Host "Reiniciando sshd..." -ForegroundColor Cyan
Restart-Service sshd

# 6. Validacao final
Write-Host ""
Write-Host "===== Conteudo final de administrators_authorized_keys =====" -ForegroundColor Green
Get-Content $adminKeys
Write-Host ""

# 7. Verificar bytes (sanidade absoluta)
$fileBytes = [System.IO.File]::ReadAllBytes($adminKeys)
Write-Host "Tamanho do arquivo: $($fileBytes.Length) bytes" -ForegroundColor DarkGray
if ($fileBytes.Length -lt 50) {
    Write-Host "AVISO: arquivo muito pequeno. Pubkey deveria ter ~100+ bytes." -ForegroundColor Red
} else {
    Write-Host "Tamanho OK. Testar do admin host:" -ForegroundColor Green
    Write-Host "  ssh <alias> 'whoami; hostname'" -ForegroundColor DarkGray
}
