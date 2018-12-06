<#
        .SYNOPSIS
        Swisscom Module for vCloud Director REST API
        .DESCRIPTION
        This Module contains functions to automate tasks after the Migration using vCloud Director REST API
#>
# ######################################################################
# ScriptName:   vcloud_director.psm1
# Description: 	Swisscom Module for vCloud Director
# Created by: 	
# ######################################################################


Function Invoke-VCDRestRequest{
<# 
 .Synopsis
  Invokes a Webrequest against vCloud Director

 .Description
  Adds the required Headers and invokes a Webrequest against vCloud Director.

 .Parameter URI
  Request URI
 .Parameter URI
  Request Content-Type
 .Parameter Method
  Request Method
 .Parameter ApiVersion
  Optional vCD API-Version. By Default taken from $Global:vCloud.ApiVersion
 .Parameter Body
  Request Body
 .Parameter Timeout
  Request Timeout in seconds, Default is 40sec

 .Example
  #GET using default API-Version
  Invoke-VCDRestRequest -URI 'https://my.vcloud.com/api/query' -Method 'Get'
  .Example
  #GET using API-Version 27.0
  Invoke-VCDRestRequest -URI 'https://my.vcloud.com/api/query' -Method 'Get' -ApiVersion 27.0
 .Example
  #PUT
  Invoke-VCDRestRequest -URI 'https://my.vcloud.com/api/vApp/{vApp-Id}/owner' -Method 'Put' -ContentType 'application/*+xml' -Body $vAppOwner.InnerXml
#>

Param(
[Parameter(Mandatory=$true)]
[string]$URI,
[Parameter(Mandatory=$false)]
[string]$ContentType,
[Parameter(Mandatory=$true)]
[string]$Method = 'Get',
[Parameter(Mandatory=$false)]
[string]$ApiVersion = $Global:vCloud.ApiVersion,
[Parameter(Mandatory=$false)]
[string]$Body,
[Parameter(Mandatory=$false)]
[int]$Timeout = 40
)
    [String] $fn = $MyInvocation.MyCommand.Name

    $mysessionid = $Global:vCloud.SessionId
    $Headers = @{"x-vcloud-authorization" = $mysessionid; "Accept" = 'application/*+xml;version=' + $ApiVersion}
    if (!$ContentType) { Remove-Variable ContentType }
    if (!$Body) { Remove-Variable Body }
    Try{
        Invoke-WebRequest -Uri $URI -Method $Method -Headers $Headers -Body $Body -ContentType $ContentType -TimeoutSec $Timeout -Verbose:$VerbosePreference
    }Catch{
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $responseBody = $reader.ReadToEnd();

        Write-Output "Exception: " $_.Exception.Message
        Write-Output "Response: " $responsebody
        if ( $_.Exception.ItemName ) { Write-Output "Failed Item: " $_.Exception.ItemName }
        Write-Output "Exiting."
        Return
    }
    
}

Function Invoke-VCDLogin{
<# 
 .Synopsis
  get a vCloud Director session token

 .Description
  Authenticates against vCloud Director and stores the session token, API-Version and API-Endpoint in a global variable ($Global:vCloud).

 .Parameter ApiEndpoint
  a vCloud Director host
  .Parameter Org
  a vCloud Director Organization
  .Parameter User
  a vCloud Director API user
  .Parameter Password
  a password for the API user
  .Parameter ApiVersion
  a supported API-Version

 .Example
  #Login 
  Invoke-VCDLogin -ApiEndpoint my.vcloud.com -Org MyVCDOrg -User MyApiUser -Password MyApiPassword -ApiVersion '29.0'
#>

Param(
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[String]$ApiEndpoint,
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[String]$Org,
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[String]$User,
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[String]$Password,
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[String]$ApiVersion
)
    [String] $fn = $MyInvocation.MyCommand.Name

    $Global:vCloud = @{}
    $loginUri = "https://$ApiEndpoint/api/sessions"
    $userName = "$User@$Org"
    # Encode username and password
    $authString = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($userName+":"+$Password))
    #set TLS to 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    #set header and do the request
    $Headers = @{ Authorization = "Basic $authString"; Accept = 'application/*+xml;version=' + $ApiVersion}
    $response = Invoke-WebRequest -Uri $loginUri -Method Post -Headers $Headers
    
    if($response.StatusCode -eq 200){
        #get sessionid
        foreach($key in $response.Headers.GetEnumerator()){
            if($key.Key -eq 'x-vcloud-authorization'){
                $session = $key.Value
                break
            }
        }
        $Global:vCloud.ApiEndpoint = $ApiEndpoint
        $Global:vCloud.SessionId = $session
        $Global:vCloud.ApiVersion = $ApiVersion
        Write-Host "$fn | Login for User: $userName successful."
    }else{
        Write-Host "$fn | Error while login"
        Write-Host "$fn | Status Code: "$response.StatusCode
        Write-Host "$fn | $response"
    }
}

