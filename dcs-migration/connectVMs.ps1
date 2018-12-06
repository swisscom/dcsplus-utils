<#
    .SYNOPSIS
	Add network adapter to VM and connect to specified network
    
    .DESCRIPTION
    This Script searches all VMs in a OvDC and adds a primary network adapter if it has no network adapter. The primary network adapter will be
    connected with the specified network if not already connected with a network. IP will be assigned from the network satic IP Pool
	VMs can be further filtered by providing an additional vApp name.
    
    .Parameter ApiEndpoint
	vCloud Director endpoint
	.Parameter User
	API-User
	.Parameter Password
	password for API-User
	.Parameter Organization
	vCloud Director Organization
	.Parameter NetworkName
	a name of network to connect the VM
	.Parameter VdcName
	name of the vDC to get all VMs from
	.Parameter VAppName
	name of a vApp to filter VMs (optional)
	.Parameter ApiVersion
	Version of the vCloud Director API. Default is set to 29.0

	.Example
	# connect all VMs in an OvDc with the specified Network
	.\connectVMs.ps1 -ApiEndpoint my.vcloud.com -User MyApiUser -Password MyPassword -Organization MyOrganization -NetworkName TestNetwork2 -VdcName TestB2
	.Example
	# connect all VM in an OvDc in the specified vApp with the specified Network
	.\connectVMs.ps1 -ApiEndpoint my.vcloud.com -User MyApiUser -Password MyPassword -Organization MyOrganization -NetworkName TestNetwork2 -VdcName TestB2 -VAppName vApp1
#>
# ######################################################################
# ScriptName:   changeVAppPermission.ps1
# Description: 	Swisscom Script to change permission of vApps
# Created by: 	
# ######################################################################
 
[CmdletBinding(
     DefaultParameterSetName='Default',
     ConfirmImpact = 'Low',
     HelpURI = 'https://github.com/swisscom/dcsplus-utils/blob/master/README.md'
)]
 Param(
    #Mandatory Params without default values used for this script
    [Parameter(Mandatory = $true)]
	[String]$ApiEndpoint,
    [Parameter(Mandatory = $true)]
	[String]$User,
    [Parameter(Mandatory = $true)]
	[String]$Password,
    [Parameter(Mandatory = $true)]
	[String]$Organization,
    [Parameter(Mandatory = $true)]
    [String]$NetworkName,
    [Parameter(Mandatory = $true)]
    [String]$VdcName,
    [Parameter(Mandatory = $false)]
    [String]$VAppName,
    [Parameter(Mandatory = $false)]
    [String]$ApiVersion = '29.0'
    )

