function Get-AutotaskManaged {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    $Filter = "PartitionKey eq 'AutotaskMapping'"


    $managed = Get-CIPPAzDataTableEntity @CIPPMapping -Filter $Filter | ForEach-Object {
        if(![String]::IsNullOrEmpty($_.IntegrationName)){
            [PSCustomObject]@{
                name  = "$($_.RowKey)"
                label = "$($_.IntegrationName)"
                value = [bool](Get-ManagedState $_)
                aid   = "$($_.IntegrationId)"
            }
        }
    }

    $MappingObj = [PSCustomObject]@{
        ManagedCusts = @($managed)
    }

    return $MappingObj
}


function Get-ManagedState {
    param($Mapping)
    if($null -eq $Mapping.IsManaged){return $false}
    return [bool]::Parse($Mapping.IsManaged)
}
