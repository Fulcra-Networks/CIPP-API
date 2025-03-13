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

    #TODO: Move this to property mapping/extension config.
    #This improves performance by removing non-managed systems (servers/printers/network equipment etc.)
    $custDevices = $custDevices | Where-Object {$_.deviceClass -in @('Laptop - Windows','Workstations - Windows')}

    $results = @()
    foreach($device in $custDevices){
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