Function Set-VmStorageProfile{
<# 
 .Synopsis
  set storage profile of a VM

 .Description
  Set a VM's default storage profile to the specified storage profile. And sets all Disks of a VM to "Use VM default" if parameter AllDisks is set

 .Parameter VmUri
  a VM's URI
 .Parameter TargetStorageprofileName
  name of the target storage profile
 .Parameter TargetStorageprofileHref
  URI of the target storage profile
 .Parameter AllDisks
  set all disk to "Use VM default"

 .Example
  # only default profile 
  Set-VmStorageProfile -vmUri $vm.href -targetStorageprofileName $targetStorageprofile.name -targetStorageprofileHref $targetStorageprofile.href
  .Example
  # set storage profile for all disks 
  Set-VmStorageProfile -vmUri $vm.href -targetStorageprofileName $targetStorageprofile.name -targetStorageprofileHref $targetStorageprofile.href -AllDisks
#>

Param(
[Parameter(Mandatory=$true)]
[String]$VmUri,
[Parameter(Mandatory=$true)]
[String]$TargetStorageprofileName,
[Parameter(Mandatory=$true)]
[String]$TargetStorageprofileHref,
[Parameter(Mandatory=$false)]
[switch]$AllDisks
)
    [String] $fn = $MyInvocation.MyCommand.Name

    [xml]$vmDetails = Invoke-VCDRestRequest -URI $VmUri -Method 'Get'
    Write-Debug "$fn | `n====================== VM details original ======================
                `n$($vmDetails.innerXml)
                `n====================== VM details original ======================"
    $vmDetails.Vm.StorageProfile.href = $TargetStorageprofileHref
    $vmDetails.Vm.StorageProfile.name = $TargetStorageprofileName
    
    Write-Debug "$fn | `n====================== VM details modified ======================
                `n$($vmDetails.innerXml)
                `n====================== VM details modified ======================"
    Write-Host "$fn | migrate VM: $($vmDetails.Vm.name) to $($TargetStorageprofileName)"
    [xml]$result = Invoke-VCDRestRequest -URI $VmUri -Method 'Put' -Body $vmDetails.InnerXml -ContentType 'application/vnd.vmware.vcloud.vm+xml'
    if($AllDisks.IsPresent){
        Wait-VCDTask -TaskUri $result.Task.href
        [xml]$diskDetails = Invoke-VCDRestRequest -URI "$VmUri/virtualHardwareSection/disks" -Method 'Get'
        Write-Debug "$fn | `n====================== Disk details original ======================
                `n$($diskDetails.innerXml)
                `n====================== Disk details original ======================"
        Write-Verbose "$fn | AllDsiks selected - Setting attribute storageProfileOverrideVmDefault of all disks to false"
        foreach($item in $diskDetails.RasdItemsList.Item){
            if($item.Description -eq "Hard Disk"){
                $item.HostResource.storageProfileOverrideVmDefault = "false"
            }
        }
        Write-Debug "$fn | `n====================== Disk details modified ======================
                `n$($diskDetails.innerXml)
                `n====================== Disk details modified ======================"
        $response = Invoke-VCDRestRequest -URI "$VmUri/virtualHardwareSection/disks" -Method 'Put' -Body $diskDetails.InnerXml -ContentType 'application/vnd.vmware.vcloud.rasdItemsList+xml'
    }
    $response
}

Function Wait-OrgTasks{
Param(
[Parameter(Mandatory=$true)]
[String]$TaskListUri
)
    [String] $fn = $MyInvocation.MyCommand.Name
    Write-Host "$fn | Waiting for tasks to finish"
    Sleep 5
    $runningTasks = $true
    while($runningTasks){
        [xml]$tasks = Invoke-VCDRestRequest -URI $TaskListUri -Method 'Get'
        $num = $tasks.QueryResultRecords.TaskRecord | measure
        if($num.Count -eq 0){
            $runningTasks = $false
            break
        }
        Write-Host -NoNewline "."
	    Sleep 15
    }
    Write-Host "$fn | All Tasks finished"
}

