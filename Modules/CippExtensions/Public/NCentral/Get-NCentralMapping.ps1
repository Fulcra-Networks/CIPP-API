function Get-NCentralMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )
    #Get available mappings
    $Mappings = [pscustomobject]@{}

    $ExtensionMappings = Get-ExtensionMapping -Extension 'NCentral'
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
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).NCentral

        #Get NCentral customer list
        $ncJWT = Get-NCentralJWT

        Connect-Ncentral -ApiHost $Configuration.ApiHost -key ($ncJWT|ConvertTo-SecureString -AsPlainText -Force)

        $rawcustomers = Get-NCentralCustomer -All
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }
        Write-LogMessage -Message "Could not get NCentral customers, error: $Message " -sev Error -tenant 'CIPP' -API 'NCentralMapping'
        $rawcustomers = @(@{customerName = "Could not get NCentral Clients, error: $Message"; customerId = 0})
    }

    $NCentralCustomers = $rawcustomers | Sort-Object -Property companyName | ForEach-Object {
        [PSCustomObject]@{
            name  = $_.customerName
            value = "$($_.customerId)"
        }
    }

    $MappingObj = [PSCustomObject]@{
        Companies   = @($NCentralCustomers)
        Mappings    = $Mappings
    }

    Write-LogMessage -Message "Returning Mapping Data: $($MappingObj|ConvertTo-Json -Depth 10 -Compress)" -sev Info -tenant 'CIPP' -API 'NCentralMapping'
    return $MappingObj
}
