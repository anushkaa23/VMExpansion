<#
.SYNOPSIS
    Expands the memory allocation for a specific VM.

.DESCRIPTION
    This script increases a VM's memory to a desired amount.
    It supports both hot-add (for powered-on VMs) and offline reconfiguration depending on VM capabilities.

.PARAMETER VMName
    Name of the virtual machine.

.PARAMETER NewMemoryGB
    New memory value in GB to assign to the VM.

.PARAMETER Credential
    vCenter credentials for authentication.

.EXAMPLE
    .\MemoryExpand.ps1 -VMName "DBServer01" -NewMemoryGB 64 -Credential (Get-Credential)

.NOTES
    - Ensure VM is eligible for memory hot-add.
    - Hot-add support must be enabled in VM settings prior to runtime expansion.

.LINK
    https://docs.vmware.com
#>

param(
    [int]$newMemoryGB,
    [string]$server,
     [switch]$Help
)
if ($Help -or $args -contains '--help') {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit
}
if($newMemoryGB -gt 64 -or $newMemoryGB -lt 1) {
    write-host "`nFailed: Please proceed it Manually.`n`nInvalid memory size: $newMemoryGB GB. Memory must be between 1 and 64 GB."
    exit
}
# Import credentials
$cred = Import-Csv -Path 'C:\temp\cred2\newcreds.csv'
$username = $cred.Username
$password = $cred.Password | ConvertTo-SecureString -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential($username, $password)

# List of vCenters to search
$vcenters = @("atlvcsvm01.amd.com", "atlvcs04.amd.com",  "mkdcvcsvm01.amd.com", "sgpvcsvm01.amd.com")
# Initialize variables
$vm = $null
$connectedVIServer = $null

# Disconnect any existing sessions to avoid conflicts
Disconnect-VIServer -Server * -Force -Confirm:$false

# Search for the VM across vCenters
foreach ($vcenter in $vcenters) {
    try {
        $connection = Connect-VIServer -Server $vcenter -Credential $credentials -ErrorAction Stop
        $get_vm = Get-VM -Server $connection -Name $server -ErrorAction SilentlyContinue
        if ($get_vm) {
            $vm = $get_vm
            $connectedVIServer = $connection
            break
        } else {
            Disconnect-VIServer -Server $connection -Force -Confirm:$false
        }
    } catch {
        Write-Warning "`nFailed: Please proceed it Manually.`nFailed to connect to $vcenter : $_"
    }
}

if (-not $vm) {
    Write-Warning "`nFailed: Please proceed it Manually.`n`nVM '$server' not found in any vCenter. Cannot proceed further...`n"
    exit
}

Write-Host "`nConnected vCenter: $($connectedVIServer.Name)`n" -ForegroundColor Green

# Current Memory of VM
$currentMem = $vm.MemoryGB
Write-Host "Current Memory: $currentMem GB"

# --- Pre-checks ---
$vmName = $vm.Name
Write-Host "Checking VM '$vmName'..."

# Check Power State
if ($vm.PowerState -ne "PoweredOn") {
    Write-Warning "`nFailed: Please proceed it Manually.`nVM is not powered on. Hot-add requires the VM to be running."
    exit
}

# Check Guest OS Version (basic check)
$guestOs = $vm.Guest.OSFullName
Write-Host "Guest OS: $guestOs"
if ($guestOs -notmatch "Windows Server 2008 R2|Linux" -and $guestOs -notmatch "Windows.*20(1[2-9]|2[0-9])") {
    Write-Warning "`nFailed: Please proceed it Manually.`nGuest OS may not support Memory hot-add."
    exit
}

# Check if Memory Hot-Add is enabled
$vmView = Get-View -Id $vm.Id
$memHotAdd = $vmView.Config.MemoryHotAddEnabled
if (-not $memHotAdd) {
    Write-Warning "`nFailed: Please proceed it Manually.`nMemory Hot-Add is not enabled."
    exit
}

# Check host resource availability
$vmHost = $vm.VMHost
$hostView = $vmHost | Get-View

# Check Host Power State
if ($vmHost.PowerState -ne "PoweredOn") {
    Write-Warning "`nFailed: Please proceed it Manually.`nHost is not powered on. Hot-add cannot proceed."
    exit
}

# Get host memory capacity and usage in GB
$hostMemTotal = $vmHost.ExtensionData.Summary.Hardware.MemorySize / 1GB
$hostMemUsed = $vmHost.ExtensionData.Summary.QuickStats.OverallMemoryUsage / 1024
$hostMemFree = $hostMemTotal - $hostMemUsed

Write-Host "Total host memory: $([math]::Round($hostMemTotal,2)) GB, Used: $([math]::Round($hostMemUsed,2)) GB, Free: $([math]::Round($hostMemFree,2)) GB"

# Safety check: host free memory
if ($hostMemFree -lt ($newMemoryGB - $currentMem)) {
    Write-Warning "`nFailed: Please proceed it Manually.`nNot enough free memory on the host to allocate additional $($newMemoryGB - $currentMem) GB. Host has only $([math]::Round($hostMemFree,2)) GB free."
    exit
}

# Check for Host Resource Overcommitment
$hostMemOvercommit = ($hostMemUsed / $hostMemTotal) * 100
if ($hostMemOvercommit -gt 85) {
    Write-Warning "`nFailed: Please proceed it Manually.`nHost memory usage is over 85%. Host is heavily overcommitted. Hot-add may fail."
    exit
}

# Check for small memory footprint VMs
if ($vm.MemoryGB -le 3) {
    Write-Warning "`nFailed: Please proceed it Manually.`nThe VM has only $($vm.MemoryGB) GB of memory. Memory hot-add may not work correctly on VMs with ≤ 3 GB due to VMware limitations."
    exit
}

# --- Perform Hot-Add ---
Write-Host "`nAll checks passed. Proceeding with hot-add..."

# Update Memory
if ($currentMem -lt $newMemoryGB) {
    Set-VM -VM $vm -MemoryGB $newMemoryGB -Confirm:$false
    Write-Host "Updated Memory to $newMemoryGB GB"
} else {
    Write-Host "`nFailed: Please proceed it Manually.`nMemory already at or above $newMemoryGB GB. Skipping."
    exit
}

Write-Host "`nHot-add completed for VM: $vmName"

# Refresh VM object to get updated properties
$vm = Get-VM -Server $connectedVIServer -Name $server -ErrorAction SilentlyContinue
Write-Host "VM New Memory: $($vm.MemoryGB) GB"

# Disconnect from the connected vCenter
Disconnect-VIServer -Server $connectedVIServer -Force -Confirm:$false

