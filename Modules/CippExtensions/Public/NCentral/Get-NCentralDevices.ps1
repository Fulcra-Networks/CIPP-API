Function Get-NCentralDevices {
    [CmdletBinding()]
    param($tenantId)

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).NCentral

    $ExtensionMappings = Get-ExtensionMapping -Extension 'NCentral'

    $ncJWT = Get-NCentralJWT
    Connect-Ncentral -ApiHost $Configuration.ApiHost -key ($ncJWT|ConvertTo-SecureString -AsPlainText -Force)

    $customerId = $ExtensionMappings | Where-Object { $_.rowKey -eq $tenantId }
    $RawDevices = Get-NCentralDevice -CustomerId $customerId.IntegrationId

    $results = $RawDevices | Sort-Object -Property name | ForEach-Object {
        [PSCustomObject]@{
            Id           = $_.deviceId
            name         = $_.longName
            serialNumber = ''
        }
    }

    return $results
}
