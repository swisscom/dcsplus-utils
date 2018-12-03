<#

    This script polls various metrics from all running VMs inside a particular organization inside vCloudDirector
    The output format is JSON and ia being written to STDOUT.
    If you would like to capture the output to a file, run it like:

    .\vcd-getmetrics.ps1 > out.json

    An explanation on the meaning of the values in the output can be found on VMware's documentation here:
    https://pubs.vmware.com/vca/index.jsp?topic=%2Fcom.vmware.vcloud.api.doc_56%2FGUID-A54D67F6-F608-4096-87AE-B01A4E526052.html

#>

import-module VMware.VimAutomation.Cloud

# The following variables need to be set according your environment
$VCD_HOST = 'vcd-pod-?.swisscomcloud.com'
$VCD_ORG_NAME = 'PRO-00xxxxxx'
$VCD_API_USER = 'api_vcd_xxxxx'
$VCD_API_PASS = '....'

# Establishes the base connection to vCloudDirector
$conn = Connect-CIServer -Server $VCD_HOST -Org $VCD_ORG_NAME -User $VCD_API_USER -Password $VCD_API_PASS

# Iterating through all vApps and VMs in the organization
$out = @{}
ForEach ($vApp in Get-CIVapp) {
    $out[$vApp.Name] = @{}
        ForEach($VM in Get-CIVM -VApp $vApp) {
            if ($VM.Status -eq 'PoweredOn') {
                $out[$vApp.Name][$VM.Name] = @{}
                Foreach($m in $VM.ExtensionData.GetMetricsCurrent().Metric)
                {
                    $out[$vApp.Name][$VM.Name].Add($m.Name, $m.Value)
                }
            }
        }
}

# Writing the $out hashtable as JSON
$out | ConvertTo-Json
