#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Legt Hyper-V-Switch, Route und die Firewall-VM "lf9-fw" für das Übungslabor an (Pflichtenheft Kap. 3.1).
.DESCRIPTION
  STATUS: nicht getestet (erste Ausführung = Machbarkeitstest 1.0). In einer PowerShell als Administrator starten.
  Danach Debian in der VM installieren (Netinst-ISO) und im Gast setup.sh ausführen.
.PARAMETER IsoPath
  Pfad zur Debian-Netinst-ISO (amd64).
.PARAMETER WithTestClient
  Legt zusätzlich die Test-Client-VM "lf9-client" (192.168.10.11) an.
#>
param(
    [Parameter(Mandatory = $true)][string]$IsoPath,
    [string]$VmRoot = 'C:\Hyper-V\lf9',
    [int]$MemMaxGB = 8,
    [switch]$WithTestClient
)

$ErrorActionPreference = 'Stop'
$switchName = 'labnet-intern'
$ifAlias    = "vEthernet ($switchName)"

if (-not (Test-Path $IsoPath)) { throw "ISO nicht gefunden: $IsoPath" }
New-Item -ItemType Directory -Force $VmRoot | Out-Null

# 1) Hyper-V-Switch "intern" (virtueller Layer-2-Switch zwischen PC und VMs)
if (-not (Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue)) {
    New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
    Write-Host "Switch $switchName angelegt"
}

# 2) Adresse des PCs im Client-Netz und Route zu den Zonen
if (-not (Get-NetIPAddress -InterfaceAlias $ifAlias -IPAddress 192.168.10.10 -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress 192.168.10.10 -PrefixLength 24 | Out-Null
    Write-Host 'PC-Adresse 192.168.10.10/24 gesetzt'
}
if (-not (Get-NetRoute -DestinationPrefix '10.20.0.0/16' -ErrorAction SilentlyContinue)) {
    New-NetRoute -DestinationPrefix '10.20.0.0/16' -InterfaceAlias $ifAlias -NextHop 192.168.10.1 -PolicyStore PersistentStore | Out-Null
    Write-Host 'Route 10.20.0.0/16 via 192.168.10.1 gesetzt (persistent)'
}
# Windows stuft ein neues Netz als "öffentlich" ein; für Ping und SMB-Tests ggf. auf privat stellen
Set-NetConnectionProfile -InterfaceAlias $ifAlias -NetworkCategory Private -ErrorAction SilentlyContinue

# 3) Firewall-VM (Debian, Generation 2, zwei Adapter)
function New-LabVm {
    param([string]$Name, [int]$Cpu, [long]$StartMem, [long]$MaxMem, [long]$DiskBytes, [string[]]$Switches)
    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { Write-Host "VM $Name existiert bereits"; return }
    $vhd = Join-Path $VmRoot "$Name.vhdx"
    New-VM -Name $Name -Generation 2 -MemoryStartupBytes $StartMem -NewVHDPath $vhd -NewVHDSizeBytes $DiskBytes -SwitchName $Switches[0] -Path $VmRoot | Out-Null
    for ($i = 1; $i -lt $Switches.Count; $i++) { Add-VMNetworkAdapter -VMName $Name -SwitchName $Switches[$i] }
    Set-VMProcessor -VMName $Name -Count $Cpu
    Set-VMMemory -VMName $Name -DynamicMemoryEnabled $true -MinimumBytes 1GB -StartupBytes $StartMem -MaximumBytes $MaxMem
    Add-VMDvdDrive -VMName $Name -Path $IsoPath
    # Debian bootet nur mit der Microsoft-UEFI-CA-Vorlage unter Secure Boot
    Set-VMFirmware -VMName $Name -EnableSecureBoot On -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'
    Set-VMFirmware -VMName $Name -FirstBootDevice (Get-VMDvdDrive -VMName $Name)
    Set-VM -Name $Name -AutomaticStartAction StartIfRunning -AutomaticStopAction ShutDown
    Write-Host "VM $Name angelegt"
}

# Adapter 1: Default Switch (NAT, Internet für Updates = eth0), Adapter 2: labnet-intern (= eth1)
New-LabVm -Name 'lf9-fw' -Cpu 4 -StartMem 4GB -MaxMem ($MemMaxGB * 1GB) -DiskBytes 60GB -Switches @('Default Switch', $switchName)

if ($WithTestClient) {
    New-LabVm -Name 'lf9-client' -Cpu 2 -StartMem 1GB -MaxMem 2GB -DiskBytes 20GB -Switches @($switchName)
}

Write-Host ''
Write-Host 'Nächste Schritte:'
Write-Host '  1. Start-VM lf9-fw ; vmconnect localhost lf9-fw   (Debian installieren, nur SSH-Server und Systemwerkzeuge)'
Write-Host '  2. Im Gast: eth0 = DHCP (Default Switch), eth1 = 192.168.10.1/24 (statisch)'
Write-Host '  3. Im Gast: git clone <Repo> ; cd lf9-lab ; sudo ./setup.sh'
Write-Host '  4. Machbarkeitstest 1.0: vom PC aus ping 192.168.10.1 und TCP-Zugriff auf einen Container'
