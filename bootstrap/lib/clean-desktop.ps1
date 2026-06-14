# clean-desktop.ps1
#
# Limpa o Desktop do user atual + esconde icones padroes do sistema
# exceto a Lixeira.
#
# Acoes:
#   1. Apaga TODOS .lnk e .url do Desktop (per-user + Public)
#   2. Esconde icones padrao: This PC, User Files, Network, Control Panel
#   3. Mostra a Lixeira (Recycle Bin)
#   4. Restart explorer.exe pra aplicar
#
# Outros arquivos (.ps1, .txt, docs etc) NAO sao apagados -- so atalhos (.lnk/.url).
# Idempotente.
#
# Uso (PowerShell admin via SSH):
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/clean-desktop.ps1 | iex

$ErrorActionPreference = 'Stop'

Write-Host "[1/3] Apagando atalhos do Desktop..." -ForegroundColor Cyan

$desktops = @(
    "$env:USERPROFILE\Desktop",
    "$env:PUBLIC\Desktop"
)

foreach ($d in $desktops) {
    if (-not (Test-Path $d)) { continue }
    Get-ChildItem $d -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  Removendo: $d\$($_.Name)"
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem $d -Filter "*.url" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  Removendo: $d\$($_.Name)"
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "[2/3] Esconde icones padrao (mantem so Lixeira)..." -ForegroundColor Cyan

# CLSIDs dos icones padrao do Desktop (HideDesktopIcons: 1 = escondido, 0 = visivel)
$iconRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
if (-not (Test-Path $iconRegPath)) { New-Item -Path $iconRegPath -Force | Out-Null }

$hide = @{
    "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" = "This PC (Computer)"
    "{59031a47-3f72-44a7-89c5-5595fe6b30ee}" = "User's Files (Home)"
    "{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}" = "Network"
    "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}" = "Control Panel"
}
$show = @{
    "{645FF040-5081-101B-9F08-00AA002F954E}" = "Recycle Bin (Lixeira)"
}

foreach ($clsid in $hide.Keys) {
    New-ItemProperty -Path $iconRegPath -Name $clsid -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host "  Esconde: $($hide[$clsid])"
}
foreach ($clsid in $show.Keys) {
    New-ItemProperty -Path $iconRegPath -Name $clsid -Value 0 -PropertyType DWord -Force | Out-Null
    Write-Host "  Mostra:  $($show[$clsid])"
}

Write-Host ""
Write-Host "[3/3] Restart explorer.exe..." -ForegroundColor Cyan
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
    Start-Process explorer.exe
}

Write-Host ""
Write-Host "clean-desktop OK." -ForegroundColor Green
