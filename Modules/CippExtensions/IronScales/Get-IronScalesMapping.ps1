function Get-IronScalesMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )
    #Get available mappings
    $Mappings = [pscustomobject]@{}
    
    $Filter = "PartitionKey eq 'Mapping'"
    Get-CIPPAzDataTableEntity @CIPPMapping -Filter $Filter | ForEach-Object {
        if($null -ne $_.IronScalesName -and "" -ne $_.IronScalesName){
            $Mappings | Add-Member -NotePropertyName $_.RowKey -NotePropertyValue @{ label = "$($_.IronScalesName)"; value = "$($_.IronScalesId)" }
        }
    }
    
    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).IronScales
        
        $JWT = Get-IronScalesToken -configuration $configuration
        $reqargs = @{ Uri = "$($Configuration.apiHost+"/company/list/")"; Headers = @{ Authorization = "Bearer $($JWT)"; }}
        $resp = Invoke-RestMethod @reqargs
        $RawCompanies = $resp.companies
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }
        
        Write-LogMessage -Message "Could not get IronScales Companies error: $Message " -Level Error -tenant 'CIPP' -API 'IronScalesMapping'
        $RawCompanies = @(@{name = "Could not get IronScales Companies, error: $Message" }) 
    }
    
    $IronScalesCompanies = $RawCompanies | Sort-Object -Property name  | ForEach-Object {
        [PSCustomObject]@{
            name  = $_.name
            value = "$($_.id)"
        }
    }
    
    $Tenants = Get-Tenants
    
    $MappingObj = [PSCustomObject]@{
        Tenants             = @($Tenants)
        IronScalesCompanies = @($IronScalesCompanies)
        Mappings            = $Mappings
    }
    
    return $MappingObj
}