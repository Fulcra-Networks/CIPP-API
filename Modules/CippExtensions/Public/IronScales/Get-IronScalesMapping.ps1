function Get-IronScalesMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    #Get available mappings
    $Mappings = [pscustomobject]@{}
    $Tenants = Get-Tenants -IncludeErrors

    $ExtensionMappings = Get-ExtensionMapping -Extension 'IronScales'
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

        Write-LogMessage -Message "Could not get IronScales Companies error: $Message " -sev Error -tenant 'CIPP' -API 'IronScalesMapping'
        $RawCompanies = @(@{name = "Could not get IronScales Companies, error: $Message" })
    }

    $IronScalesCompanies = $RawCompanies | Sort-Object -Property name  | ForEach-Object {
        [PSCustomObject]@{
            name  = $_.name
            value = "$($_.id)"
        }
    }

    $MappingObj = [PSCustomObject]@{
        Companies   = @($IronScalesCompanies)
        Mappings    = @($Mappings)
    }

    return $MappingObj
}
