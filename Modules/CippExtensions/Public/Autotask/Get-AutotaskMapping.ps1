function Get-AutotaskMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )
    #Get available mappings
    $Mappings = [pscustomobject]@{}


    try{
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

    $RawAutotaskCustomers = Get-AutotaskCompanies

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
catch {
    Write-Host "Exception $($_.Exception.Message)"
}
}