Function Wait-VCDTask{
<# 
 .Synopsis
  checks status of a task

 .Description
  Checks status of a given Task

 .Parameter TaskUri
  an URI of a Task
 
 .Example
  # only default profile 
  Wait-VCDTask -TaskUri $response.Task.href
#>
Param(
[Parameter(Mandatory=$true)]
[String]$TaskUri
)
    [String] $fn = $MyInvocation.MyCommand.Name
    Write-Host "$fn | Waiting for task to finish"
    $taskIsRunning = $true
    while($taskIsRunning){
        Write-Host -NoNewline "."
        [xml]$task = Invoke-VCDRestRequest -URI $TaskUri -Method 'Get' -Verbose:$false
        $status = $task.Task.status
        if($status -ne 'running' -and $status -ne 'queued'){
            $taskIsRunning = $false
            Write-Host "done"
            break
        }
	    Sleep 5
    }
    Write-Host "$fn | Task finished with status $status" -
}

Function Set-VAppPermission{
<# 
 .Synopsis
  change owner or access control of a vApp 

 .Description
  change owner of a vApp or share vApp with a specified user or Everyone

 .Parameter VAppUri
  a vApp's URI
 .Parameter Permission
  Permission the user get's when shearing the vApp
 .Parameter NewOwner
  name of the new owner
 .Parameter ShareWith
  optional, name of the user to shar the vApp with. Default is Everyone

 .Example
  # share vApp with specific user 
  Set-VAppPermission -VAppURI $vApp.href -Permission ReadOnly -ShareWith $user
  .Example
  # share vApp with Everyone 
  Set-VAppPermission -VAppURI $vApp.href -Permission ReadOnly
  .Example
  # change owner of vApp 
  Set-VAppPermission -VAppURI $vApp.href -NewOwner $user
#>

[CmdletBinding(DefaultParameterSetName='shareVApp')]
Param(
[Parameter(Mandatory = $true)]
[String]$VAppUri,
[Parameter(Mandatory = $true, ParameterSetName = 'shareVApp')]
[ValidateSet('ReadOnly','ReadWrite','FullControl')]
[String]$Permission,
[Parameter(Mandatory = $true, ParameterSetName = 'changeOwner')]
[String]$NewOwner,
[Parameter(Mandatory = $false, ParameterSetName = 'shareVApp')]
[String]$ShareWith = 'Everyone'
)
    [String] $fn = $MyInvocation.MyCommand.Name

    if($PSBoundParameters.ContainsKey('newOwner')){
        Write-Host "$fn | changing ownership of vApp to $NewOwner"
        ### get user
        $getUserUri = "https://$($Global:vCloud.ApiEndpoint)/api/query?type=user&filter=name==$NewOwner"
        Write-Verbose "$fn | getting User with URI: $getUserUri"
        [xml]$userRecord = Invoke-VCDRestRequest -URI $getUserUri -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
        Write-Debug "$fn | `n====================== User Record ======================
                    `n$($userRecord.innerXml)
                    `n====================== User Record ======================"

        ### get vApp owner section and change owner
        [xml]$vAppOwner = Invoke-VCDRestRequest -URI "$VAppUri/owner" -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
        Write-Debug "$fn | `n====================== Owner original ======================
                    `n$($vAppOwner.innerXml)
                    `n====================== Owner original ======================"
        Write-Verbose "$fn | setting new owner"
        $vAppOwner.Owner.User.href = $userRecord.QueryResultRecords.UserRecord.href 
        $vAppOwner.Owner.User.name = $userRecord.QueryResultRecords.UserRecord.name
        Write-Debug "$fn | `n====================== Owner modified ======================
                    `n$($vAppOwner.innerXml)
                    `n====================== Owner modified ======================"
        Invoke-VCDRestRequest -URI "$VAppUri/owner" -Method 'Put' -ContentType 'application/*+xml' -Body $vAppOwner.InnerXml -Verbose:$VerbosePreference -Debug:$DebugPreference
    }
    elseif($PSBoundParameters.ContainsKey('permission') -and $ShareWith -ne 'Everyone'){
        Write-Host "$fn | share vApp with $ShareWith"
        ### get user
        $getUserUri = "https://$($Global:vCloud.ApiEndpoint)/api/query?type=user&filter=name==$ShareWith"
        Write-Verbose "$fn | getting User with URI: $getUserUri"
        [xml]$userRecord = Invoke-VCDRestRequest -URI $getUserUri -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
        Write-Debug "$fn | `n====================== ControlAccess original ======================
                    `n$($vAppAccessControl.innerXml)
                    `n====================== ControlAccess original ======================"
        ### get vApp access control section and add user with permission
        [xml]$vAppAccessControl = Invoke-VCDRestRequest -URI "$VAppUri/controlAccess" -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
        Write-Debug "$fn | `n====================== ControlAccess original ======================
                    `n$($vAppAccessControl.innerXml)
                    `n====================== ControlAccess original ======================"
        Write-Verbose "$fn | creating new ChildNodes"
        $newAccessLevel= $vAppAccessControl.CreateElement("AccessLevel", "http://www.vmware.com/vcloud/v1.5")
        Write-Verbose "$fn | setting Permission to $Permission"
        $newAccessLevel.InnerText = $Permission
        Write-Verbose "$fn | setting User properties"
        $newSubject = $vAppAccessControl.CreateElement("Subject", "http://www.vmware.com/vcloud/v1.5")
        $newSubject.SetAttribute("href",$userRecord.QueryResultRecords.UserRecord.href)
        $newSubject.SetAttribute("name",$userRecord.QueryResultRecords.UserRecord.name)
        $newSubject.SetAttribute("type","application/vnd.vmware.admin.user+xml")
        
        $newAccessSetting = $vAppAccessControl.CreateElement("AccessSetting", "http://www.vmware.com/vcloud/v1.5")   
        $newAccessSetting.AppendChild($newSubject)
        $newAccessSetting.AppendChild($newAccessLevel)
        Write-Verbose "$fn | appending new Child to Element AccessSettings"
        if($vAppAccessControl.ControlAccessParams.AccessSettings.HasChildNodes){
            $vAppAccessControl.ControlAccessParams.AccessSettings.AppendChild($newAccessSetting)
        }else{
            $newAccessSettings= $vAppAccessControl.CreateElement("AccessSettings", "http://www.vmware.com/vcloud/v1.5")
            $newAccessSettings.AppendChild($newAccessSetting)
            $vAppAccessControl.ControlAccessParams.AppendChild($newAccessSettings)
        }
        Write-Debug "$fn | `n====================== ControlAccess original ======================
                    `n$($vAppAccessControl.innerXml)
                    `n====================== ControlAccess original ======================"
        Invoke-VCDRestRequest -URI "$VAppUri/action/controlAccess" -Method 'Post' -ContentType 'application/*+xml' -Body $vAppAccessControl.InnerXml -Verbose:$VerbosePreference -Debug:$DebugPreference
    }
    else{
        Write-Host "$fn | share vApp with Everyone in the Org"
        ### get vApp access contorl section an change to everyone in Org
        [xml]$vAppAccessControl = Invoke-VCDRestRequest -URI "$VAppUri/controlAccess" -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
        Write-Debug "$fn | `n====================== ControlAccess original ======================
                    `n$($vAppAccessControl.innerXml)
                    `n====================== ControlAccess original ======================"
        $vAppAccessControl.ControlAccessParams.IsSharedToEveryone = 'true'
        
        if($vAppAccessControl.ControlAccessParams.EveryoneAccessLevel){
            Write-Verbose "$fn | setting Permission for Everyone to $Permission"
            $vAppAccessControl.ControlAccessParams.EveryoneAccessLevel = $Permission
        }else{
            Write-Verbose "$fn | creating new Element EveryoneAccessLevel"
            $ns = New-Object System.Xml.XmlNamespaceManager($vAppAccessControl.NameTable)
            $ns.AddNamespace("ns","http://www.vmware.com/vcloud/v1.5")
            $newEveryoneAccessLevel = $vAppAccessControl.CreateElement("EveryoneAccessLevel", "http://www.vmware.com/vcloud/v1.5")
            $newEveryoneAccessLevel.InnerXml = $Permission
            $ref = $vAppAccessControl.SelectSingleNode('//ns:ControlAccessParams/ns:IsSharedToEveryone',$ns)
            Write-Verbose "$fn | insert Element EveryoneAccessLevel"
            $vAppAccessControl.ControlAccessParams.InsertAfter($newEveryoneAccessLevel, $ref)
        }
        Write-Debug "$fn |`n====================== ControlAccess modified ======================
                    `n$($vAppAccessControl.innerXml)
                    `n====================== ControlAccess modified ======================"
        Invoke-VCDRestRequest -URI "$VAppUri/action/controlAccess" -Method 'Post' -ContentType 'application/*+xml' -Body $vAppAccessControl.InnerXml -Verbose:$VerbosePreference -Debug:$DebugPreference
    }    
}

