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

    $RawAutotaskCustomers = Invoke-GetAutotaskCompanies

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

    Write-LogMessage -Message "Returning Mapping Data: $($MappingObj|ConvertTo-Json -Depth 10 -Compress)" -sev Info -tenant 'CIPP' -API 'AutotaskMapping'
    return $MappingObj
}
