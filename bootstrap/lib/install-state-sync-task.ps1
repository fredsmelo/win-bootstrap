# install-state-sync-task.ps1
#
# Cria/atualiza Scheduled Task `DeviceBootstrap.StateSync` que faz drift detection
# via commits no repo privado <StateRepo>. Roda 2x: 2min apos boot + diario 06:00 local.
#
# Pre-requisito: SSH key dedicada ja em C:\ProgramData\device-bootstrap\ssh\id_<host>_state
# (escrita pelo state-sync-setup.sh do lado Mac antes de chamar este script).
#
# Idempotente: re-register OK.
#
# Uso (chamado pelo state-sync-setup.sh; nao pra rodar direto):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/install-state-sync-task.ps1).Trim())) `
#       -Hostname 'mydevice' -StateRepo '<owner>/<repo>'

param(
    [Parameter(Mandatory=$true)][string]$Hostname,
    [Parameter(Mandatory=$true)][string]$StateRepo
)

$ErrorActionPreference = 'Stop'

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: rode em PowerShell COMO ADMINISTRATOR." -ForegroundColor Red
    exit 1
}

Write-Host "==> install-state-sync-task (host=$Hostname, repo=$StateRepo)" -ForegroundColor Cyan
Write-Host ""

$taskName    = 'DeviceBootstrap.StateSync'
$baseDir     = 'C:\ProgramData\device-bootstrap'
$sshDir      = "$baseDir\ssh"
$keyPath     = "$sshDir\id_${Hostname}_state"
$repoDir     = "$baseDir\repo"
$syncScript  = "$baseDir\state-sync.ps1"
$logFile     = 'C:\Users\Public\device-bootstrap-state-sync.log'

# ---- 1. Sanity: key existe? ----
Write-Host "[1/6] Sanity check SSH key..." -ForegroundColor Cyan
if (-not (Test-Path $keyPath)) {
    Write-Host "ERRO: SSH key nao encontrada em $keyPath" -ForegroundColor Red
    Write-Host "      Esperado: state-sync-setup.sh ja copiou via SCP." -ForegroundColor Red
    exit 1
}
# ACL: SYSTEM only (mesma do administrators_authorized_keys)
icacls $keyPath /inheritance:r /grant 'SYSTEM:F' /grant 'Administrators:F' | Out-Null
Write-Host "    OK ($keyPath)" -ForegroundColor DarkGray

# ---- 2. Pre-popular known_hosts pra github.com (evita prompt) ----
Write-Host "[2/6] Configurando known_hosts pra github.com..." -ForegroundColor Cyan
$knownHosts = "$sshDir\known_hosts"
if (-not (Test-Path $knownHosts) -or -not ((Get-Content $knownHosts -Raw -ErrorAction SilentlyContinue) -match 'github\.com')) {
    try {
        $ghKeys = & ssh-keyscan -t ed25519,rsa github.com 2>$null
        Add-Content -Path $knownHosts -Value $ghKeys -Encoding ASCII
        Write-Host "    OK" -ForegroundColor DarkGray
    } catch {
        Write-Host "    WARN: ssh-keyscan falhou; usando StrictHostKeyChecking=accept-new" -ForegroundColor Yellow
    }
} else {
    Write-Host "    ja presente." -ForegroundColor DarkGray
}

# Comando SSH usado pelo git (string unica pra GIT_SSH_COMMAND e core.sshCommand)
$gitSshCmd = "ssh -i `"$keyPath`" -o UserKnownHostsFile=`"$knownHosts`" -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes"

# ---- 2b. Garantir git instalado ----
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "    git ausente, instalando via winget (Git.Git)..." -ForegroundColor Yellow
    if (Get-Module -ListAvailable Microsoft.WinGet.Client) {
        Import-Module Microsoft.WinGet.Client -ErrorAction SilentlyContinue
        Install-WinGetPackage -Id 'Git.Git' -Mode Silent | Out-Null
    } else {
        & winget install --id Git.Git -e --silent --accept-source-agreements --accept-package-agreements | Out-Null
    }
    # Refresh PATH na sessao atual
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "ERRO: git nao disponivel apos install." -ForegroundColor Red
        exit 1
    }
    Write-Host "    OK ($(git --version))" -ForegroundColor DarkGray
}