Function Add-NetworkToVApp {
<# 
 .Synopsis
  add a network to a vApp 

 .Description
  Add the specified Newtork to the specified vApp

 .Parameter VAppUri
  a vApp's URI
 .Parameter OrgVdcNetwork
  XMl object of the OrgVDCNetwork to be added to the vApp
 .Parameter FenceMode
  specifies the mode how the nework will be connected

 .Example
  #Add a network in bridged mode to the vApp
  Add-NetworkToVApp -VAppURI $vApp.href -OrgVdcNetwork $orgVdcNetwork.innerXml -FenceMode bridged
#>

Param(
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[String]$VAppUri,
[Parameter(Mandatory=$true)]
[ValidateScript({
    if(-Not($_ -is [xml])){ throw "Not an XML object"}
    return $true
})]
[xml]$OrgVdcNetwork,
[Parameter(Mandatory=$true)]
[ValidateSet('bridged','natRouted')]
[String]$FenceMode
)
    [String] $fn = $MyInvocation.MyCommand.Name
	### check if the network is shared and if not check if parent of vApp and network are the same
    if($OrgVdcNetwork.OrgVdcNetwork.isShared -eq 'false'){
        [xml]$vAppDetails = Invoke-VCDRestRequest -URI $VAppUri -Method 'Get' -Verbose:$VerbosePreference
        $vAppDetails.VApp.Link| Where-Object{ $_.rel -eq 'up'} |%{ $vAppParent = $_.href}
        $OrgVdcNetwork.OrgVdcNetwork.Link | Where-Object{ $_.rel -eq 'up'} |%{ $networkParent = $_.href}
        if($vAppParent -ne $networkParent){
            throw "$fn | Network is not shared with OvDC of this vApp"
            
        }
    }
	### check if network is present in vApp and add it if not
    if(!(Search-NetworkInVApp -VAppUri $VAppUri -NetworkName $OrgVdcNetwork.OrgVdcNetwork.name)){
        Write-Host "$fn | adding network $($OrgVdcNetwork.OrgVdcNetwork.name) to vApp"
        ### get network part of the vApp
        [xml]$vAppNetworkConfigSection = Invoke-VCDRestRequest -URI "$VAppUri/networkConfigSection" -Method 'Get' -Verbose:$VerbosePreference
        Write-Debug "`n====================== NetworkConfigSection modified ======================
                    `n$($vAppNetworkConfigSection.innerXml)
                    `n====================== NetworkConfigSection modified ======================"

        ### load XML Template and fill in the needed values
        $newNetworkConfig = $vAppNetworkConfigSection.CreateElement("NetworkConfig", "http://www.vmware.com/vcloud/v1.5")
        $newConfiguration = $vAppNetworkConfigSection.CreateElement("Configuration", "http://www.vmware.com/vcloud/v1.5")
        $newParentNetwork = $vAppNetworkConfigSection.CreateElement("ParentNetwork", "http://www.vmware.com/vcloud/v1.5")
        $newFenceMode = $vAppNetworkConfigSection.CreateElement("FenceMode", "http://www.vmware.com/vcloud/v1.5")

        $newNetworkConfig.SetAttribute('networkName',$OrgVdcNetwork.OrgVdcNetwork.name)
        $newParentNetwork.SetAttribute('href',$OrgVdcNetwork.OrgVdcNetwork.href)
        $newParentNetwork.SetAttribute('id',$OrgVdcNetwork.OrgVdcNetwork.id)
        $newParentNetwork.SetAttribute('name',$OrgVdcNetwork.OrgVdcNetwork.name)
        $newFenceMode.InnerText = $FenceMode
        
        $newConfiguration.AppendChild($newParentNetwork)
        $newConfiguration.AppendChild($newFenceMode)
        $newNetworkConfig.AppendChild($newConfiguration)
        
        
        $vAppNetworkConfigSection.NetworkConfigSection.AppendChild($newNetworkConfig)
        Write-Debug "`n====================== NetworkConfigSection modified ======================
                    `n$($vAppNetworkConfigSection.innerXml)
                    `n====================== NetworkConfigSection modified ======================"

        Invoke-VCDRestRequest -URI "$VAppUri/networkConfigSection" -Method 'Put' -Body $vAppNetworkConfigSection.innerXml -ContentType 'application/vnd.vmware.vcloud.networkConfigSection+xml' -Verbose:$VerbosePreference
    }else{
        Write-Output "$fn | Network already exists in this vApp"
    }
}

