<#
    This command as of now, will connect to the configured PSA (Autotask for now) and retrieve all active assets.
    After retrieving the list of assets it will query the configured N-Central RMM and retrieve all matching devices,
    then update the PSA assets that are found, with N-Central asset CPU and RAM detail.
#>
function Set-PSAAssetDetail {
    [CmdletBinding()]
    param (
        $APIName = 'Set PSA Asset Detail'
    )

    $MappingTable = Get-CIPPTable -TableName CippMapping
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10

    try {
        $managedCompanies = Get-AutotaskManaged -CIPPMapping $MappingTable
        Write-LogMessage -user "CIPP" -API $APIName -tenant "None" -Message "Got $($managedCompanies.ManagedCusts.Count) managed companies."  -Sev "Info"

        #Get all AT Configuration Items of type workstation, that are active, that have the "N-central Device ID [UDF]" property set, and Managed
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
                                "op": "in",
                                "field": "companyID",
                                "value": $($managedCompanies.ManagedCusts|Select-Object -ExpandProperty aid|% {$_ -as [int]}|ConvertTo-Json)
                            }
                        ]
                    }
            ]}
"@

        Get-AutotaskToken -configuration $Configuration.Autotask
        #Write-LogMessage -user "CIPP" -API $APIName -tenant "None" -Message "Connected to Autotask API."  -Sev "Info"
        $ncJWT = Get-NCentralJWT
        New-NCentralConnection -ServerFQDN $Configuration.NCentral.ApiHost -JWT $ncJWT
        #Write-LogMessage -user "CIPP" -API $APIName -tenant "None" -Message "Connected to N-Central."  -Sev "Info"

        $ATDevices = Get-AutotaskAPIResource -Resource ConfigurationItems -SearchQuery $query
        Write-LogMessage -user "CIPP" -API $APIName -tenant "None" -Message "Got $($ATDevices.Count) Autotask devices."  -Sev "Info"

        foreach ($ATDevice in $ATDevices){
            #get the NC device info using the "N-central Device ID [UDF]""
            $i = [array]::indexof($ATDevice.userDefinedFields.name, "N-central Device ID")
            $NCid = $ATDevice.userDefinedFields[$i].value
            #update the AT configuration item
            #$NCDevice = Get-NCDeviceID "TNS-HYPERV1" | Get-NCDeviceObject
            $NCDevice = Get-NCDeviceObject $NCid

            Write-LogMessage -user "CIPP" -API $APIName -tenant "None" -Message "Updating $($ATDevices.IndexOf($ATDevice)+1)/$($ATDevices.Count)"  -Sev "Info"

            $body = [PSCustomObject]@{
                userDefinedFields = @(
                    [pscustomobject]@{"name" = "RAM"; "value" = "$([math]::Round($NCDevice.computersystem.totalphysicalmemory/([Math]::Pow(1024,3))))GB"};
                    [pscustomobject]@{"name" = "CPU"; "value" =  "$($NCDevice.processor.name) (x$($NCDevice.processor.numberofcpus))"};
                    [pscustomobject]@{"name" = "Last Boot Time"; "value" = "$($NCDevice.os.lastbootuptime)"};
                    [pscustomobject]@{"name" = "OS"; "value" = $NCDevice.os.reportedos};
                    [pscustomobject]@{"name" = "OS Architecture"; "value" = $NCDevice.os.osarchitecture};
                    [pscustomobject]@{"name" = "Version"; "value" = $NCDevice.os.version}
                )
            }

            $q = Set-AutotaskAPIResource -Resource ConfigurationItemExts -ID $ATDevice.id -body $body
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

    Write-LogMessage -user "CIPP" -API $APIName -tenant "None" -Message "Got NCentral api key $($ClientSecret.substring(0,5))..."  -Sev "Info"
    return $ClientSecret
}