# ---- 3. Clone repo se nao existe ----
Write-Host "[3/6] Repo local em $repoDir..." -ForegroundColor Cyan
# Git escreve "Cloning into..." na stderr (normal); EAP=Stop+2>&1 trata como erro.
# Localmente baixa pra Continue ao redor de native commands; checa $LASTEXITCODE.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    if (Test-Path "$repoDir\.git") {
        Write-Host "    ja clonado. skip." -ForegroundColor DarkGray
    } else {
        if (Test-Path $repoDir) { Remove-Item -Path $repoDir -Recurse -Force }
        $env:GIT_SSH_COMMAND = $gitSshCmd
        & git clone "git@github.com:$StateRepo.git" $repoDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERRO: git clone falhou (exit $LASTEXITCODE)." -ForegroundColor Red
            exit 1
        }
    }

    # Configurar repo: ssh command + identidade per-device
    & git -C $repoDir config core.sshCommand $gitSshCmd
    & git -C $repoDir config user.name  $Hostname
    & git -C $repoDir config user.email "$Hostname@device-bootstrap.local"
} finally {
    $ErrorActionPreference = $prevEAP
}

# ---- 4. Escrever state-sync.ps1 ----
Write-Host "[4/6] Escrevendo $syncScript..." -ForegroundColor Cyan

# Single-quoted here-string (sem interpolacao no install time) com placeholders.
# Substitui depois -- evita escape hell de `$, `(, ``$().
$syncTemplate = @'
# state-sync.ps1 -- disparado por DeviceBootstrap.StateSync. NAO edite a mao;
# regerado por install-state-sync-task.ps1.
#
# Fluxo:
#   1. git pull --rebase (sync com remote, autostash safety)
#   2. Coleta state -> <repo>/<host>/{inventory.md,state.json,meta.json}
#   3. git diff --quiet -> sem mudanca, exit (silencioso)
#   4. com diff -> commit + push, log

$ErrorActionPreference = 'Continue'

$hostName = '__HOSTNAME__'
$repoDir  = '__REPODIR__'
$logFile  = '__LOGFILE__'
$env:GIT_SSH_COMMAND = '__GITSSHCMD__'

function Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts] $msg" | Out-File -Append -FilePath $logFile -Encoding ASCII
}

Log "===== sync start ====="

# 1. Pull
try {
    $pullOut = & git -C $repoDir pull --rebase --autostash 2>&1 | Out-String
    Log "pull: $($pullOut.Trim())"
} catch {
    Log "ERROR pull: $($_.Exception.Message)"
    exit 1
}

# 2. Dir do host
$hostDir = Join-Path $repoDir $hostName
if (-not (Test-Path $hostDir)) { New-Item -ItemType Directory -Path $hostDir -Force | Out-Null }

# 3a. State.json (estruturado, sorted, deterministico)
# Apps em try/catch isolado: Microsoft.WinGet.Client cmdlet exige PS 7+;
# Scheduled Task SYSTEM roda powershell.exe (PS 5.1) -> throw. Tenta via pwsh.exe
# se disponivel; se falhar, segue com apps vazio (resto do state ainda registra).
$apps = @()
try {
    # Probe pwsh.exe: PATH primeiro, depois MSI install, depois AppX install path.
    # SYSTEM context PATH nao tem alias per-user de PS 7 (WindowsApps launcher);
    # AppX install vive em C:\Program Files\WindowsApps\Microsoft.PowerShell_<version>_x64__<hash>\pwsh.exe
    $pwshExe = $null
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($cmd) {
        $pwshExe = $cmd.Source
    } else {
        # MSI install paths
        $candidates = @(
            "$env:ProgramFiles\PowerShell\7\pwsh.exe",
            "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe"
        )
        foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { $pwshExe = $c; break } }

        # AppX install (wildcard pra cobrir version bumps)
        if (-not $pwshExe) {
            $appxPwsh = Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.PowerShell_*_x64*\pwsh.exe" -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending | Select-Object -First 1
            if ($appxPwsh) { $pwshExe = $appxPwsh.FullName }
        }
    }

    if ($pwshExe) {
        $appsCmd = "Import-Module Microsoft.WinGet.Client -ErrorAction Stop; @(Get-WinGetPackage | Where-Object Id | Sort-Object Id | ForEach-Object { @{ id = `$_.Id; version = `$_.InstalledVersion; source = `$_.Source } }) | ConvertTo-Json -Depth 5"
        $appsRaw = & $pwshExe -NoProfile -NonInteractive -Command $appsCmd 2>$null
        if ($appsRaw) {
            $parsed = $appsRaw | ConvertFrom-Json
            $apps = @($parsed | ForEach-Object { @{ id = $_.id; version = $_.version; source = $_.source } })
        }
    } else {
        Log "apps collection skip: pwsh.exe nao encontrado (PS 7 ausente). state.json sem 'apps'."
    }
} catch {
    Log "apps collection skip: $($_.Exception.Message)"
}