Function Search-NetworkInVApp {
<# 
 .Synopsis
  searches a network in a vApp 

 .Description
  serach a network in a vApp 

 .Parameter VAppUri
  a vApp's URI
 .Parameter NetworkName
  a name of a network to search fo in a vApp

 .Example
  # share vApp with specific user 
  Search-NetworkInVApp -VAppURI 'https://my.vcloud.com/api/vApp/vapp-{id} -NetworkName 'MyOrgNetwork'
#>
Param(
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[String]$VAppUri,
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[String]$NetworkName
)
    [String] $fn = $MyInvocation.MyCommand.Name
    
    ### get network part of the vApp
    Write-Host "$fn | searching for network $NetworkName in vApp"
    $networkIsPresent = $false
    [xml]$networkConfigSection = Invoke-VCDRestRequest -URI "$VAppUri/networkConfigSection" -Method 'Get'
    foreach($networkConfig in $networkConfigSection.NetworkConfigSection.NetworkConfig){
        if($networkConfig.networkName -eq $NetworkName){
            $networkIsPresent = $true
            break
        }
    }
    if($networkIsPresent){
        Write-Host "$fn | the network $NetWorkName is present in vApp"
    }else{
        Write-Host "$fn | the network $NetWorkName is not present in vApp"
    }
    $networkIsPresent
}

