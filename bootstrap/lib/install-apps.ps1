# Instalar apps via Microsoft.WinGet.Client (winget via SSH non-interactive).
#
# Uso (PowerShell admin via SSH, scriptblock pattern):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/install-apps.ps1).Trim())) `
#       -Apps @(
#           'Microsoft.PowerToys',
#           'AgileBits.1Password',
#           @{Id='Obsidian.Obsidian'; Silent=$false},
#           @{Id='9NKSQGP7F2NH'; Source='msstore'}
#       )
#
# Formato de cada item em -Apps:
#   string             -> winget Id, modo silent
#   hashtable @{...}   -> Id (req), Source ('winget'|'msstore', default winget), Silent ($true|$false, default $true)
#
# Idempotente: pula apps ja instalados (Get-WinGetPackage check).
# Robusto: tenta silent; se der Access Violation (0xC0000005), retry sem silent.

param(
    [Parameter(Mandatory=$true)]
    [array]$Apps
)

$ErrorActionPreference = 'Stop'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

if (-not (Get-Module -ListAvailable Microsoft.WinGet.Client)) {
    Write-Host "ERRO: Microsoft.WinGet.Client ausente. Rode setup-tools.ps1 primeiro." -ForegroundColor Red
    exit 1
}
Import-Module Microsoft.WinGet.Client

Write-Host "==> install-apps ($($Apps.Count) item(s))" -ForegroundColor Cyan
Write-Host ""

$ok = 0; $skip = 0; $fail = 0; $failed = @()

foreach ($entry in $Apps) {
    # Normalizar pra hashtable
    if ($entry -is [string]) {
        $spec = @{ Id = $entry; Source = 'winget'; Silent = $true }
    } else {
        $spec = @{
            Id     = $entry.Id
            Source = if ($entry.Source) { $entry.Source } else { 'winget' }
            Silent = if ($entry.ContainsKey('Silent')) { $entry.Silent } else { $true }
        }
    }

    Write-Host "[$($spec.Id)] ($($spec.Source))..." -ForegroundColor Cyan

    # Idempotencia: ja instalado?
    $installed = Get-WinGetPackage -Id $spec.Id -ErrorAction SilentlyContinue
    if ($installed) {
        Write-Host "    ja instalado (v$($installed.InstalledVersion)). skip." -ForegroundColor Yellow
        $skip++
        continue
    }

    # Install (retry sem silent se Access Violation)
    $params = @{
        Query  = $spec.Id
        Source = $spec.Source
    }
    if ($spec.Silent) { $params.Mode = 'Silent' }

    try {
        $result = Install-WinGetPackage @params
        if ($result.Status -eq 'Ok') {
            Write-Host "    OK (v$($result.InstalledVersion))" -ForegroundColor Green
            $ok++
        } else {
            Write-Host "    Status: $($result.Status). ExtendedErrorCode: $($result.ExtendedErrorCode)" -ForegroundColor Yellow
            # Detectar Access Violation (Obsidian-like) e retentar sem silent
            if ($spec.Silent -and ($result.ExtendedErrorCode -match '0xC0000005' -or $result.RebootRequired -eq $false -and $result.Status -ne 'Ok')) {
                Write-Host "    retry sem -Mode Silent..." -ForegroundColor Yellow
                $params.Remove('Mode') | Out-Null
                $result2 = Install-WinGetPackage @params
                if ($result2.Status -eq 'Ok') {
                    Write-Host "    OK (v$($result2.InstalledVersion)) [retry]" -ForegroundColor Green
                    $ok++
                } else {
                    Write-Host "    falhou no retry: $($result2.Status)" -ForegroundColor Red
                    $fail++; $failed += $spec.Id
                }
            } else {
                $fail++; $failed += $spec.Id
            }
        }
    } catch {
        Write-Host "    EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red
        $fail++; $failed += $spec.Id
    }
}

Write-Host ""
Write-Host "===== Resumo =====" -ForegroundColor Cyan
Write-Host "  OK     : $ok" -ForegroundColor Green
Write-Host "  SKIP   : $skip" -ForegroundColor Yellow
Write-Host "  FAIL   : $fail" -ForegroundColor $(if ($fail -gt 0) {'Red'} else {'DarkGray'})
if ($fail -gt 0) {
    Write-Host "  failed : $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
