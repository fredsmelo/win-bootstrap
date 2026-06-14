# harden-taskbar.ps1
#
# Configura aspectos visuais da taskbar do user atual:
#   - Esconde barra de pesquisa (SearchboxTaskbarMode)
#   - Esconde widgets (via Group Policy AllowNewsAndInterests -- TaskbarDa direto e bloqueado em Win 11 25H2)
#   - Esconde botao Task View (ShowTaskViewButton)
#   - Despina todos os icones da taskbar exceto File Explorer
#   - Restart explorer.exe pra aplicar
#
# Aplica pro USER ATUAL (HKCU). HKLM tambem (machine-wide) se tiver elevation.
# Idempotente.
#
# Uso (PowerShell admin via SSH):
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/harden-taskbar.ps1 | iex

$ErrorActionPreference = 'Stop'

# 1) Esconde search box
Write-Host "[1/4] Esconde search box (SearchboxTaskbarMode=0)" -ForegroundColor Cyan
$searchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
if (-not (Test-Path $searchKey)) { New-Item -Path $searchKey -Force | Out-Null }
New-ItemProperty -Path $searchKey -Name "SearchboxTaskbarMode" -Value 0 -PropertyType DWord -Force | Out-Null

# 2) Esconde widgets + Task View button
Write-Host "[2/4] Esconde widgets (AllowNewsAndInterests=0) e Task View (ShowTaskViewButton=0)" -ForegroundColor Cyan
$dshKeyUser = "HKCU:\Software\Policies\Microsoft\Dsh"
if (-not (Test-Path $dshKeyUser)) { New-Item -Path $dshKeyUser -Force | Out-Null }
New-ItemProperty -Path $dshKeyUser -Name "AllowNewsAndInterests" -Value 0 -PropertyType DWord -Force | Out-Null

try {
    $dshKeyMachine = "HKLM:\Software\Policies\Microsoft\Dsh"
    if (-not (Test-Path $dshKeyMachine)) { New-Item -Path $dshKeyMachine -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -Path $dshKeyMachine -Name "AllowNewsAndInterests" -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    Write-Host "  Tambem aplicou em HKLM (machine-wide)" -ForegroundColor DarkGray
} catch {
    Write-Host "  HKLM nao acessivel (precisa elevation) -- HKCU basta pro user atual" -ForegroundColor DarkGray
}

$advKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
New-ItemProperty -Path $advKey -Name "ShowTaskViewButton" -Value 0 -PropertyType DWord -Force | Out-Null

# 3) Despina tudo exceto File Explorer (e garante File Explorer pinned)
Write-Host "[3/4] Despina taskbar (mantem so File Explorer) + garante File Explorer pinned" -ForegroundColor Cyan
$pinDir = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
if (-not (Test-Path $pinDir)) {
    New-Item -ItemType Directory -Path $pinDir -Force | Out-Null
}
Get-ChildItem $pinDir -Filter "*.lnk" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne "File Explorer.lnk" } | ForEach-Object {
        Write-Host "  Removendo: $($_.Name)"
        Remove-Item $_.FullName -Force
    }

# Garante File Explorer.lnk existe (caso nao esteja pinned por padrao)
$feShortcut = Join-Path $pinDir "File Explorer.lnk"
if (-not (Test-Path $feShortcut)) {
    Write-Host "  Criando File Explorer.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($feShortcut)
    $lnk.TargetPath = "$env:windir\explorer.exe"
    $lnk.IconLocation = "$env:windir\explorer.exe,0"
    $lnk.Save()
}

# Reseta o registry Taskband\Favorites (binary blob com a ordem dos pins)
$taskbandKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
if (Test-Path $taskbandKey) {
    Remove-ItemProperty -Path $taskbandKey -Name "Favorites" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $taskbandKey -Name "FavoritesResolve" -ErrorAction SilentlyContinue
}

# 4) Restart explorer.exe pra aplicar
Write-Host "[4/4] Restart explorer.exe" -ForegroundColor Cyan
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
    Start-Process explorer.exe
}

Write-Host ""
Write-Host "harden-taskbar OK." -ForegroundColor Green
