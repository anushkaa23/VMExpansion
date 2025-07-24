$serversFile = "C:\temp\severForTestingNcpa\servers.txt"
$service1= "ncpaListener"
$service2= "ncpaPassive"
$ncpaInstallerPath = "C:\Temp\NCPA_Files\ncpa-2.4.1.exe"
$ncpaInstallerURL = "https://assets.nagios.com/downloads/ncpa/ncpa-2.4.1.exe"
$pluginSource = "C:\Program Files (x86)\Nagios\NCPA\plugins"
$configSource = "C:\Program Files (x86)\Nagios\NCPA\etc\ncpa.cfg.d"
 
# Read test server list
if(!(Test-path $serversFile)){
    Write-Host "Server list file not found: $serversFile"
    exit 1
}else{
    $servers = Get-Content $serversFile
}

Function Check-NCPA{
    param($server){
        try{
            $service1=Get-Service -name $service1 -ComputerName $server -ErrorAction SilentlyContinue
            $service2 = Get-Service -name $service2 -ComputerName $server -ErrorAction SilentlyContinue
            if($service1 -or $service2){
                Write-Host "NCPA is already installed on $server."
                foreach ($service in ($service1,$service2)){
                    if($service.status -ne "running"){
                        Restart-Service -Name $service -ComputerName $server

                        #recheck whether the services started running or not 
                        if($service.status -eq "running"){
                            write-host "$service started successfully on $server."
                        }
                        else{
                            write-host "$service failed to start on $server."
                            return $false
                        }
                    }
                    
                }
                return $true

            }
        }
        catch {
            Write-Host "NCPA service not found on $server."
        }

        return (Test-Path "\\$server\C$\Program Files (x86)\Nagios\NCPA")

    }
}

function  Install-NCPA{
    param (
        $server
    )
    Write-Host "Installing NCPA on $server..."
 
    #check whether installer is available or not
    if(!(Test-Path $ncpaInstallerPath)){
        Write-Host "Downloading NCPA installer..."
        curl -o $ncpaInstallerPath $ncpaInstallerURL
    }
 
    $remoteInstallerPath= "\\$server\C$\temp\$ncpaInstaller"
    Copy-Item -Path $ncpaInstallerPath -Destination $remoteInstallerPath -Force
    Invoke-Command -ComputerName $server -ScriptBlock{
        Start-Process -FilePath "C:\temp\ncpa-2.4.1.exe" -ArgumentList "/S /TOKEN='pe_eng_sysmon'"
 
    }
 
    if(Check-NCPA -server $server){
        Write-Host "NCPA installed successfully on $server."
    }else{
        Write-Host "NCPA installation failed on $server."
        exit 1
    }  
}
 
 
#function to copy plugins
function Copy-Plugins{
    param ($server)
    $pluginDestination = "\\$server\C$\Program Files (x86)\Nagios\NCPA\plugins"
 
    if(!(Test-Path $pluginDestination)){
        Write-Host "Creating plugins directory on the $server..."
        Invoke-Command -ComputerName $server -ScriptBlock{
            New-Item -ItemType Directory -Path "C:\Program Files (x86)\Nagios\NCPA\plugins" -Force | Out-Null
        }
    }
    $existingPlugins = Get-ChildItem -path $pluginDestination
    if($existingPlugins.Count -eq 0){
        Write-Host "Copying plugins to $server..."
        Copy-Item -Path "$pluginSource\*" -Destination $pluginDestination -Recurse -Force
    }
    else{
        write-host "Plugins already exist on $server."
    }
}
 
#function to check config files
function Copy-ConfigFiles{
    param(
        $server
    )
    $configDestination = "\\$server\C$\Program Files (x86)\Nagios\NCPA\etc\ncpa.cfg.d"
    if(!(Test-Path $configDestination)){
        Write-Host "Creating config directory on $server..."
        Invoke-Command -ComputerName $server -ScriptBlock{
            New-Item -ItemType Directory -Path "C:\Program Files (x86)\Nagios\NCPA\etc\ncpa.cfg.d" -Force | Out-Null
        }
    }
    write-host "copy config files to $server..."
    Copy-Item -Path "$configSource\*" -Destination $configDestination -Recurse -Force
}
 

