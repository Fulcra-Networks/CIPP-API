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
        Write-LogMessage -Message "Get NCentral token ($($ncJWT.substring(0,6)))" -Level Info -tenant 'CIPP' -API 'NCentralMapping'

        Connect-Ncentral -ApiHost $Configuration.ApiHost -key ($ncJWT|ConvertTo-SecureString -AsPlainText -Force)

        $rawcustomers = Get-NCentralCustomer -All
        Write-LogMessage -Message "Get NCentral customers ($($rawcustomers.count))" -Level Info -tenant 'CIPP' -API 'NCentralMapping'
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }
        Write-LogMessage -Message "Could not get NCentral customers, error: $Message " -Level Error -tenant 'CIPP' -API 'NCentralMapping'
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

    return $MappingObj
}
