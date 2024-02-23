function Set-IronScalesMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request
    )

    foreach ($Mapping in ([pscustomobject]$Request.body.mappings).psobject.properties) {
        $Filter = "PartitionKey eq 'Mapping' and RowKey eq '$($mapping.name)'"
        $res = Get-CIPPAzDataTableEntity @CIPPMapping -Filter $Filter
        if($null -ne $res){
            Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Updated mapping for $($mapping.name)." -Sev 'Info' 
            Update-AzDataTableEntity @CIPPMapping -Entity @{
                PartitionKey        = $res.PartitionKey
                RowKey              = $res.RowKey
                'IronScalesName'    = "$($Mapping.value.label)"
                'IronScalesId'      = "$($Mapping.value.value)"
            }
        }
        else {
            Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Added mapping for $($mapping.name)." -Sev 'Info' 

            $AddObject = @{
                PartitionKey  = 'Mapping'
                RowKey        = "$($mapping.name)"
                'IronScalesId'     = "$($mapping.value.value)"
                'IronScalesName' = "$($mapping.value.label)"
            }
        
            Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        }
    }
    $Result = [pscustomobject]@{'Results' = "Successfully edited mapping table." }

    Return $Result
}