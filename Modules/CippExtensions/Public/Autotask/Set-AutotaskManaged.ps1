function Set-AutotaskManaged {
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request
    )

    
    $Table = Get-CippTable -tablename 'CippMapping'

    Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message $(ConvertTo-Json $Request.body -Depth 10) -Sev Debug

    foreach ($Mapping in ([pscustomobject]$Request.body).psobject.properties) {        
        $Filter = "PartitionKey eq 'Mapping' and RowKey eq '$($mapping.name)'"
        $res = Get-CIPPAzDataTableEntity @CIPPMapping -Filter $Filter

        Update-AzDataTableEntity @Table -Entity @{
            PartitionKey = $res.PartitionKey
            RowKey       = $res.RowKey
            'IsManaged'  = [bool]$mapping.value
        }

        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Updated 'IsManaged' mapping for $($mapping.name)." -Sev 'Info' 
    }
    $Result = [pscustomobject]@{'Results' = "Successfully edited mapping table." }

    Return $Result
}