function Set-AutotaskMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request
    )

    foreach ($Mapping in ([pscustomobject]$Request.body.mappings).psobject.properties) {
        Write-Host $(ConvertTo-Json $Mapping)
        $AddObject = @{
            PartitionKey  = 'Mapping'
            RowKey        = "$($mapping.name)"
            'AutotaskPSA'     = "$($mapping.value.value)"
            'AutotaskPSAName' = "$($mapping.value.label)"
        }

        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force

        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Added mapping for $($mapping.name)." -Sev 'Info' 
    }
    $Result = [pscustomobject]@{'Results' = "Successfully edited mapping table." }

    Return $Result
}