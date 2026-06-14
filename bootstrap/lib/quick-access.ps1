# quick-access.ps1
#
# Reseta os pinned items do Quick Access (sidebar do File Explorer) pra
# uma lista fixa de paths. Despina tudo que nao esta na lista, pina o que
# esta. Cria dir se nao existir.
#
# Default: home (USERPROFILE), Downloads, vaults.
#
# Uso (PowerShell admin via SSH):
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/quick-access.ps1 | iex
#
# Com paths customizados (scriptblock):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/quick-access.ps1).Trim())) `
#       -Paths @("$env:USERPROFILE", "$env:USERPROFILE\Downloads", "C:\Repos")
#
# Aplica pro USER ATUAL (Quick Access e per-user, em
# %APPDATA%\Microsoft\Windows\Recent\AutomaticDestinations).
# Idempotente.

param(
    [string[]]$Paths = @(
        $env:USERPROFILE,
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\vaults"
    )
)

$ErrorActionPreference = 'Continue'

Write-Host "==> quick-access" -ForegroundColor Cyan
Write-Host ""

# 1. Cria dirs faltantes (no caso de 'vaults' nao existir)
Write-Host "[1/3] Garantindo que dirs existem..." -ForegroundColor Cyan
foreach ($p in $Paths) {
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Write-Host "  CRIOU: $p" -ForegroundColor Yellow
    } else {
        Write-Host "  OK:    $p" -ForegroundColor DarkGray
    }
}

# 2. Normalize paths (resolve caminho final, trim trailing backslash)
$desired = @{}
foreach ($p in $Paths) {
    try {
        $resolved = (Resolve-Path -Path $p -ErrorAction Stop).Path.TrimEnd('\')
        $desired[$resolved.ToLowerInvariant()] = $resolved
    } catch {
        Write-Host "  WARN: nao resolveu $p" -ForegroundColor Yellow
    }
}

# 3. Lista pinned items atuais + processa
# Quick Access pinned namespace: shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}
Write-Host ""
Write-Host "[2/3] Inspecionando Quick Access atual..." -ForegroundColor Cyan
$shell = New-Object -ComObject Shell.Application
$qa = $shell.Namespace('shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}')

# Items() inclui pinned + frequent. Pinned tem o tipo "Pinned folder" no .Type ou
# IsFolder + .ItemName presente. Filtra pelo verb 'unpinfromhome' disponivel.
$current = @()
foreach ($item in $qa.Items()) {
    if (-not $item.IsFolder) { continue }
    $verbs = $item.Verbs() | ForEach-Object { $_.Name }
    # Verb name varies por locale ("Unpin from Quick access", "Desafixar do Acesso rapido", etc).
    # Match no actual verb id atraves de InvokeVerb('unpinfromhome') que e' stable.
    # Mas pra detectar se esta pinned, checa se NAO tem 'pintohome' (pinned items nao tem verb pra pin).
    $hasPin    = $verbs -match 'pintohome|Pin to Quick'
    $hasUnpin  = $verbs -match 'unpinfromhome|Unpin from Quick|Desafixar'
    if ($hasUnpin -and -not $hasPin) {
        $current += @{ path = $item.Path.TrimEnd('\'); item = $item }
    }
}

Write-Host "  Atualmente pinned ($($current.Count)):"
$current | ForEach-Object { Write-Host "    $($_.path)" -ForegroundColor DarkGray }

# 4. Despina o que nao esta na lista desejada
Write-Host ""
Write-Host "[3/3] Reconciliando pinned items..." -ForegroundColor Cyan
$pinnedNow = @{}
foreach ($entry in $current) {
    $key = $entry.path.ToLowerInvariant()
    $pinnedNow[$key] = $true
    if (-not $desired.ContainsKey($key)) {
        Write-Host "  UNPIN: $($entry.path)" -ForegroundColor Yellow
        try { $entry.item.InvokeVerb('unpinfromhome') } catch {
            Write-Host "    falha unpin: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# 5. Pina os desejados que ainda nao estao
foreach ($key in $desired.Keys) {
    if (-not $pinnedNow.ContainsKey($key)) {
        $path = $desired[$key]
        Write-Host "  PIN:   $path" -ForegroundColor Green
        try {
            $folder = $shell.Namespace($path)
            if ($folder) { $folder.Self.InvokeVerb('pintohome') }
        } catch {
            Write-Host "    falha pin: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "  KEEP:  $($desired[$key])" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "quick-access OK. Abra File Explorer pra ver." -ForegroundColor Green
