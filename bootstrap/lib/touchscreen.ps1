# Touchscreen disable/enable -- contorno pra ghost touch em digitizer falhando.
#
# Uso (PowerShell admin via SSH, scriptblock pattern):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/touchscreen.ps1).Trim())) -Action disable
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/touchscreen.ps1).Trim())) -Action enable
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/touchscreen.ps1).Trim())) -Action status
#
# -IncludePen $true se ghost events vierem tambem pelo stylus/pen
#   (raro, mas alguns digitizers compartilham canal)
#
# Alvo: todos PnP devices com FriendlyName = "HID-compliant touch screen".
# Survives reboots (Disable-PnpDevice persiste no registry).
# Idempotente.

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('disable','enable','status')]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [switch]$IncludePen
)

$ErrorActionPreference = 'Stop'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($Action -ne 'status' -and -not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

# Coletar candidatos
$candidates = Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -eq 'HID-compliant touch screen' }

if ($IncludePen) {
    # Adiciona "HID-compliant pen" (alguns digitizers)
    $candidates += Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'pen|stylus' -and $_.FriendlyName -notmatch 'pad' }
}

if (-not $candidates -or $candidates.Count -eq 0) {
    Write-Host "Nenhum touchscreen HID encontrado. Nada a fazer." -ForegroundColor Yellow
    exit 0
}

Write-Host "==> touchscreen -Action $Action" -ForegroundColor Cyan
Write-Host ""
Write-Host "Devices alvo:" -ForegroundColor Cyan
$candidates | Select-Object Status, FriendlyName, InstanceId | Format-Table -AutoSize -Wrap | Out-String | Write-Host

switch ($Action) {
    'status' {
        # Ja imprimiu acima. Adicionar sumario.
        $disabledCount = ($candidates | Where-Object { $_.Status -eq 'Error' -or $_.ConfigManagerErrorCode -eq 22 }).Count
        Write-Host "Total: $($candidates.Count) | Desabilitados: $disabledCount" -ForegroundColor Cyan
    }
    'disable' {
        foreach ($d in $candidates) {
            if ($d.Status -eq 'Error') {
                Write-Host "  [skip] $($d.FriendlyName) ja desabilitado." -ForegroundColor Yellow
                continue
            }
            Write-Host "  [disable] $($d.FriendlyName)..." -ForegroundColor Cyan
            try {
                Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
                Write-Host "    OK" -ForegroundColor Green
            } catch {
                Write-Host "    FAIL: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Host ""
        Write-Host "Estado final:" -ForegroundColor Cyan
        Get-PnpDevice -Class HIDClass | Where-Object { $_.FriendlyName -eq 'HID-compliant touch screen' } |
            Select-Object Status, FriendlyName | Format-Table -AutoSize | Out-String | Write-Host
        Write-Host "Se ghost touches persistirem, re-rodar com -IncludePen ou desabilitar USB parent manualmente." -ForegroundColor DarkGray
    }
    'enable' {
        foreach ($d in $candidates) {
            if ($d.Status -eq 'OK') {
                Write-Host "  [skip] $($d.FriendlyName) ja habilitado." -ForegroundColor Yellow
                continue
            }
            Write-Host "  [enable] $($d.FriendlyName)..." -ForegroundColor Cyan
            try {
                Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
                Write-Host "    OK" -ForegroundColor Green
            } catch {
                Write-Host "    FAIL: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Host ""
        Write-Host "Estado final:" -ForegroundColor Cyan
        Get-PnpDevice -Class HIDClass | Where-Object { $_.FriendlyName -eq 'HID-compliant touch screen' } |
            Select-Object Status, FriendlyName | Format-Table -AutoSize | Out-String | Write-Host
    }
}
