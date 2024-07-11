function Get-AutotaskManaged {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )
    
    $Filter = "PartitionKey eq 'Mapping'"
    
    
    $managed = Get-CIPPAzDataTableEntity @CIPPMapping -Filter $Filter | ForEach-Object {
        if($null -ne $_.AutotaskPSAName -and "" -ne $_.AutotaskPSAName){
            [PSCustomObject]@{
                name  = "$($_.RowKey)"
                label = "$($_.AutotaskPSAName)"
                value = [bool](Get-ManagedState $_)
                aid   = "$($_.AutotaskPSA)"
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