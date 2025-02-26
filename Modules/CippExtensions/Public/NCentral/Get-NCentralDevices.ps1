Function Get-NCentralDevices {
    [CmdletBinding()]
    param($tenantId)

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).NCentral

    $ExtensionMappings = Get-ExtensionMapping -Extension 'NCentral'
}
