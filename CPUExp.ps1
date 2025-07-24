<#
.SYNOPSIS
    Expands vCPU count for a single VM.

.DESCRIPTION
    This script increases the number of vCPUs for a VM.
    It checks if hot-add is enabled and applies changes without VM downtime if allowed.

.PARAMETER hostName
    Name of the virtual machine.

.PARAMETER newCPUCount
    The new total number of vCPUs to assign.

.EXAMPLE
    .\CpuExpand.ps1 -hostName "AppVM01" -newCPUCount 6

.NOTES
    Ensure VM's guest OS supports hot-add and CPU limits are not exceeded.

.LINK
    https://kb.vmware.com
#>


param(
    [int]$newCPUCount ,
    $hostName,
    [switch]$Help
)
if ($Help -or $args -contains '--help') {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit
}
if ($newCPUCount -gt 32 -or $newCPUCount -lt 1) {
    Write-Host "`nFailed: Please proceed it Manually.`nInvalid CPU count: $newCPUCount. CPU must be between 1 and 32." -ForegroundColor Red 
    exit
}
function Get-Credentials {
    $cred = Import-Csv -Path 'C:\temp\cred2\newcreds.csv'
    $username = $cred.Username
    $password = $cred.Password | ConvertTo-SecureString -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($username, $password)
}
$credentials = Get-Credentials
$vcenters = @("atlvcs04.amd.com" , "atlvcsvm01.amd.com", "mkdcvcsvm01.amd.com", "sgpvcsvm01.amd.com")

$vc = $null
$vm = $null
foreach ($vcenter in $vcenters) {
    try {
        $connection = Connect-VIServer $vcenter -Credential $credentials -Force -ErrorAction Stop

        # Use -Server to ensure Get-VM runs in correct scope
        $get_vm = Get-VM -Name $hostname -Server $connection -ErrorAction SilentlyContinue

        if ($get_vm) {
            $vc = $vcenter
            $vm = $get_vm
            break
        } else {
            # Disconnect explicitly
            Disconnect-VIServer -Server $connection -Confirm:$false
        }
    } catch {
        Write-Warning "Failed: Please proceed it Manually.`nFailed to connect to $vcenter : $_ `n"
    }
}

if ($vc) {
    Write-Host "`nConnected vCenter is : $vc`n" -ForegroundColor Green
    Write-Host "Found VM: $($vm.Name)"
} else {
    Write-Warning "Failed: Please proceed it Manually.`nVM $hostname not found in any vCenter. Cannot proceed further. `n"
    exit
}

Write-Host "`nConnected vCenter is : $vc`n" -ForegroundColor Green

$currentCpu = $vm.NumCpu
$vmName = $vm.Name
Write-Host "Current vCPUs: $currentCpu"
Write-Host "Checking VM '$vmName'..."

# --- Pre-checks ---
if ($vm.PowerState -ne "PoweredOn") {
    Write-Warning "Failed: Please proceed it Manually.`nVM is not powered on. "
    return
}

$guestOs = $vm.Guest.OSFullName
Write-Host "Guest OS: $guestOs"
if ($guestOs -notmatch "Windows Server 2008 R2|Linux" -and $guestOs -notmatch "Windows.*20(1[2-9]|2[0-9])") {
    Write-Warning "Failed: Please Proceed manually.`nGuest OS may not support CPU/Memory hot-add.`n"
}

$vmView = Get-View -Id $vm.Id
if (-not $vmView.Config.CpuHotAddEnabled) {
    Write-Warning "Failed: Please Proceed manually.`nCPU Hot-Add is not enabled."
    exit
}

$vmHost = $vm.VMHost
$hostView = $vmHost | Get-View

if ($vmHost.PowerState -ne "PoweredOn") {
    Write-Warning "Failed: Please Proceed manually.`nHost is not powered on. Hot-add cannot proceed."
    return
}

$cpuMhzPerCore = $hostView.Summary.Hardware.CpuMhz
$hostCpuTotal = $hostView.Summary.Hardware.CpuMhz * $hostView.Summary.Hardware.NumCpuCores
$hostCpuUsed = $hostView.Summary.QuickStats.OverallCpuUsage
$hostCpuFree = $hostCpuTotal - $hostCpuUsed
$neededCpuMHz = ($newCpuCount - $currentCpu) * $cpuMhzPerCore

if ($hostCpuFree -lt $neededCpuMHz) {
    Write-Warning "Failed: Please Proceed manually.`nNot enough free CPU capacity on host to allocate $newCPUCount vCPUs (~$neededCpuMHz MHz). Host has only $hostCpuFree MHz free."
    return
}

$hostCpuOvercommit = ($hostCpuUsed / $hostCpuTotal) * 100
if ($hostCpuOvercommit -gt 85) {
    Write-Warning "Failed: Please Proceed manually.`nHost CPU usage is over 85%. Host is heavily overcommitted. Hot-add may fail."
}

if ($newCPUCount -gt 32) {
    Write-Warning "Failed: Please Proceed manually.`nIncreasing vCPU count above 32 disables CPU hot-add permanently for this VM."
    exit
}

# --- Perform Hot-Add ---
Write-Host "`nAll checks passed. Proceeding with hot-add..."
if ($currentCpu -lt $newCPUCount) {
        try {
            $coresPerSocket = Get-WmiObject -Class Win32_Processor -ComputerName $hostname |
                Measure-Object -Property NumberOfCores -Maximum |
                Select-Object -ExpandProperty Maximum
            if (-not $coresPerSocket -or $coresPerSocket -lt 2) {
                $coresPerSocket = 2
            }
            $cpuToAdd = [math]::Ceiling(($newCPUCount - $currentCpu) / $coresPerSocket) * $coresPerSocket
            $finalCPUCount = $currentCpu + $cpuToAdd
            if ($finalCPUCount -ne $newCPUCount) {
                Write-Host "`nFailed to expand to exact target vCPU count ($newCPUCount) for VM '$vmName'." -ForegroundColor Yellow
                Write-Host "Reason: Cores per socket is $coresPerSocket. CPU count must align with this value." -ForegroundColor Yellow
                Write-Host "Expanding to nearest aligned value: $finalCPUCount vCPUs instead." -ForegroundColor Yellow
            } else {
                Write-Host "`nTargeting exact vCPU count: $newCPUCount (aligned with Cores/Socket: $coresPerSocket)"
            }
            Set-VM -VM $vm -NumCpu $finalCPUCount -CoresPerSocket $coresPerSocket -Confirm:$false
        } catch {
            Write-Warning "CPU hot-add failed for VM '$vmName': $_"
            continue
        }
}
else {
    Write-Host "Failed: Please Proceed manually.`nCPU already at or above $newCPUCount. Skipping."
    exit
}

# Allow vCenter to sync changes
Start-Sleep -Seconds 5

# Refresh VM object to get updated config
$get_vm = Get-VM -Name $hostName 
$vm=$get_vm

Write-Host "`nHot-add completed for VM: $vmName"
Write-Host "VM New CPU Count: $($vm.NumCpu)"

Disconnect-VIServer -Server $vc -Confirm:$false


