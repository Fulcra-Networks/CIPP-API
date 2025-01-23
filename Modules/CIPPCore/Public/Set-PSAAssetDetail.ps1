<#
    This command as of now, will connect to the configured PSA (Autotask for now) and retrieve all active assets.
    After retrieving the list of assets it will query the configured N-Central RMM and retrieve all matching devices,
    then update the PSA assets that are found, with N-Central asset CPU and RAM detail.
#>
function Set-PSAAssetDetail {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Set PSA Asset Detail'
    )

    try {

        if($TenantFilter -eq 'AllTenants') {
            return "Cannot run job for all Tenants."
        }

        $MappingTable = Get-CIPPTable -TableName CippMapping
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10

        $TenantTable = Get-CIPPTable -TableName Tenants
        $Filter = "defaultDomainName eq '$TenantFilter' and PartitionKey eq 'Tenants'"
        $TenantObj = [pscustomobject](Get-CIPPAzDataTableEntity @TenantTable -Filter $Filter)

        <# Next filter the managed companies to get the Autotask ID of the Tenant selected for the job
        The "name" property is from the CippMapping table and corresponds to the TenantID
        $TenantFilter is the value passed from the Scheduler Screen - This should be the Tenant ID but may be the domain name.
            #(Looks like it according to Scheduled tasks table.)
        We'll need to log that to make sure.
        #>

        if($null -eq $TenantObj){
            Write-LogMessage -user "CIPP" -API $APIName -tenant $TenantFilter -Message "No tenant found using filter $($TenantFilter)"  -Sev "Error"
            return "No tenant matching filter."
        }

        $managedCompanies = Get-AutotaskManaged -CIPPMapping $MappingTable

        $jobCompany = $managedCompanies.ManagedCusts | Where-Object { $_.Name -eq $TenantObj.customerId }

        if($null -eq $jobCompany) {
            Write-LogMessage -user "CIPP" -API $APIName -tenant $TenantFilter -Message "No PSA client found using filter $($TenantFilter)"  -Sev "Error"
            return "No PSA client matching filter."
        }

        Write-LogMessage -user "CIPP" -API $APIName -tenant $TenantFilter -Message "Using $($TenantFilter) for filetering managed companies.."  -Sev "Info"
        Write-LogMessage -user "CIPP" -API $APIName -tenant "None" -Message "Got $($managedCompanies.ManagedCusts.Count) managed companies."  -Sev "Info"

        #Get all AT Configuration Items of type workstation, that are active, that have the "N-central Device ID [UDF]" property set, and Managed for the Client
        #Get-AutotaskAPIResource -Resource ConfigurationItemTypes -SimpleSearch "isactive eq $true "
        <# ID list of all Asset Types
                id isActive name
            -- -------- ----
            1     True Workstation
            2     True Server
            3     True Firewall
            4     True Wireless Access Point
            5     True Printer
            6     True UPS
            7     True Anti-Virus
            8     True Domain Registration
            9     True Software
            10     True Web Hosting
            11     True SSL Certificate
            12     True DVR/NVR/VMS
            13     True Standard
            14     True Non-Standard
            16     True Network Device
        #>
        $query = @"
            { "filter": [
                    {
                        "op": "and",
                        "items": [
                            {
                                "op": "eq",
                                "field": "isactive",
                                "value": "True"
                            },
                            {
                                "op": "lte",
                                "field": "configurationItemType",
                                "value": "2"
                            },
                            {
                                "op": "exist",
                                "field": "N-central Device ID",
                                "udf": true
                            },
                            {
                                "op": "eq",
                                "field": "companyID",
                                "value": "$($jobCompany.aid)"
                            }
                        ]
                    }
            ]}
"@
        $query = (ConvertFrom-Json $query) | ConvertTo-Json -Depth 10 -Compress

        Get-AutotaskToken -configuration $Configuration.Autotask
        $ncJWT = Get-NCentralJWT
        Connect-Ncentral -ApiHost $Configuration.NCentral.ApiHost -key ($ncJWT|ConvertTo-SecureString -AsPlainText -Force)

        $ATDevices = Get-AutotaskAPIResource -Resource ConfigurationItems -SearchQuery $query

        foreach ($ATDevice in $ATDevices){
            try{
                $NCid = $ATDevice.userDefinedFields | Where-Object {$_.Name -eq 'N-central Device ID'}
                $eligibleAT = $ATDevice.userDefinedFields|?{$_.Name -eq 'OS Upgrade Eligible'}

                $NCDevice = Get-NCentralDeviceDetail -DeviceId $NCid.Value

                #update the AT configuration item
                $body = [PSCustomObject]@{ userDefinedFields = [System.Collections.ArrayList]::new() }
                $body.userDefinedFields.add([pscustomobject]@{"name" = "RAM"; "value" = "$([math]::Round($NCDevice.data.computersystem.totalphysicalmemory/([Math]::Pow(1024,3))))GB"})|Out-Null
                $body.userDefinedFields.add([pscustomobject]@{"name" = "CPU"; "value" =  "$($NCDevice.data.processor.name) (x$($NCDevice.processor.numberofcpus))"})|Out-Null
                $body.userDefinedFields.add([pscustomobject]@{"name" = "Last Boot Time"; "value" = "$($NCDevice.data.os.lastbootuptime)"})|Out-Null
                $body.userDefinedFields.add([pscustomobject]@{"name" = "OS"; "value" = $NCDevice.data.os.reportedos})|Out-Null
                $body.userDefinedFields.add([pscustomobject]@{"name" = "OS Architecture"; "value" = $NCDevice.data.os.osarchitecture})|Out-Null
                $body.userDefinedFields.add([pscustomobject]@{"name" = "Version"; "value" = $NCDevice.data.os.version})|Out-Null

                #Check if OS Upgrade eligible field is set
                #If not add the field
                #Note if it's false, we will still try because it could have been errantly set as false.
                if($eligibleAT.value -ne 'true'){
                    $NCDeviceServices = Get-NcentralDeviceServicesMonitoring -DeviceId $NCid.Value
                    $service = $NCDeviceServices|?{$_.moduleName -eq 'Windows 11 Eligible'}
                    if($null -ne $NCDeviceServices.data -and $null -eq $service){
                        $service = $NCDeviceServices.data|?{$_.moduleName -eq 'Windows 11 Eligible'}
                    }

                    $eligibleNC = $(if($service.stateStatus -eq 'Normal'){'true'} elseif($service.stateStatus -eq 'Failed'){'false'} else {''})

                    if($eligibleNC -eq 'true' -or $eligibleNC -eq 'false' -and $eligibleAT -ne 'true'){
                        $body.userDefinedFields.add([pscustomobject]@{"name" = "OS Upgrade Eligible"; "value" = $eligibleNC})|Out-Null
                    }
                }

                $q = Set-AutotaskAPIResource -Resource ConfigurationItemExts -ID $ATDevice.id -body $body
            }
            catch {
                Write-Host "Meh $($ATDevice.referenceTitle) failed to get NCentral details."
            }
        }

        Write-LogMessage -user "CIPP" -API $APIName -tenant "None" -Message "Updated $($ATDevices.Count) devices" -Sev "Info"
        return "Updated $($ATDevices.Count) devices"
    } catch {
        Write-LogMessage -user "CIPP" -API $APINAME -tenant "None" -message "Failed to set PSA Asset Detail. Error:$($_.Exception.Message)" -Sev 'Error'
        throw "Failed to set alias: $($_.Exception.Message)"
    }
}


##TODO##MOVE TO NCentral Extension dir
function Get-NCentralJWT {
    if (!$ENV:NCentralJWT) {
        $null = Connect-AzAccount -Identity
        $ClientSecret = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'NCentral' -AsPlainText)
    } else {
        $ClientSecret = $ENV:NCentralJWT
    }

    #Write-LogMessage -user "CIPP" -API $APIName -tenant "None" -Message "Got NCentral api key $($ClientSecret.substring(0,5))..."  -Sev "Info"
    return $ClientSecret
}
