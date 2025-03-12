Function Get-NCentralDevices {
    [CmdletBinding()]
    param($tenantId)

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).NCentral

    $ExtensionMappings = Get-ExtensionMapping -Extension 'NCentral'

    $ncJWT = Get-NCentralJWT
    Connect-Ncentral -ApiHost $Configuration.ApiHost -key ($ncJWT|ConvertTo-SecureString -AsPlainText -Force)

    $customerId = $ExtensionMappings | Where-Object { $_.rowKey -eq $tenantId }
    $custDevices = Get-NCentralDevice -CustomerId $customerId.IntegrationId

    #$devDetails[0].data.computersystem.serialnumber
    $results = @()
    foreach($device in ($custDevices | Where-Object {$_.deviceClass -ne 'Other'})){
        $DevDetail = Get-NCentralDeviceDetail -DeviceId $device.deviceId
        $fDetail = [PSCustomObject]@{
            Id = $device.deviceId
            name = $device.longName
            serialNumber = $DevDetail.data.computersystem.serialnumber
        }
        $results += $fDetail
    }

    return $results
}