try {
    $services = @(Get-Service |
        Where-Object { $_.StartType -eq 'Automatic' } |
        Sort-Object Name |
        ForEach-Object { @{ name = $_.Name; status = $_.Status.ToString() } })

    $tasks = @(Get-ScheduledTask |
        Where-Object { $_.TaskName -like 'DeviceBootstrap.*' } |
        Sort-Object TaskName |
        ForEach-Object { @{ name = $_.TaskName; state = $_.State.ToString() } })

    $bitlocker = $null
    try {
        $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
        $bitlocker = @{
            volumeStatus     = $bl.VolumeStatus.ToString()
            protectionStatus = $bl.ProtectionStatus.ToString()
            encryptionMethod = $bl.EncryptionMethod.ToString()
        }
    } catch { $bitlocker = @{ status = 'unavailable' } }

    $tpm = $null
    try {
        $t = Get-Tpm -ErrorAction Stop
        $tpm = @{ present = $t.TpmPresent; ready = $t.TpmReady; enabled = $t.TpmEnabled }
    } catch { $tpm = @{ status = 'unavailable' } }

    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS

    $state = [ordered]@{
        host = $hostName
        os   = @{
            caption     = $os.Caption
            version     = $os.Version
            build       = $os.BuildNumber
            arch        = $os.OSArchitecture
            installDate = $os.InstallDate.ToString('yyyy-MM-dd')
        }
        hardware = @{
            manufacturer = $cs.Manufacturer
            model        = $cs.Model
            ramGB        = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        }
        bios = @{
            version     = $bios.SMBIOSBIOSVersion
            serial      = $bios.SerialNumber
            releaseDate = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('yyyy-MM-dd') } else { $null }
        }
        tpm       = $tpm
        bitlocker = $bitlocker
        apps      = $apps
        services  = $services
        tasks     = $tasks
    }

    $json = $state | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText((Join-Path $hostDir 'state.json'), $json, [System.Text.Encoding]::UTF8)

    # 3b. inventory.md derivado do $state (human-readable)
    if ($state.apps.Count -gt 0) {
        $appLines = ($state.apps | ForEach-Object { "- ``$($_.id)`` v$($_.version) [$($_.source)]" }) -join "`r`n"
    } else {
        $appLines = "_(nenhum app via winget)_"
    }
    if ($state.tasks.Count -gt 0) {
        $taskLines = ($state.tasks | ForEach-Object { "- ``$($_.name)``: $($_.state)" }) -join "`r`n"
    } else {
        $taskLines = "_(nenhuma)_"
    }
    $svcLines = ($state.services | Select-Object -First 50 | ForEach-Object { "- ``$($_.name)`` ($($_.status))" }) -join "`r`n"

    $md  = "# $hostName`r`n`r`n"
    $md += "## Identity`r`n`r`n"
    $md += "- OS: $($state.os.caption) build $($state.os.build) ($($state.os.arch))`r`n"
    $md += "- Install date: $($state.os.installDate)`r`n"
    $md += "- Hardware: $($state.hardware.manufacturer) $($state.hardware.model), $($state.hardware.ramGB) GB RAM`r`n"
    $md += "- BIOS: $($state.bios.version) (serial $($state.bios.serial), release $($state.bios.releaseDate))`r`n`r`n"
    $md += "## Security`r`n`r`n"
    $md += "- TPM: present=$($state.tpm.present) ready=$($state.tpm.ready) enabled=$($state.tpm.enabled)`r`n"
    $md += "- BitLocker (C:): volumeStatus=$($state.bitlocker.volumeStatus), protectionStatus=$($state.bitlocker.protectionStatus)`r`n`r`n"
    $md += "## DeviceBootstrap Tasks`r`n`r`n$taskLines`r`n`r`n"
    $md += "## Apps ($($state.apps.Count))`r`n`r`n$appLines`r`n`r`n"
    $md += "## Auto-start Services (top 50 de $($state.services.Count))`r`n`r`n$svcLines`r`n"
    [System.IO.File]::WriteAllText((Join-Path $hostDir 'inventory.md'), $md, [System.Text.Encoding]::UTF8)
} catch {
    Log "WARN state collection: $($_.Exception.Message)"
}