#registration
function Register-server{
    param ($server)
    write-host "Registering $server..."  
        if($server -match '^xsj'){
            # for sbka
            #host list
            $XSJ_host_data = curl.exe --silent -XGET --insecure "https://sbka.xilinx.com/nagiosxi/api/v1/config/host?apikey=api&pretty=1" | ConvertFrom-Json
            $XSJ_hosts=$XSJ_host_data.host_name
            #$XSJ_hosts
            #hostgroup_name list
            $XSJ_host_groups_data= curl.exe --silent -XGET --insecure "https://sbka.xilinx.com/nagiosxi/api/v1/config/hostgroup?apikey=api&pretty=1" |ConvertFrom-Json
            $XSJ_host_groups=$XSJ_host_groups_data.hostgroup_name
            #$XSJ_host_groups
            #contact_groups
            $XSJ_contact_groups_data = curl.exe --silent -XGET --insecure "https://sbka.xilinx.com/nagiosxi/api/v1/config/contactgroup?apikey=api&pretty=1" | ConvertFrom-json
            $XSJ_contact_groups=$XSJ_contact_groups_data.contactgroup_name

            if($server -in $XSJ_hosts){
                Write-Host "$server is already registered in sbka."
                return
            }
            #host not there
            else{
                #check host group
                if($XSJ_host_groups -notcontains "c4-windows"){
                    Write-Host "c4-windows host group is not there in sbka. Creating the host group."
                    curl.exe --silent -XPOST "https://sbka.xilinx.com/nagiosxi/api/v1/config/hostgroup?apikey=api&pretty=1" -d "hostgroup_name=c4-windows&alias=c4-windows&members=$server" -k
                }else{
                    Write-Host "c4-windows host group is already there in sbka."
                }
                #check for contact groups
                if($XSJ_contact_groups -notcontains "c4-windows"){
                    Write-Host "c4-windows contact group is not there in sbka. Creating the contact group."
                    curl.exe --silent -XPOST "https://sbka.xilinx.com/nagiosxi/api/v1/config/contactgroup?apikey=api&pretty=1" -d "contactgroup_name=c4-windows&alias=c4-windows&members=$server" -k
                }else{
                    Write-Host "c4-windows contact group is already there in sbka."
                }
                #register the host
                curl.exe --silent -XPOST "https://sbka/nagiosxi/api/v1/config/host?apikey=api&pretty=1" -d "host_name=$server&address=$server&hostgroups=c4-windows&check_command=check_ping\!3000,80%\!5000,100%&max_check_attempts=2&check_period=24x7&check_interval=6&retry_interval=2&contact_groups=admins,c4-windows&notification_interval=0&notification_period=24x7&notification_options=d,u," -k
            }
        }
        elseif($server -match "^hyd"){
            # for
            #host list
            $XHD_host_data= curl.exe --silent -XGET --insecure "https://xhd-dvapngo01.xilinx.com/nagiosxi/api/v1/config/host?apikey=api&pretty=1" | ConvertFrom-Json
            $XHD_hosts=$XHD_host_data.host_name
            #host group
            $XHD_host_group_data= curl.exe --silent -XGET --insecure "https://xhd-dvapngo01.xilinx.com/nagiosxi/api/v1/config/hostgroup?apikey=api&pretty=1" | ConvertFrom-Json
            $XHD_host_groups=$XHD_host_group_data.hostgroup_name
            #contact_groups
            $XHD_contact_groups_data =  curl.exe --silent -XGET --insecure "https://xhd-dvapngo01.xilinx.com/nagiosxi/api/v1/config/contactgroup?apikey=api&pretty=1" | ConvertFrom-Json
            $XHD_contact_groups=$XHD_contact_groups_data.contactgroup_name

            if($server -in $XHD_hosts){
                #check whether it is registered or not by using --silent -XGET
                Write-Host "$server is already registered in."
                return
            }
            #host not there
            else{
                #check host group
                if($XHD_host_groups -notcontains "c4-windows"){
                    Write-Host "c4-windows host group is not there in. Creating the host group."
                    curl.exe -XPOST --silent "https://site.com/nagiosxi/api/v1/config/hostgroup?apikey=api&pretty=1" -d "hostgroup_name=c4-windows&alias=c4-windows&members=$server" -k
                }else{
                    Write-Host "c4-windows host group is already there in."
                }
                #check for contact groups
                if($XHD_contact_groups -notcontains "c4-windows"){
                    Write-Host "c4-windows contact group is not there in. Creating the contact group."
                    curl.exe -XPOST --silent "https://site/nagiosxi/api/v1/config/contactgroup?apikey=apikey&pretty=1" -d "contactgroup_name=c4-windows&alias=c4-windows&members=$server" -k
                }else{
                    Write-Host "c4-windows contact group is already there in."
                }
                #register the host
                curl.exe -XPOST --silent "https://site.com/nagiosxi/api/v1/config/host?apikey=api&pretty=1" -d "host_name=$server&address=$server&hostgroups=c4-windows&check_command=check_ping\!3000,80%\!5000,100%&max_check_attempts=2&check_period=24x7&check_interval=6&retry_interval=2&contact_groups=admins,c4-windows&notification_interval=0&notification_period=24x7&notification_options=d,u," -k
            }
        }
        else{
            Write-Host " not hyd or xsj"
        }
}
#main script execution
foreach($server in $servers){
    Write-Host "checking for $server"
    if(!(Check-NCPA -server $server)){ 
        Install-NCPA -server $server
    }
    
    copy-Plugins -server $server
    Copy-ConfigFiles -server $server
    Register-Server -server $server
    Write-Host "Completed processing for $server."
}
