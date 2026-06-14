# fix-ntp.ps1 -- hardening do W32Time pra sync agressivo no boot.
#
# Caso de uso: CMOS battery fraca/morta -> clock reseta no cold boot ->
# NTP precisa pegar logo. Default do Win 11 e' polling preguicoso (varias horas).
# Esse script forca:
#   - Re-registro do W32Time (limpa state corrompido)
#   - Peers publicos com flag 0x9 (SpecialInterval + Client, polling agressivo)
#   - SpecialPollInterval = 1024s (~17min) em vez do default 9h
#   - Service Automatic startup
#   - Resync imediato
#
# Idempotente: roda quantas vezes quiser.
#
# Uso (PowerShell admin):
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/fix-ntp.ps1 | iex

# IMPORTANTE: NAO setar ErrorActionPreference=Stop aqui. Native commands
# (net, w32tm) escrevem em stderr em casos benignos (servico ja parado etc)
# e Stop converte stderr-as-error em terminating exception ANTES do 2>&1
# poder engolir. Usar Continue + Stop-Service/Start-Service PS-nativos.
$ErrorActionPreference = 'Continue'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

Write-Host "==> fix-ntp" -ForegroundColor Cyan
Write-Host ""

$w32tm = "$env:windir\System32\w32tm.exe"

# 1. Parar servico (idempotente -- se ja parado, no-op)
Write-Host "[1/6] Parando W32Time (se rodando)..." -ForegroundColor Cyan
Stop-Service -Name w32time -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Write-Host "    OK" -ForegroundColor DarkGray

# 2. Re-registrar servico (limpa state corrompido)
Write-Host "[2/6] Re-registrando W32Time..." -ForegroundColor Cyan
& $w32tm /unregister *>&1 | Out-Null
Start-Sleep -Seconds 2
& $w32tm /register *>&1 | Out-Null
Start-Sleep -Seconds 2
Write-Host "    OK" -ForegroundColor DarkGray

# 3. SpecialPollInterval = 1024s (default era 32400s = 9h)
Write-Host "[3/6] SpecialPollInterval = 1024s (~17min)..." -ForegroundColor Cyan
$polKey = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient"
if (Test-Path $polKey) {
    New-ItemProperty -Path $polKey -Name "SpecialPollInterval" -Value 1024 -PropertyType DWord -Force | Out-Null
    Write-Host "    OK" -ForegroundColor DarkGray
} else {
    Write-Host "    NtpClient key ausente (sera criada apos primeiro start)" -ForegroundColor Yellow
}

# 4. Service Automatic + iniciar
Write-Host "[4/6] Service w32time = Automatic + Start..." -ForegroundColor Cyan
Set-Service -Name w32time -StartupType Automatic
Start-Service -Name w32time -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$svc = Get-Service w32time
Write-Host "    Status: $($svc.Status), StartType: $($svc.StartType)" -ForegroundColor DarkGray
if ($svc.Status -ne 'Running') {
    Write-Host "    AVISO: servico nao iniciou. Tentando manual start..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    Start-Service -Name w32time -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# 5. Configurar peers publicos com polling agressivo (flag 0x9)
#    0x1 = SpecialInterval (usa SpecialPollInterval em vez do default)
#    0x8 = Client (sincronizar como client)
#    0x9 = ambos
Write-Host "[5/6] Configurando NTP peers (Cloudflare + Google + pool.ntp.org + Windows)..." -ForegroundColor Cyan
$peers = "time.cloudflare.com,0x9 time.google.com,0x9 pool.ntp.org,0x9 time.windows.com,0x9"
& $w32tm /config /manualpeerlist:"$peers" /syncfromflags:manual /reliable:yes /update *>&1 | Out-Null

# SpecialPollInterval pode ter sido sobrescrito pelo /config /update -- re-aplica
if (Test-Path $polKey) {
    New-ItemProperty -Path $polKey -Name "SpecialPollInterval" -Value 1024 -PropertyType DWord -Force | Out-Null
}
Restart-Service -Name w32time -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Host "    OK" -ForegroundColor DarkGray

# 6. Force resync
Write-Host "[6/6] Forcando resync imediato..." -ForegroundColor Cyan
$resyncOut = & $w32tm /resync /force 2>&1 | Out-String
Write-Host "    $($resyncOut.Trim())" -ForegroundColor DarkGray
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "===== Status =====" -ForegroundColor Green
& $w32tm /query /status

Write-Host ""
Write-Host "===== Peers =====" -ForegroundColor Green
& $w32tm /query /peers

Write-Host ""
Write-Host "fix-ntp OK." -ForegroundColor Green
Write-Host "Se o problema persistir no proximo cold boot, suspeitar bateria CMOS." -ForegroundColor Yellow
Write-Host "Procurar guia ifixit pra modelo especifico do device." -ForegroundColor DarkGray
