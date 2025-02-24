function Set-IronScalesMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request
    )

    Get-CIPPAzDataTableEntity @CIPPMapping -Filter "PartitionKey eq 'IronScalesMapping'" | ForEach-Object {
        Remove-AzDataTableEntity -Force @CIPPMapping -Entity $_
    }

    foreach ($Mapping in $Request.Body) {
        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Added mapping for $($mapping.name)." -Sev 'Info'

        $AddObject = @{
            PartitionKey    = 'IronScalesMapping'
            RowKey          = "$($mapping.TenantId)"
            IntegrationId   = "$($mapping.IntegrationId)"
            IntegrationName = "$($mapping.IntegrationName)"
        }

        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force
    }
    $Result = [pscustomobject]@{'Results' = "Successfully edited mapping table." }

    Return $Result
}