Begin {
    # #################################### Import ##############################
    #region Import
    $modules = @('vCloudDirectorREST');
    foreach ($module in $modules) {
        if (Get-Module | Where-Object {$_.Name -eq $module}) {
            # Module already imported. Do nothing.
        }
        else {
            Import-Module $module
        }
    }
    Add-Type -AssemblyName System.Web

    #endregion Modules
    # ######################################################################

    # #################################### Variables ##############################
    #region Variables
    # Version
    $ScriptVersion = '1.0'
    $pageSize = '128'
    $dateBegin = [datetime]::Now
    [String] $fn = $MyInvocation.MyCommand.Name
    #endregion Variables
    # ######################################################################

    ### connect to vCloud Director ###
    Invoke-VCDLogin -ApiEndpoint $ApiEndpoint -Org $Organization -User $User -Password $Password -ApiVersion $ApiVersion

    Write-Debug $Global:vCloud.ApiEndpoint
    Write-Debug $Global:vCloud.ApiVersion
    Write-Debug $Global:vCloud.SessionId
    
} # Begin
Process {
    # #################################### Main ##############################
    #region Main
    Write-Host $fn "CALL."
    Try{
        ### get all vms
        $vmList = @{};

        if($VAppName){
            Write-Host "$fn | get all VMs in target vApp $VAppName on migration storage."
            $getVmsURI = "https://$ApiEndPoint/api/query?type=vm&filter=containerName==$VAppName"
        }else{
            [xml]$vdcRecord = Invoke-VCDRestRequest -URI "https://$ApiEndPoint/api/query?type=orgVdc&filter=name==$VdcName" -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
            Write-Host "$fn | get all VMs in target vdc $VdcName on migration Storage"
            #$vdcRecord.QueryResultRecords.OrgVdcRecord.href
            $getVmsURI = "https://$ApiEndPoint/api/query?type=vm&filter=vdc==$($vdcRecord.QueryResultRecords.OrgVdcRecord.href)"
        }
    
        [xml]$vmRecords = Invoke-VCDRestRequest -URI $getVmsURI -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
        $total = $vmRecords.QueryResultRecords.total

        if($total -gt 0){
            $pages = [Math]::Ceiling($total/$pageSize)
            Write-Host "$fn | $total VMs found in vApp $VAppName" 
            Write-Verbose "$fn | $pages Pages to check"
            if($pages -gt 1){
                for($i=1; $i -le $pages; $i++){
                    Write-Verbose "$fn | checking page $i"
                    [xml]$vmRecords = Invoke-VCDRestRequest -URI "$getVmsURI&page=$i" -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
                    foreach($vm in $vmRecords.QueryResultRecords.VmRecord){
                        $vmList.Add($vm.name,$vm.href)
                    }
                }
            }else{
                foreach($vm in $vmRecords.QueryResultRecords.VmRecord){
                    $vmList.Add($vm.name,$vm.href)
                }
            }
   
            ### get org vdc network
            [xml]$NetworkRecords = Invoke-VCDRestRequest -URI "https://$apiEndpoint/api/query?type=orgVdcNetwork&filter=name==$NetworkName" -Method 'Get'
            [xml]$Network = Invoke-VCDRestRequest -URI $NetworkRecords.QueryResultRecords.OrgVdcNetworkRecord.href -Method 'Get'

            ### add a network
            foreach($vm in $vmList.GetEnumerator()){
                Write-Host "$fn | connectingVM: $($vm.Key) to network $NetworkName"
                [xml]$vmDetails = Invoke-VCDRestRequest -URI $vm.Value -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
                $vmDetails.Vm.Link| Where-Object{ $_.rel -eq 'up'} |%{ $vAppUri = $_.href}

                ### add the network to the vApp
                $result = Add-NetworkToVApp -VAppURI $vAppUri -OrgVdcNetwork $Network -FenceMode bridged -Verbose:$VerbosePreference -Debug:$DebugPreference
                $task = ([xml](([string]$result.Content).Trim())).Task.href
                if($task){
                    Write-Verbose $task
                    Wait-VCDTask -TaskUri $task
                }

                ### add a networkadapter to the VM
                $result = Add-NetworkAdapter -VmURI $vm.Value -PrimaryAdapter -Verbose:$VerbosePreference -Debug:$DebugPreference
                $task = ([xml](([string]$result.Content).Trim())).Task.href
                if($task){
                    Write-Verbose $task
                    Wait-VCDTask -TaskUri $task
                }
                
                ### connect VM with Network
                $result = Connect-NetworkAdapter -VmUri $vm.Value -Adapter primary -AutomaticIpAddress POOL -NetworkName $networkName -Verbose:$VerbosePreference -Debug:$DebugPreference
                $task = ([xml](([string]$result.Content).Trim())).Task.href
                if($task){
                    Write-Verbose $task
                    Wait-VCDTask -TaskUri $task
                }
            }
        }else{
            Write-Error "$fn | No VMs found on Migration Storage"
        }

        #endregion Main
        # ######################################################################
    }
    catch {
        Write-Error "$fn | connecting Vms with Network $NetworkName has failed"
        Write-Host "Exception: "$_.Exception.Message
    }
} # Process