# 3c. meta.json (estavel, sem timestamps)
try {
    $meta = [ordered]@{
        host         = $hostName
        syncSchedule = 'boot+2min, daily 06:00'
        syncTaskName = 'DeviceBootstrap.StateSync'
    }
    $metaJson = $meta | ConvertTo-Json
    [System.IO.File]::WriteAllText((Join-Path $hostDir 'meta.json'), $metaJson, [System.Text.Encoding]::UTF8)
} catch {
    Log "WARN meta.json: $($_.Exception.Message)"
}

# 4. Diff + commit
& git -C $repoDir add -A | Out-Null
& git -C $repoDir diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Log "no diff. skip commit."
    Log "===== sync end (no-op) ====="
    exit 0
}

$ts = Get-Date -Format 'yyyy-MM-dd HH:mm'
$msg = "${hostName}: state drift $ts"
& git -C $repoDir commit -m $msg 2>&1 | ForEach-Object { Log "commit: $_" }
$pushOut = & git -C $repoDir push 2>&1 | Out-String
Log "push: $($pushOut.Trim())"
Log "===== sync end (drift committed) ====="
'@

$syncBody = $syncTemplate.
    Replace('__HOSTNAME__', $Hostname).
    Replace('__REPODIR__',  $repoDir).
    Replace('__LOGFILE__',  $logFile).
    Replace('__GITSSHCMD__', ($gitSshCmd -replace "'", "''"))

[System.IO.File]::WriteAllText($syncScript, $syncBody, [System.Text.Encoding]::ASCII)
Write-Host "    OK" -ForegroundColor DarkGray

# ---- 5. Register Scheduled Task ----
Write-Host "[5/6] Registrando Scheduled Task '$taskName'..." -ForegroundColor Cyan

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$syncScript`""

$triggerBoot = New-ScheduledTaskTrigger -AtStartup
$triggerBoot.Delay = "PT2M"
$triggerDaily = New-ScheduledTaskTrigger -Daily -At 6:00am

$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger @($triggerBoot, $triggerDaily) `
    -Principal $principal `
    -Settings $settings `
    -Description "Drift detection: sync state pro repo $StateRepo (boot+2min, daily 06:00)" `
    -Force | Out-Null

Write-Host "    OK" -ForegroundColor DarkGray

# ---- 6. Validar com 1 run ----
Write-Host "[6/6] Disparando primeiro sync (validacao)..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 8
Get-ScheduledTask -TaskName $taskName |
    Select-Object TaskName, State, @{N='LastRun';E={(Get-ScheduledTaskInfo -TaskName $_.TaskName).LastRunTime}}, @{N='LastResult';E={(Get-ScheduledTaskInfo -TaskName $_.TaskName).LastTaskResult}} |
    Format-List | Out-String | Write-Host

Write-Host ""
Write-Host "install-state-sync-task OK." -ForegroundColor Green
Write-Host ""
Write-Host "Logs locais:" -ForegroundColor DarkGray
Write-Host "  Get-Content $logFile -Tail 30" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Disparar manual:" -ForegroundColor DarkGray
Write-Host "  Start-ScheduledTask -TaskName $taskName" -ForegroundColor DarkGray
