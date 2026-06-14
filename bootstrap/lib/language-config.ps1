# language-config.ps1
#
# Configura linguas + teclados no Windows. Por padrao instala todas as
# linguas (Install-Language baixa FOD do MS Update se faltar), forca
# UM unico keyboard layout pra todas (default: US International), e
# opcionalmente seta a linguagem de exibicao do user.
#
# Uso (PowerShell admin via SSH, scriptblock pattern):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/language-config.ps1).Trim())) `
#       -Languages "en-US","pt-BR" -KeyboardLayout 00020409 -DisplayLanguage pt-BR
#
# Params:
#   -Languages         array de BCP-47 tags, ex: "en-US","pt-BR". Ordem importa
#                      (primeira = preferida do user).
#   -KeyboardLayout    hex string do layout (default "00020409" = US International).
#                      Outras refs: 00000409 = US, 00000416 = PT-BR ABNT2.
#                      Aplicado MESMO LAYOUT pra TODAS as linguas.
#   -DisplayLanguage   (opcional) BCP-47 da lingua de exibicao do user. Se setada,
#                      garante o FOD instalado e configura como preferida.
#                      Tem efeito apos sign-out/reboot.
#
# Idempotente.

param(
    [Parameter(Mandatory=$true)][string[]]$Languages,
    [string]$KeyboardLayout = '00020409',
    [string]$DisplayLanguage = ''
)

$ErrorActionPreference = 'Stop'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

Write-Host "==> language-config" -ForegroundColor Cyan
Write-Host "    Languages       : $($Languages -join ', ')" -ForegroundColor DarkGray
Write-Host "    Keyboard layout : $KeyboardLayout (mesmo pra todas)" -ForegroundColor DarkGray
Write-Host "    Display language: $(if ($DisplayLanguage) { $DisplayLanguage } else { '(sem mudanca)' })" -ForegroundColor DarkGray
Write-Host ""

# 1. Instalar FODs faltantes (Install-Language e cmdlet Win 11+).
# Baixa de MS Update; pode demorar alguns minutos por lingua nova.
Write-Host "[1/4] Verificando language packs instalados..." -ForegroundColor Cyan
$installed = @()
try { $installed = (Get-InstalledLanguage -ErrorAction Stop).LanguageId } catch {
    Write-Host "    WARN: Get-InstalledLanguage indisponivel (precisa Win 11). Skip install." -ForegroundColor Yellow
}
foreach ($lang in $Languages) {
    if ($lang -in $installed) {
        Write-Host "    OK  $lang (ja instalado)" -ForegroundColor DarkGray
    } else {
        Write-Host "    Instalando $lang via FOD..." -ForegroundColor Yellow
        try {
            Install-Language -Language $lang -ErrorAction Stop | Out-Null
            Write-Host "        OK" -ForegroundColor Green
        } catch {
            Write-Host "        FALHOU: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# 2. Montar UserLanguageList com SO o keyboard layout especificado por lingua
Write-Host ""
Write-Host "[2/4] Configurando UserLanguageList + input methods..." -ForegroundColor Cyan
$list = New-WinUserLanguageList -Language $Languages[0]
for ($i = 1; $i -lt $Languages.Count; $i++) {
    $list.Add($Languages[$i])
}
foreach ($lang in $list) {
    $tag = $lang.LanguageTag
    try {
        $lcid = (Get-Culture -Name $tag).LCID.ToString('X4')
    } catch {
        Write-Host "    WARN: LCID nao resolvido pra $tag. Skip." -ForegroundColor Yellow
        continue
    }
    $ime = "${lcid}:${KeyboardLayout}"
    $lang.InputMethodTips.Clear()
    $lang.InputMethodTips.Add($ime) | Out-Null
    Write-Host "    $tag (LCID=$lcid) -> input $ime" -ForegroundColor DarkGray
}
Set-WinUserLanguageList -LanguageList $list -Force
Write-Host "    OK" -ForegroundColor Green

# 3. Display language override (opcional)
Write-Host ""
Write-Host "[3/4] Display language..." -ForegroundColor Cyan
if ($DisplayLanguage) {
    try {
        Set-WinUILanguageOverride -Language $DisplayLanguage
        Write-Host "    OK: $DisplayLanguage (efeito apos sign-out/reboot)" -ForegroundColor Green
        # Tambem ajusta preferred UI ranking
        try { Set-SystemPreferredUILanguage -Language $DisplayLanguage -ErrorAction Stop } catch {}
    } catch {
        Write-Host "    FALHOU: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "    (sem mudanca solicitada)" -ForegroundColor DarkGray
}

# 4. Validacao
Write-Host ""
Write-Host "[4/4] Estado atual..." -ForegroundColor Cyan
$current = Get-WinUserLanguageList
$current | ForEach-Object {
    Write-Host "    $($_.LanguageTag) :: $($_.InputMethodTips -join ', ')" -ForegroundColor DarkGray
}
Write-Host "    UI override: $((Get-WinUILanguageOverride).Name)" -ForegroundColor DarkGray

Write-Host ""
Write-Host "language-config OK." -ForegroundColor Green
if ($DisplayLanguage) {
    Write-Host "AVISO: display language so reflete totalmente apos sign-out/reboot." -ForegroundColor Yellow
}