Function Add-NetworkAdapter{
<# 
 .Synopsis
  add a network adapter to a VM 

 .Description
  add a network adapter to the specified VM 

 .Parameter VmUri
  a VM's URI
 .Parameter PrimaryAdapter
  set to add primary adapter
 
 .Example
  # share vApp with specific user 
  Add-NetworkAdapter -VmURI 'https://my.vcloud.com/api/vApp/vm-{id}'
#>

Param(
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[String]$VmUri,
[Parameter(Mandatory=$false)]
[Switch]$PrimaryAdapter
)
    [String] $fn = $MyInvocation.MyCommand.Name

    Write-Verbose "$fn | getting network card section of VM"
    [xml]$vmNetworkCards = Invoke-VCDRestRequest -URI "$VmUri/virtualHardwareSection/networkCards" -Method 'Get' -Verbose:$VerbosePreference -Debug:$DebugPreference
    
    [System.Xml.XmlNamespaceManager] $nsm = new-object System.Xml.XmlNamespaceManager $vmNetworkCards.NameTable
    $nsm.AddNamespace("ns10", "http://www.vmware.com/vcloud/v1.5") 
    $nsm.AddNamespace("rasd", $vmNetworkCards.rasdItemsList.GetNamespaceOfPrefix("rasd"))

    $numberOfNIC = $vmNetworkCards.RasdItemsList.Item.AddressOnParent.Count

    if($numberOfNIC -eq 10){
        Write-Error "VM already has $numberOfNIC network adapter"
        return
    }
    if($numberOfNIC -gt 0 -and $PrimaryAdapter.IsPresent){
        Write-Error "VM already has a primary network adapter"
        return
    }
    Write-Debug "$fn |`n====================== NetworkConfigSection original ======================
                    `n$($vmNetworkCards.innerXml)
                    `n====================== NetworkConfigSection original ======================"
    
    
    # create new Network adapter
    Write-Verbose "$fn | creating new Element Item with Default Values"
    $newItem = $vmNetworkCards.CreateElement('Item','http://www.vmware.com/vcloud/v1.5')
    $newAddressOnParent = $vmNetworkCards.CreateElement('rasd:AddressOnParent',$nsm.LookupNamespace('rasd'))
	$newConnection = $vmNetworkCards.CreateElement('rasd:Connection',$nsm.LookupNamespace('rasd'))
    $newElementName = $vmNetworkCards.CreateElement('rasd:ElementName',$nsm.LookupNamespace('rasd'))
	$newInstanceID = $vmNetworkCards.CreateElement('rasd:InstanceID',$nsm.LookupNamespace('rasd'))
	$newResourceSubType = $vmNetworkCards.CreateElement('rasd:ResourceSubType',$nsm.LookupNamespace('rasd'))
	$newResourceType = $vmNetworkCards.CreateElement('rasd:ResourceType',$nsm.LookupNamespace('rasd'))
    
    $newAddressOnParent.InnerText = '0'
    $attr = $newConnection.OwnerDocument.CreateAttribute('ns10:ipAddressingMode',$nsm.LookupNamespace('ns10'))
    $attr.Value = 'NONE'
    $newConnection.Attributes.Append($attr)
    $attr = $newConnection.OwnerDocument.CreateAttribute('ns10:primaryNetworkConnection',$nsm.LookupNamespace('ns10'))
    $attr.Value = 'true'
    $newConnection.Attributes.Append($attr)
    $newConnection.InnerText = 'none'
    $newResourceSubType.InnerText = 'VMXNET3'
    $newResourceType.InnerText = '10'
    
    $newItem.AppendChild($newAddressOnParent)
    $newItem.AppendChild($newConnection)
    $newItem.AppendChild($newElementName)
    $newItem.AppendChild($newInstanceID)
    $newItem.AppendChild($newResourceSubType)
    $newItem.AppendChild($newResourceType)
    
    if($numberOfNIC -gt 0 -and $numberOfNIC -le 10){
        Write-Host "$fn | VM already has $numberOfNIC network adapter"
        # search for a free address
        for($i=0; $i-le 9; $i++){
            $node = $vmNetworkCards.SelectSingleNode("//*/rasd:AddressOnParent[. = '$i']", $nsm)
            if(!$node){
                Write-Host "$fn | address $i is not used"
                $addressOnParent= $i
                break
            }
        }
        Write-Verbose "$fn | setting AddressOnParent to $addressOnParent"
        $newItem.AddressOnParent = "$addressOnParent"
        Write-Verbose "$fn | setting primaryNetworkConnection to false"
        $newItem.Connection.primaryNetworkConnection = 'false'
        Write-Verbose "$fn | append new Element"
        $vmNetworkCards.RasdItemsList.AppendChild($newItem)
    }else{
        Write-Host "$fn | No Networkadapter present, add new primary adapter"
        $vmNetworkCards.RasdItemsList.AppendChild($newItem)
    }

    Write-Debug "$fn |
                    `n====================== NetworkConfigSection modified ======================
                    `n$($vmNetworkCards.innerXml)
                    `n====================== NetworkConfigSection modified ======================"
    
    Invoke-VCDRestRequest -URI "$VmUri/virtualHardwareSection/networkCards" -Method 'Put' -Body $vmNetworkCards.innerXml -ContentType 'application/vnd.vmware.vcloud.rasdItemsList+xml' -Verbose:$VerbosePreference -Debug:$DebugPreference
}

Function Connect-NetworkAdapter{
<# 
  .Synopsis
  connect a network adapter to a network 

  .Description
  connect a network adapter of a VM to a network 

  .Parameter VmUri
  a VM's URI
  .Parameter NetworkName
  name of the network to connect
  .Parameter Adapter
  adapter number or primary adapter
  .Parameter AutomaticIpAddress
  an automatic addressing mode
  .Parameter ManualIpAddress
  an ip address for manual addressing

 .Example
  # connect adapter no. 1 to network using IP pool of the network to assing IP address 
  Connect-NetworkAdapter -VmUri $vmUri -Adapter 1 -AutomaticIpAddress POOL -NetworkName 'MyNetwork'
  .Example
  # connect primary adapter to network with a static IP address 
  Connect-NetworkAdapter -VmUri $vmUri -Adapter primary -ManualIpAddress 192.168.1.10 -NetworkName 'MyNetwork'
#>
[CmdletBinding(DefaultParameterSetName='Default')]
Param(
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[String]$VmUri,
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[String]$NetworkName,
[Parameter(Mandatory=$false, ParameterSetName = 'Default')]
[Parameter(Mandatory=$false, ParameterSetName = 'ManualIpAddress')]
[ValidateSet('primary','0','1','2','3','4','5','6','7','8','9')]
[String]$Adapter,
[Parameter(Mandatory=$true, ParameterSetName = 'Default')]
[ValidateSet('DHCP', 'POOL')]
[String]$AutomaticIpAddress,
[Parameter(Mandatory=$true, ParameterSetName = 'ManualIpAddress')]
[ValidatePattern('\b((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}\b')]
[String]$ManualIpAddress
)
    [String] $fn = $MyInvocation.MyCommand.Name

    [xml]$vmNetworkCards = Invoke-VCDRestRequest -URI "$VmUri/virtualHardwareSection/networkCards" -Method 'Get'
    Write-Debug "$fn |
                    `n====================== NetworkConfigSection original ======================
                    `n$($vmNetworkCards.innerXml)
                    `n====================== NetworkConfigSection original ======================"

    [System.Xml.XmlNamespaceManager] $nsm = new-object System.Xml.XmlNamespaceManager $vmNetworkCards.NameTable
    $nsm.AddNamespace("ns10", "http://www.vmware.com/vcloud/v1.5") 
    $nsm.AddNamespace("rasd", $vmNetworkCards.rasdItemsList.GetNamespaceOfPrefix("rasd"))

    # search adapter number of primary adapter  
    if($Adapter -eq 'primary'){
        Write-Host "$fn | Selected adapter is primary, getting adapter number"
        $node = $vmNetworkCards.SelectSingleNode("//*/rasd:Connection[@ns10:primaryNetworkConnection = 'true']",$nsm)
        if($node){
            $Adapter = $node.ParentNode.AddressOnParent
            Write-Verbose "$fn | primary adapter is number $Adapter"
        }else{
            Write-Error "$fn | no primary adapter found"
            return
        }  
    }

    # search adapter and connect to specified network
    Write-Verbose "$fn | Searching adapter $Adapter"
    $node = $vmNetworkCards.SelectSingleNode("//*/rasd:AddressOnParent[. = '$Adapter']",$nsm)
    $networkAdapter = $node.ParentNode
    if($networkAdapter){
        # check if adapter is already connected
        Write-Host "$fn | connecting adapter $Adapter to Network $NetworkName"
        if($networkAdapter.Connection.innerText -ne 'none'){
            Write-Error "$fn | Adapter $Adapter is already connected to the following network: $($networkAdapter.Connection.innerText)"
            return
        }
        # setting correct IpAddressingMode
        if($PSBoundParameters.ContainsKey('ManualIpAddress')){
            $ipAddressingMode = 'MANUAL'
            Write-Host "$fn | Setting IP allocation mode to $ipAddressingMode"
        }else{
            $ipAddressingMode = $AutomaticIpAddress
            Write-Host "$fn | Setting IP allocation mode to $ipAddressingMode"
        }

        Write-Verbose "$fn | Setting Connection to $NetworkName"
        $networkAdapter.Connection.innerText = $NetworkName
        $networkAdapter.AutomaticAllocation = 'true'
        Write-Verbose "$fn | Setting Connection to $ipAddressingMode"
        $networkAdapter.Connection.ipAddressingMode = $ipAddressingMode
        if($ManualIpAddress){
            # create attribute ipAddress if it does not exist and set value
            if(!$networkAdapter.Connection.ipAddress){
                Write-Verbose "$fn | create missing attribute ipAddress and set it to $ManualIpAddress"
                $attr = $networkAdapter.Connection.OwnerDocument.CreateAttribute('ipAddress',$nsm.LookupNamespace('ns10'))
                $attr.Value = $ManualIpAddress
                $networkAdapter.Connection.Attributes.Append($attr)
            }else{
                Write-Verbose "$fn | Setting ipAddress to $ManualIpAddress"
                $networkAdapter.Connection.ipAddress = $ManualIpAddress
            }
        }
    }else{
        Write-Error "$fn | No network adapter with addres $Adapter found"
        return
    }

     Write-Debug "$fn |
                    `n====================== NetworkConfigSection modified ======================
                    `n$($vmNetworkCards.innerXml)
                    `n====================== NetworkConfigSection modified ======================"
    Invoke-VCDRestRequest -URI "$VmUri/virtualHardwareSection/networkCards" -Method 'Put' -ContentType 'application/vnd.vmware.vcloud.rasdItemsList+xml' -Body $vmNetworkCards.InnerXml -Verbose:$VerbosePreference -Debug:$DebugPreference
}