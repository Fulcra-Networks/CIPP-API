using namespace System.Net

Function Invoke-ExecAssetManagement {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try{
        $TenantFilter = $Request.Query.TenantFilter
        if ($Request.Query.TenantFilter -eq 'AllTenants') {
            write-host "$('~'*60)>"
            $body = 'All tenants not supported.'
        }
        elseif([String]::IsNullOrEmpty($TenantFilter)){
            write-host "$('~'*60)>"
            $body = 'Empty tenant filter not supported.'
        }
        else {
            $TblTenant = Get-CIPPTable -TableName Tenants
            $Tenants = Get-CIPPAzDataTableEntity @TblTenant -Filter "PartitionKey eq 'Tenants'"

            $tenantId = $Tenants | Where-Object { $_.defaultDomainName -eq $TenantFilter } | Select-Object -ExpandProperty RowKey


            $TablePSA = Get-CIPPTable -TableName AssetsPSA
            $PSACanaryRow = Get-CIPPAzDataTableEntity @TablePSA -Filter "PartitionKey eq '$tenantId'" -First 1

            if($null -eq $PSACanaryRow -or $PSACanaryRow.LastRefresh -lt [datetime]::UtcNow.AddHours(-12)) {
                write-host "$('~'*60)> PSA Data Stale. Updating."
                Set-AssetManagementData -tenantFilter $TenantFilter
            }

            $AssetsPSA = Get-CIPPAzDataTableEntity @TablePSA -Filter "PartitionKey eq '$tenantId'"

            $TableRMM = Get-CIPPTable -TableName AssetsRMM
            $RMMCanaryRow = Get-CIPPAzDataTableEntity @TableRMM -Filter "PartitionKey eq '$tenantId'" -First 1

            if($null -eq $RMMCanaryRow -or $RMMCanaryRow.LastRefresh -lt [datetime]::UtcNow.AddHours(-12)) {
                write-host "$('~'*60)> RMM Data Stale. Updating."
                Set-AssetManagementData -tenantFilter $TenantFilter
            }

            $AssetsRMM = Get-CIPPAzDataTableEntity @TableRMM -Filter "PartitionKey eq '$tenantId'"

            try {
                $IntuneDevsRAW = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices' -Tenantid $tenantId
                #consolidate properties into list expected by table columns
                $IntuneDevs = $IntuneDevsRAW|ForEach-Object {
                    [PSCustomObject]@{
                        Name            = $_.deviceName
                        SerialNumber    = $_.hardwareInformation.serialNumber
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -sev error -API 'AssetManagement' -message $ErrorMessage
                $IntuneDevs = @()
            }


            $body = [PSCustomObject]@{
                assetsPSA = @($AssetsPSA)
                assetsRMM = @($AssetsRMM)
                assetsINT = @($IntuneDevs)
            }
        }

        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
    }
    catch{
        Write-LogMessage -sev Error -API "ExecAssetManagement" -message "Error getting asset management data. $($_.Exception.Message)"
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = $body
        })
    }
}
