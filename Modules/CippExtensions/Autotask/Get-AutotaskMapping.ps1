function Get-AutotaskMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )
    #Get available mappings
    $Mappings = [pscustomobject]@{}
    
    $Filter = "PartitionKey eq 'Mapping'"
    Get-CIPPAzDataTableEntity @CIPPMapping -Filter $Filter | ForEach-Object {
        if($null -ne $_.AutotaskPSAName -and "" -ne $_.AutotaskPSAName){
            $Mappings | Add-Member -NotePropertyName $_.RowKey -NotePropertyValue @{ label = "$($_.AutotaskPSAName)"; value = "$($_.AutotaskPSA)" }
        }
    }
    
    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).Autotask
        
        Get-AutotaskToken -configuration $Configuration | Out-Null
        $RawAutotaskCustomers = Get-AutotaskAPIResource -Resource Companies -SearchQuery "{'filter':[{'op':'and',items:[{'op':'eq','field':'isactive','value':true},{'op':'eq','field':'companyType','value':'1'}]}]}"
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }
        
        Write-LogMessage -Message "Could not get Autotask Clients, error: $Message " -Level Error -tenant 'CIPP' -API 'AutotaskMapping'
        $RawAutotaskCustomers = @(@{name = "Could not get Autotask Clients, error: $Message" }) 
    }
    
    $AutotaskCustomers = $RawAutotaskCustomers | Sort-Object -Property companyName | ForEach-Object {
        [PSCustomObject]@{
            name  = $_.companyName
            value = "$($_.id)"
        }
    }
    
    $Tenants = Get-Tenants -IncludeErrors

    $MappingObj = [PSCustomObject]@{
        Tenants           = @($Tenants)
        AutotaskCustomers = @($AutotaskCustomers)
        Mappings          = $Mappings
    }
    
    return $MappingObj
}