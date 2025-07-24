<#
.SYNOPSIS
    Performs a bulk update of vCPU configurations for multiple VMs across one or more vCenters.

.DESCRIPTION
    This script reads a list of VMs along with their desired CPU configuration and updates each VM accordingly.
    It checks for compatibility, hot-add capabilities, power state, and current CPU settings before applying changes.

.PARAMETER InputCSV
    Path to a CSV file containing VM names, target vCenter, and desired vCPU counts.

.PARAMETER Credential
    vCenter credentials for authentication.

.EXAMPLE
    .\CpuBulkUpdate.ps1 -csvPath "C:\VMList.csv" 

.NOTES
    - Supports powered-on VMs.
    - Make sure the user has permissions to modify VM hardware.

.LINK
    https://developer.vmware.com/apis
#>

param(
    [string]$csvPath,
     [switch]$Help
)
if ($Help -or $args -contains '--help') {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit
}

function Get-Credentials {
    $cred = Import-Csv -Path 'C:\temp\cred2\newcreds.csv'
    $username = $cred.Username
    $password = $cred.Password | ConvertTo-SecureString -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($username, $password)
}

if (-not (Test-Path $csvPath)) {
    Write-Error "`nFailed: Please proceed it Manually.`nCSV file '$csvPath' not found. Exiting..."
    exit
}

$credentials = Get-Credentials
$vcenters = @("atlvcs04.amd.com", "atlvcsvm01.amd.com", "mkdcvcsvm01.amd.com", "sgpvcsvm01.amd.com")
$vmList = Import-Csv -Path $csvPath

foreach ($entry in $vmList) {
    $server = $entry.server
    $newCPUCount = [int]$entry.newCPUCount
    if ($newCPUCount -gt 32 -or $newCPUCount -lt 1) {
        Write-Host "`nFailed : Please proceed it Manually.`nInvalid CPU count: $newCPUCount for VM '$server'. CPU must be between 1 and 32." -ForegroundColor Red
        continue
    }
    Write-Host "`nProcessing VM: $server | Target CPU: $newCPUCount" -ForegroundColor Cyan
    $vc = $null
    $vm = $null

    foreach ($vcenter in $vcenters) {
        try {
            $connection = Connect-VIServer $vcenter -Credential $credentials -Force -ErrorAction Stop
            $get_vm = Get-VM -Name $server -Server $connection -ErrorAction SilentlyContinue
            if ($get_vm) {
                $vc = $vcenter
                $vm = $get_vm
                break
            } else {
                Disconnect-VIServer -Server $connection -Confirm:$false
            }
        } catch {
            Write-Warning "`nFailed: Please proceed it Manually.`nFailed to connect to $vcenter : $_"
        }
    }

    if (-not $vc -or -not $vm) {
        Write-Warning "`nFailed: Please proceed it Manually.`nVM '$server' not found in any vCenter. Skipping..."
        continue
    }

    Write-Host "`nConnected vCenter is : $vc" -ForegroundColor Green
    Write-Host "Found VM: $($vm.Name)"

    $currentCpu = $vm.NumCpu
    $vmName = $vm.Name
    Write-Host "Current vCPUs: $currentCpu"
    Write-Host "Checking VM '$vmName'..."

    if ($vm.PowerState -ne "PoweredOn") {
        Write-Warning "`nFailed: Please proceed it Manually.`nVM is not powered on.`n"
        continue
    }

    $guestOs = $vm.Guest.OSFullName
    Write-Host "Guest OS: $guestOs"
    if ($guestOs -notmatch "Windows Server 2008 R2|Linux" -and $guestOs -notmatch "Windows.*20(1[2-9]|2[0-9])") {
        Write-Warning "F`nFailed: Please proceed it Manually.`nUnsupported Guest OS: $guestOs"
        continue
    }

    $vmView = Get-View -Id $vm.Id
    $CPUHotAdd = $vmView.Config.CPUHotAddEnabled
    if (-not $CPUHotAdd) {
        Write-Warning "`nFailed: Please proceed it Manually.`nCPU Hot-Add is not enabled on VM '$vmName'. Skipping..."
        Disconnect-VIServer -Server $vc -Confirm:$false
        continue
    }

    $vmHost = $vm.VMHost
    $hostView = $vmHost | Get-View
    if ($vmHost.PowerState -ne "PoweredOn") {
        Write-Warning "`nFailed: Please proceed it Manually.`nHost of VM '$vmName' is not powered on. Skipping..."
        Disconnect-VIServer -Server $vc -Confirm:$false
        continue
    }

    $cpuMhzPerCore = $hostView.Summary.Hardware.CpuMhz
    $hostCpuTotal = $hostView.Summary.Hardware.CpuMhz * $hostView.Summary.Hardware.NumCpuCores
    $hostCpuUsed = $hostView.Summary.QuickStats.OverallCpuUsage
    $hostCpuFree = $hostCpuTotal - $hostCpuUsed
    $neededCpuMHz = ($newCPUCount - $currentCpu) * $cpuMhzPerCore

    if ($hostCpuFree -lt $neededCpuMHz) {
        Write-Warning "`nFailed: Please proceed it Manually.`nNot enough free CPU capacity on host to allocate $newCPUCount vCPUs (~$neededCpuMHz MHz). Host has only $hostCpuFree MHz free. "
        continue
    }

    $hostCpuOvercommit = ($hostCpuUsed / $hostCpuTotal) * 100
    if ($hostCpuOvercommit -gt 85) {
        Write-Warning "`nFailed: Please proceed it Manually.`nHost CPU usage is over 85%. Host is heavily overcommitted. Hot-add may fail."
        continue
    }

    if ($newCPUCount -gt 128) {
        Write-Warning "`nFailed: Please proceed it Manually.`nNew vCPU count exceeds 128."
        continue
    }

    # --- Perform Hot-Add with cores per socket logic ---
    if ($currentCpu -lt $newCPUCount) {
        try {
            $coresPerSocket = Get-WmiObject -Class Win32_Processor -ComputerName $server |
                Measure-Object -Property NumberOfCores -Maximum |
                Select-Object -ExpandProperty Maximum

            if (-not $coresPerSocket -or $coresPerSocket -lt 1) {
                $coresPerSocket = 1
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
    } else {
        Write-Host "`nFailed: Please proceed it Manually.`nCPU already at or above $newCPUCount. Skipping."
        continue
    }

    Start-Sleep -Seconds 5

    $vm = Get-VM -Name $server
    Write-Host "`nHot-add completed for VM: $vmName"
    Write-Host "VM New CPU Count: $($vm.NumCpu)"

    Disconnect-VIServer -Server $vc -Confirm:$false
}
