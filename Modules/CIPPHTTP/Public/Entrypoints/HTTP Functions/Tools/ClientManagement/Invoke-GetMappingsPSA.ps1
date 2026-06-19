using namespace System.Net


function Invoke-GetMappingsPSA {
    param($request, $TriggerMetadata)


    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10

    $extName = Get-PSAConfig $Configuration


    $ExtensionMappings = Get-ExtensionMapping -Extension $extName.Name
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

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Mappings
        })
}
