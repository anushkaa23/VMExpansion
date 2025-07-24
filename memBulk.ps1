<#
.SYNOPSIS
    Performs memory upgrades on a list of VMs in bulk from a CSV input file.

.DESCRIPTION
    This script reads VM names and new memory values from a CSV file and performs memory updates across vCenters.
    It validates current memory settings, checks for hot-add capability, and adjusts memory accordingly.

.PARAMETER InputCSV
    Path to a CSV file with VM names, vCenter, and desired memory values in GB.

.PARAMETER Credential
    vCenter credentials for authentication.

.EXAMPLE
    .\memBulk.ps1 -csvPath  "C:\MemoryUpdateList.csv" 

.NOTES
    - The CSV should have columns: VMName, vCenter, NewMemoryGB.
    - Supports both online (hot-add) and offline memory reconfiguration.

.LINK
    https://developer.vmware.com/docs
#>

param(
    [string]$csvPath,
     [switch]$Help
)
if ($Help -or $args -contains '--help') {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit
}
# Load credentials
$cred = Import-Csv -Path 'C:\temp\cred2\newcreds.csv'
$username = $cred.Username
$password = $cred.Password | ConvertTo-SecureString -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential($username, $password)

# vCenter list
$vcenters = @("atlvcs04.amd.com" , "atlvcsvm01.amd.com", "mkdcvcsvm01.amd.com", "sgpvcsvm01.amd.com")

# Load input CSV with columns: server, newMemoryGB
if (-not (Test-Path $csvPath)) {
    Write-Error "`nFailed: Please proceed it Manually.`nCSV file '$csvPath' not found. Exiting..."
    exit
}

$vmList = Import-Csv -Path $csvPath

foreach ($entry in $vmList) {
    $server = $entry.server
    $newMemoryGB = [int]$entry.newMemoryGB
    if($newMemoryGB -gt 64 -or $newMemoryGB -lt 1) {
        Write-Host "`nFailed: Please proceed it Manually.`nInvalid memory size: $newMemoryGB GB for VM '$server'. Memory must be between 1 and 64 GB." -ForegroundColor Red
        continue
    }

    Write-Host "`nProcessing VM: $server | Target Memory: $newMemoryGB GB" -ForegroundColor Cyan

    $connectedVC = $null
    $targetVM = $null

    foreach ($vcenter in $vcenters) {
        try {
            $connection = Connect-VIServer $vcenter -Credential $credentials -Force -ErrorAction Stop
            $get_vm = Get-VM -Name $server -Server $connection -ErrorAction SilentlyContinue

            if ($get_vm) {
                $connectedVC = $connection
                $targetVM = $get_vm
                break
            } else {
                Disconnect-VIServer -Server $connection -Confirm:$false
            }
        } catch {
            Write-Warning "`nFailed: Please proceed it Manually.`nFailed to connect to $vcenter : $_"
        }
    }

    if (-not $connectedVC -or -not $targetVM) {
        Write-Warning "`nFailed: Please proceed it Manually.`nVM '$server' not found in any vCenter. Skipping..."
        continue
    }

    Write-Host "`nConnected vCenter is : $connectedVC" -ForegroundColor Green
    Write-Host "Found VM: $($targetVM.Name)"

    $vm = $targetVM
    $currentMem = $vm.MemoryGB
    Write-Host "Current Memory: $currentMem GB"
    $vmName = $vm.Name

    # Power state check
    if ($vm.PowerState -ne "PoweredOn") {
        Write-Warning "``nFailed: Please proceed it Manually.`nVM '$vmName' is not powered on. Skipping..."
        Disconnect-VIServer -Server $connectedVC -Confirm:$false
        continue
    }

    # Guest OS check
    $guestOs = $vm.Guest.OSFullName
    Write-Host "Guest OS: $guestOs"
    if ($guestOs -notmatch "Windows Server 2008 R2|Linux" -and $guestOs -notmatch "Windows.*20(1[2-9]|2[0-9])") {
        Write-Warning "`nFailed: Please proceed it Manually.`nGuest OS may not support memory hot-add. Proceed with caution."
        continue
    }

    # Memory hot-add check
    $vmView = Get-View -Id $vm.Id
    $memHotAdd = $vmView.Config.MemoryHotAddEnabled
    if (-not $memHotAdd) {
        Write-Warning "`nFailed: Please proceed it Manually.`nMemory Hot-Add is not enabled on VM '$vmName'. Skipping..."
        Disconnect-VIServer -Server $connectedVC -Confirm:$false
        continue
    }

    # Host info and memory checks
    $vmHost = $vm.VMHost
    if ($vmHost.PowerState -ne "PoweredOn") {
        Write-Warning "`nFailed: Please proceed it Manually.`nHost of VM '$vmName' is not powered on. Skipping..."
        Disconnect-VIServer -Server $connectedVC -Confirm:$false
        continue
    }

    $hostMemTotal = $vmHost.ExtensionData.Summary.Hardware.MemorySize / 1GB
    $hostMemUsed = $vmHost.ExtensionData.Summary.QuickStats.OverallMemoryUsage / 1024
    $hostMemFree = $hostMemTotal - $hostMemUsed

    Write-Host "Host Total Memory = $hostMemTotal GB | Used = $hostMemUsed GB | Free = $hostMemFree GB"

    if ($hostMemFree -lt ($newMemoryGB - $currentMem)) {
        Write-Warning "`nFailed: Please proceed it Manually.`nNot enough host memory to update VM '$vmName' to $newMemoryGB GB. Skipping..."
        Disconnect-VIServer -Server $connectedVC -Confirm:$false
        continue
    }

    $hostMemOvercommit = ($hostMemUsed / $hostMemTotal) * 100
    if ($hostMemOvercommit -gt 85) {
        Write-Warning "`nFailed: Please proceed it Manually.`nHost is overcommitted (>85%). Hot-add may fail for VM '$vmName'."
        continue
    }

    if ($currentMem -le 3) {
        Write-warning "`nFailed: Please proceed it Manually.`nVM '$vmName' has only $currentMem GB. Hot-add may not work well. Skipping..."
        Disconnect-VIServer -Server $connectedVC -Confirm:$false
        continue
    }

    # Hot-add
    if ($currentMem -lt $newMemoryGB) {
        Set-VM -VM $vm -MemoryGB $newMemoryGB -Confirm:$false
        Write-Host "Successfully updated '$vmName' to $newMemoryGB GB" -ForegroundColor Green
        continue
    } else {
        Write-host "`nFailed: Please proceed it Manually.`nMemory for VM '$vmName' is already >= $newMemoryGB GB. Skipping update." -ForegroundColor Yellow
        continue
    }

    # Disconnect from vCenter
    Disconnect-VIServer -Server $connectedVC -Force -Confirm:$false
}
