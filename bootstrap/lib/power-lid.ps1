# power-lid.ps1
#
# Configura acao do botao do lid (fechar a tampa do notebook). Aplica
# separadamente pra modo AC (plugado) e DC (bateria).
#
# Uso (PowerShell admin via SSH, scriptblock pattern):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/power-lid.ps1).Trim())) `
#       -OnAC nothing -OnDC nothing
#
# Valores aceitos pra -OnAC / -OnDC:
#   nothing    -> 0 (default Win = 1 no laptop)
#   sleep      -> 1
#   hibernate  -> 2
#   shutdown   -> 3
#
# Idempotente.

param(
    [Parameter(Mandatory=$true)][ValidateSet('nothing','sleep','hibernate','shutdown')][string]$OnAC,
    [Parameter(Mandatory=$true)][ValidateSet('nothing','sleep','hibernate','shutdown')][string]$OnDC
)

$ErrorActionPreference = 'Stop'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

$map = @{ nothing = 0; sleep = 1; hibernate = 2; shutdown = 3 }
$acVal = $map[$OnAC]
$dcVal = $map[$OnDC]

Write-Host "==> power-lid (AC=$OnAC=$acVal, DC=$OnDC=$dcVal)" -ForegroundColor Cyan
Write-Host ""

# SUB_BUTTONS = 4f971e89-eebd-4455-a8de-9e59040e7347
# LIDACTION   = 5ca83367-6e45-459f-a27b-476b1d01c936
$sub = '4f971e89-eebd-4455-a8de-9e59040e7347'
$set = '5ca83367-6e45-459f-a27b-476b1d01c936'

& powercfg /setacvalueindex SCHEME_CURRENT $sub $set $acVal | Out-Null
& powercfg /setdcvalueindex SCHEME_CURRENT $sub $set $dcVal | Out-Null
& powercfg -setactive SCHEME_CURRENT | Out-Null

Write-Host "OK. Verificacao via powercfg /q:" -ForegroundColor Green
$query = & powercfg /q SCHEME_CURRENT $sub $set | Out-String
$current = $query -split "`n" | Select-String "Current AC Power Setting Index|Current DC Power Setting Index"
$current | ForEach-Object { Write-Host "  $($_.Line.Trim())" -ForegroundColor DarkGray }
