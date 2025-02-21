function Get-AutotaskMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )
    #Get available mappings
    $Mappings = [pscustomobject]@{}

    # Migrate legacy mappings
    $Filter = "PartitionKey eq 'Mapping'"
    $MigrateRows = Get-CIPPAzDataTableEntity @CIPPMapping -Filter $Filter | ForEach-Object {
        [PSCustomObject]@{
            PartitionKey    = 'AutotaskMapping'
            RowKey          = $_.RowKey
            IntegrationId   = $_.AutotaskPSA
            IntegrationName = $_.AutotaskPSAName
        }
        Remove-AzDataTableEntity -Force @CIPPMapping -Entity $_ | Out-Null
    }
    if (($MigrateRows | Measure-Object).Count -gt 0) {
        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $MigrateRows -Force
    }

    $ExtensionMappings = Get-ExtensionMapping -Extension 'Autotask'
    $Tenants = Get-Tenants -IncludeErrors

    $Mappings = foreach ($Mapping in $ExtensionMappings) {
        $Tenant = $Tenants | Where-Object { $_.RowKey -eq $Mapping.RowKey }
        if ($Tenant) {
            [PSCustomObject]@{
                TenantId        = $Tenant.customerId
                Tenant          = $Tenant.displayName
                TenantDomain    = $Tenant.defaultDomainName
                IntegrationId   = $Mapping.IntegrationId
                IntegrationName = $Mapping.IntegrationName
            }
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

    $MappingObj = [PSCustomObject]@{
        Companies   = @($AutotaskCustomers)
        Mappings    = $Mappings
    }

    return $MappingObj
}
