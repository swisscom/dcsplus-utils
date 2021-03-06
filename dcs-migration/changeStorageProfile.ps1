 <#
    .SYNOPSIS
	Move VMs to a target storage profile
    
    .DESCRIPTION
    This Script searches all VMs in a OvDC and moves them to the specified storage profile.
	VMs can be further filtered by providing an additional vApp name.
    
    .Parameter ApiEndpoint
	vCloud Director endpoint
	.Parameter User
	API-User
	.Parameter Password
	password for API-User
	.Parameter Organization
	vCloud Director Organization
	.Parameter StorageType
	storage type to which  VMs should be migrated
	.Parameter VdcName
	name of the vDC
	.Parameter VAppName
	name of a vApp to filter VMs
	.Parameter ApiVersion
	Version of the vCloud Director API. Default is set to 29.0

	.Example
	# change storage profile of all VMs in a specific OvDC
	.\changeStorageProfile.ps1 -ApiEndpoint my.vcloud.com -User MyApiUser -Password MyPassword -Organization MyOrganization -StorageType 'Fast Storage' -VdcName MyVdc
	.Example
	# change storage profile of all VMs which are in a vApp starting with MyVApp
	.\changeStorageProfile.ps1 -ApiEndpoint my.vcloud.com -User MyApiUser -Password MyPassword -Organization MyOrganization -StorageType 'Fast Storage' -VdcName MyVdc -VAppName 'MyVApp*'
	.Example
	# change storage profile of all VMs inthe vApp with the name MyVApp in DCS classic
	.\changeStorageProfile.ps1 -ApiEndpoint my.oldvcloud.com -User MyApiUser -Password MyPassword -Organization MyOrganization -StorageType 'Migration Storage' -VdcName MyVdc -VAppName 'MyVApp' -ApiVersion 27.0
