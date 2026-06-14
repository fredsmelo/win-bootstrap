# Inventario hardware/OS -- output pra stdout, sem persistir nada no host.
#
# Uso (PowerShell admin via SSH ou local):
#   irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/inventory.ps1 | iex
#
# Coleta: OS, BIOS, CPU, RAM, disco, NIC, TPM, BitLocker.
# Idempotente: so le, nao escreve.

$ErrorActionPreference = 'Stop'

function Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

Section "OS"
Get-CimInstance Win32_OperatingSystem |
    Select-Object Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime, RegisteredUser |
    Format-List | Out-String | Write-Host

Section "Hostname / Domain"
"Hostname: $env:COMPUTERNAME"
"Domain:   $((Get-CimInstance Win32_ComputerSystem).Domain)"

Section "Hardware (ComputerSystem)"
Get-CimInstance Win32_ComputerSystem |
    Select-Object Manufacturer, Model, SystemFamily, TotalPhysicalMemory |
    Format-List | Out-String | Write-Host

Section "BIOS"
Get-CimInstance Win32_BIOS |
    Select-Object Manufacturer, SMBIOSBIOSVersion, SerialNumber, ReleaseDate |
    Format-List | Out-String | Write-Host

Section "CPU"
Get-CimInstance Win32_Processor |
    Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, AddressWidth |
    Format-List | Out-String | Write-Host

Section "RAM"
$totalGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
"Total: ${totalGB} GB"
Get-CimInstance Win32_PhysicalMemory |
    Select-Object @{N='SizeGB';E={[math]::Round($_.Capacity/1GB,1)}}, Speed, Manufacturer, PartNumber |
    Format-Table -AutoSize | Out-String | Write-Host

Section "Disco"
Get-CimInstance Win32_DiskDrive |
    Select-Object Model, @{N='SizeGB';E={[math]::Round($_.Size/1GB,1)}}, InterfaceType, MediaType |
    Format-Table -AutoSize | Out-String | Write-Host

Get-PSDrive -PSProvider FileSystem |
    Where-Object { $_.Used -or $_.Free } |
    Select-Object Name,
        @{N='UsedGB';E={[math]::Round($_.Used/1GB,1)}},
        @{N='FreeGB';E={[math]::Round($_.Free/1GB,1)}} |
    Format-Table -AutoSize | Out-String | Write-Host

Section "Particoes do disco 0"
Get-Partition -DiskNumber 0 -ErrorAction SilentlyContinue |
    Select-Object PartitionNumber, Type, @{N='SizeMB';E={[math]::Round($_.Size/1MB,0)}}, IsHidden, IsActive, DriveLetter |
    Format-Table -AutoSize | Out-String | Write-Host

Section "Rede (interfaces ativas)"
Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } |
    Select-Object Name, InterfaceDescription, MacAddress, LinkSpeed |
    Format-Table -AutoSize | Out-String | Write-Host

Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.InterfaceAlias -notlike '*Loopback*' -and $_.IPAddress -notlike '169.*' } |
    Select-Object InterfaceAlias, IPAddress, PrefixLength |
    Format-Table -AutoSize | Out-String | Write-Host

Section "TPM"
try {
    $tpm = Get-Tpm
    "TpmPresent       : $($tpm.TpmPresent)"
    "TpmReady         : $($tpm.TpmReady)"
    "TpmEnabled       : $($tpm.TpmEnabled)"
    "TpmActivated     : $($tpm.TpmActivated)"
    "ManufacturerVersion: $($tpm.ManufacturerVersion)"
    $tpmInfo = Get-CimInstance -Namespace 'Root\CIMv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue
    if ($tpmInfo) { "SpecVersion      : $($tpmInfo.SpecVersion)" }
} catch {
    Write-Host "TPM: indisponivel ($($_.Exception.Message))" -ForegroundColor Yellow
}

Section "BitLocker (Drive C:)"
try {
    Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop |
        Select-Object MountPoint, EncryptionMethod, VolumeStatus, ProtectionStatus, EncryptionPercentage |
        Format-List | Out-String | Write-Host
} catch {
    Write-Host "BitLocker: nao disponivel ou nao configurado." -ForegroundColor Yellow
}

Section "Ativacao Windows"
cscript //nologo C:\Windows\System32\slmgr.vbs /xpr 2>&1 | Out-String | Write-Host

Section "Resumo"
"Hostname           : $env:COMPUTERNAME"
"User atual         : $env:USERNAME"
"OS                 : $((Get-CimInstance Win32_OperatingSystem).Caption) ($((Get-CimInstance Win32_OperatingSystem).BuildNumber))"
"Hardware           : $((Get-CimInstance Win32_ComputerSystem).Manufacturer) $((Get-CimInstance Win32_ComputerSystem).Model)"
"CPU                : $((Get-CimInstance Win32_Processor).Name)"
"RAM                : ${totalGB} GB"

Write-Host ""
Write-Host "Inventario coletado." -ForegroundColor Green
