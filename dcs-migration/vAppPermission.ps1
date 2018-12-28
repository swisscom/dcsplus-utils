<#
    .SYNOPSIS
	Shares selected vApps with current API-User
    
    .DESCRIPTION
    This Script searches all vApps or those matching the parameter VAppNamefilter and shares them vApp with the current API-User.
	The Permission set for the API-User is FullControl.
    
    .Parameter ApiEndpoint
	vCloud Director endpoint
	.Parameter User
	API-User
	.Parameter Password
	password for API-User
	.Parameter Organization
	vCloud Director Organization
	.Parameter VAppNamefilter
	name of a vApp to filter VMs
	.Parameter AllVApps
	switch if set all vApps will be shared (default)
	.Parameter ApiVersion
	Version of the vCloud Director API. Default is set to 27.0

	.Example
	# share all vApps with Everyone in the Organization with permission ReadOnly
	.\changeVAppPermission.ps1 -ApiEndpoint my.vcloud.com -User MyApiUser -Password MyPassword -Organization MyOrganization -AllVApps
	.Example
	# share all vApps with name starting with MyVApp with Everyone in the Organization with permission ReadOnly
	.\changeVAppPermission.ps1 -ApiEndpoint my.vcloud.com -User MyApiUser -Password MyPassword -Organization MyOrganization -VAppNamefilter 'MyVApp*'
    .Example
	# share all vApps with Everyone in the Organization with permission ReadOnly using a specific API-Version
	.\changeVAppPermission.ps1 -ApiEndpoint my.vcloud.com -User MyApiUser -Password MyPassword -Organization MyOrganization -AllVApps -ApiVersion 29.0
#>
# ######################################################################
# ScriptName:   changeVAppPermission.ps1
# Description: 	Swisscom Script to change permission of vApps
# Created by: 
# ######################################################################
 
[CmdletBinding(
     DefaultParameterSetName='Default',
     ConfirmImpact = 'Low',
     HelpURI = 'https://github.com/swisscom/dcsplus-utils/blob/master/dcs-migration/README.md'
)]
 Param(
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
    
    [Parameter(Mandatory = $true ,ParameterSetName ='FilterVApps')]
    [ValidateNotNullOrEmpty()]
    [String]$VAppNamefilter,

    [Parameter(Mandatory = $true, ParameterSetName='Default')]
    [ValidateNotNullOrEmpty()]
    [switch]$AllVApps,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [String]$ApiVersion = '27.0'
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
        ### get vApps
        $vappList = @{};
        if($AllVApps.IsPresent){
            Write-Host "$fn | all vApps selected"
            $getVAppUri = "https://$ApiEndpoint/api/query?type=vApp&pageSize=$pageSize"
        }else{
            Write-Host "$fn | vApp name filter set"
            $getVAppUri = "https://$ApiEndpoint/api/query?type=vApp&pageSize=$pageSize&filter=name==$VAppNamefilter"
        }
		
        [xml]$vappResult = Invoke-VCDRestRequest -URI $getVAppUri -Method 'Get' -ApiVersion $ApiVersion -Verbose:$VerbosePreference -Debug:$DebugPreference
        $total = $vappResult.QueryResultRecords.total
        if($total -gt 0){
            $pages = [Math]::Ceiling($total/$pageSize)
            Write-Verbose "$fn | $pages Pages to check"
            if($pages -gt 1){
                for($i=1; $i -le $pages; $i++){
                    Write-Verbose "$fn | checking page $i"
                    [xml]$vappResult = Invoke-VCDRestRequest -URI "$getVAppUri&page=$i" -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
                    foreach($vapp in $vappResult.QueryResultRecords.VAppRecord){
                        $vappList.Add($vapp.name,$vapp.href)
                    }
                }
            }else{
                foreach($vapp in $vappResult.QueryResultRecords.VAppRecord){
                    $vappList.Add($vapp.name,$vapp.href)
                }
            }
        
            ### change vApp permission
            foreach($vApp in $vappList.GetEnumerator()){
                Write-Host "$fn | sharing vApp: $($vApp.Key), $($vApp.Value) with $User"
                $result = Set-VAppPermission -VAppUri $vApp.Value -Permission FullControl -ShareWith $User -Verbose:$VerbosePreference -Debug:$DebugPreference
                Write-Debug "$fn | Result:`n$($result.RawContent)"
            }
        }else{
            Write-Error "$fn | No VMs found on Migration Storage"
        }
            
        #endregion Main
        # ######################################################################
    }
    catch {
        Write-Error "change permission for vApps has failed!"
        Write-Host "Exception: "$_.Exception.Message
    }
} # Process