#>
# ######################################################################
# ScriptName:   changeVmStorageProfile.ps1
# Description: 	Swisscom Script to move VMs to a target storage profile
# Created by: 	
# ######################################################################
 
 [CmdletBinding(
     ConfirmImpact = 'Low',
     HelpURI = 'https://github.com/swisscom/dcsplus-utils/blob/master/dcs-migration/README.md'
)]
 Param(
    #Mandatory Params without default values used for this script
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
	[String]$ApiEndpoint,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
	[String]$User,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
	[String]$Password,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
	[String]$Organization,
    [Parameter(Mandatory = $true)]
    [ValidateSet('Fast Storage','Fast Storage with Backup',
    'Ultra Fast Storage','Ultra Fast Storage with Backup','Migration Storage')]
    [String]$StorageType,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String]$VdcName,
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [String]$VAppName,
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
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
    Write-Host "$fn | CALL."
    try {
        Write-Host "$fn | getting storage profile of target vdc $VdcName"
        ### get target vdc
        Write-Verbose "$fn | get target vdc"
        $orgVdcUri = "https://$ApiEndPoint/api/query?type=orgVdc&filter=name==$VdcName"
        [xml]$vdcRecords = Invoke-VCDRestRequest -URI $orgVdcUri -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
        $vdcUri = $vdcRecords.QueryResultRecords.OrgVdcRecord.href

        ### get storage profiles of target vdc
        Write-Verbose " $fn | get vdc storage profiles"
        [xml]$storageprofiles = Invoke-VCDRestRequest -URI $vdcUri -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
        Write-Debug "$fn | $($storageprofiles.InnerXml)"

        ### get target storage profile
        if($StorageType -eq 'Fast Storage'){$storageProfileName = '^\bFast Storage [AB]{1,2}(( Mirrored)?)(?:(?!.+with Backup))\b'}
        if($StorageType -eq 'Fast Storage with Backup'){$storageProfileName = '^\bFast Storage [AB]{1,2}(( Mirrored)?) with Backup\b'}
        if($StorageType -eq 'Ultra Fast Storage'){$storageProfileName = '^\bUltra Fast Storage [AB]{1,2}(( Mirrored)?)(?:(?!.+with Backup))\b'}
        if($StorageType -eq 'Ultra Fast Storage with Backup'){$storageProfileName = '^\bUltra Fast Storage [AB]{1,2}(( Mirrored)?) with Backup\b'}
        if($StorageType -eq 'Migration Storage'){$storageProfileName = '^\bMigration Storage(2|3)?\b'}
        Write-Verbose " $fn | search target storage profile"
        $storageprofiles.Vdc.VdcStorageProfiles.VdcStorageProfile | Where{($_.name -match $storageProfileName)}| %{
            $targetStorageprofile = $_
          }
        Write-Debug "$fn | Storage Profile: $($targetStorageprofile.href), $($targetStorageprofile.name)"

        ### get all vms
        $vmList = @{};
        Write-Host "$fn | getting VMs"
        if($VAppName){
            if($StorageType -eq 'Migration Storage'){
                Write-Verbose "$fn | get all VMs in target vApp $VAppName in vDC $VdcName"
                $getVmsURI = "https://$ApiEndPoint/api/query?type=vm&pageSize=$pageSize&filter=containerName==$VAppName;vdc==$vdcUri"
            }else{
                Write-Verbose "$fn | get all VMs in target vApp $VAppName on migration storage."
                $getVmsURI = "https://$ApiEndPoint/api/query?type=vm&pageSize=$pageSize&filter=containerName==$VAppName;vdc==$vdcUri;storageProfileName==Migration%20Storage"
            }
        }else{
            if($StorageType -eq 'Migration Storage'){
                Write-Verbose "$fn | get all VMs in target vdc $VdcName"
                $getVmsURI = "https://$ApiEndPoint/api/query?type=vm&pageSize=$pageSize&filter=vdc==$vdcUri"
            }else{
                Write-Verbose "$fn | get all VMs in target vdc $VdcName on migration Storage"
                $getVmsURI = "https://$ApiEndPoint/api/query?type=vm&pageSize=$pageSize&filter=vdc==$vdcUri;storageProfileName==Migration%20Storage"
            }
        }
        
        [xml]$vmRecords = Invoke-VCDRestRequest -URI $getVmsURI -Method 'Get' -ApiVersion $ApiVersion -Verbose:$VerbosePreference -Debug:$DebugPreference
        $total = $vmRecords.QueryResultRecords.total
        
        if($total -gt 0){
            Write-Host "$fn | $total VMs found to change Storage Profile" 
            $pages = [Math]::Ceiling($total/$pageSize)
            Write-Verbose "$fn | $pages Pages to check"
            if($pages -gt 1){
                for($i=1; $i -le $pages; $i++){
                    Write-Verbose "$fn | checking page $i"
                    [xml]$vmRecords = Invoke-VCDRestRequest -URI "$getVmsURI&page=$i" -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
                    foreach($vm in $vmRecords.QueryResultRecords.VmRecord){
                        $vmList.Add($vm.name, $vm.href)
                    }
                }
            }else{
                foreach($vm in $vmRecords.QueryResultRecords.VmRecord){
                    $vmList.Add($vm.href, $vm.name)
                }
            }
        
            # change storage profile of selected VMs
            $startDate = Get-Date -Format o
            foreach($vm in $vmList.GetEnumerator()){
                Write-Host "$fn | change storage profile of VM: $($vm.Key), $($vm.Value) to $($targetStorageProfile.name)"
                Set-VmStorageProfile -vmUri $vm.Key -targetStorageprofileName $targetStorageprofile.name -targetStorageprofileHref $targetStorageprofile.href -AllDisks -Verbose:$VerbosePreference -Debug:$DebugPreference
                #Write-Host $result.RawContent
            }
            ### check for running Tasks
            $taskUri = "https://$ApiEndpoint/api/query?type=task&filter=status==running;startDate=ge=$([System.Web.HttpUtility]::UrlEncode($startDate))"
            Write-Host "$fn | Waiting for tasks to be completed."
            Write-Debug $taskUri
            Wait-OrgTasks -taskListUri $taskUri
            Write-Host "$fn | Storage Migration of all selected VMs finished"
        }else{
            Write-Error "$fn | No VMs found to change storage profile"
        }
        
        #endregion Main
        # ######################################################################
    }catch {
        Write-Error "$fn | Move VMs to a target storage profile was failed!"
		Write-Host "Exception: "$_.Exception.Message
    }
} # Process
