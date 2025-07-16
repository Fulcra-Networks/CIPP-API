using namespace System.Net

<#
    - Fetch+Store Devices from PSA
    - Fetch+Store Devices from RMM
    Provides tables which the UI will quickly be able to query.
    No matching will be performed on this end.

    Maybe query for PSA duplicate SN where RMM device exists?
#>

Function Set-AssetManagementData {
    [CmdletBinding()]
    param(
        $TenantFilter,
        $APIName = 'Set PSA Asset Detail'
    )

    if($TenantFilter -eq 'AllTenants') {
        return "Cannot run job for all Tenants."
    }

    write-host "$('~'*60)> 1"
    $TblTenant = Get-CIPPTable -TableName Tenants
    $Tenants = Get-CIPPAzDataTableEntity @TblTenant -Filter "PartitionKey eq 'Tenants'"

    $tenantId = $Tenants | Where-Object { $_.defaultDomainName -eq $TenantFilter } | Select-Object -ExpandProperty RowKey
    write-host "$('~'*60)> 2"
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10

    $cfgPSA = Get-PSAConfig $Configuration
    if(!$cfgPSA){
        Write-LogMessage -API 'Set-AssetManagementData' -message 'No PSA configured.' -sev Info
        return 'No PSA Configured'
    }

    $cfgRMM = Get-RMMConfig $Configuration
    if(!$cfgRMM){
        Write-LogMessage -API 'Set-AssetManagementData' -message 'No RMM configured.' -sev Info
        return 'No RMM Configured'
    }

    <#Expected object format
        [string]name, [string]serial, [int]psaId, [int]rmmId, [string]contract
    #>
    write-host "$('~'*60)> 3"
    Switch ($cfgPSA.Name) {
        'Autotask' {
            UpdateAutoTaskDevices $tenantId
        }
        'HaloPSA' {
            $PSADevices = @()
        }
    }

    write-host "$('~'*60)> 4"
    Switch ($cfgRMM.Name) {
        'NCentral' {
            UpdateNCentralDevices $tenantId
        }
        'NinjaOne' {
            $RMMDevices = @()
        }
    }
}

Function UpdateAutoTaskDevices {
    param($tenantId)

    $PSADevices = Get-AutotaskDevices -tenantId $tenantId

    $Table = Get-CIPPTable -TableName AssetsPSA
    # if($existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($tenantId)'") {
    #     write-host "$('~'*60)> Removing expired PSA asset entities."
    #     $existing | ForEach-Object {
    #         Remove-AzDataTableEntity -Force @Table -Entity $_
    #     }
    # }

    foreach($device in $PSADevices){
        $addObject = [PSCustomObject]@{
            PartitionKey    = [string]$tenantId
            RowKey          = "AutoTask-$($device.psaId)"
            LastRefresh     = [datetime]::UtcNow
            Name            = [string]$device.name
            Contract        = [string]$device.contract
            SerialNumber    = [string]$device.serialNumber
            Id              = [string]$device.psaId
        }

        Add-CIPPAzDataTableEntity @Table -Entity $AddObject -Force
    }
}

Function UpdateNCentralDevices {
    param($tenantId)

    $RMMDevices = Get-NCentralDevices -tenantId $tenantId

    $Table = Get-CIPPTable -TableName AssetsRMM
    # if($existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($tenantId)'") {
    #     $existing | ForEach-Object {
    #         write-host "$('~'*60)> Removing expired RMM asset entities."
    #         Remove-AzDataTableEntity -Force @Table -Entity $_
    #     }
    # }

    foreach($RMMDevice in $RMMDevices){
        $addObject = [PSCustomObject]@{
            PartitionKey    = [string]$tenantId
            RowKey          = "NCentral-$($RMMDevice.Id)"
            LastRefresh     = [datetime]::UtcNow
            Name            = $RMMDevice.Name
            SerialNumber    = $RMMDevice.SerialNumber
            Id              = $RMMDevice.Id
        }

        Add-CIPPAzDataTableEntity @Table -Entity $AddObject -Force
    }
}

Function Get-PSAConfig {
    param($Configuration)

    if($PSAConfig = $Configuration.Autotask){
        return [PSCustomObject]@{
            Name = 'Autotask'
            Config = $PSAConfig
        }
    }
    elseif($PSAConfig = $Configuration.HaloPSA){
        return [PSCustomObject]@{
            Name = 'HaloPSA'
            Config = $PSAConfig
        }
    }
    return $null
}

Function Get-RMMConfig {
    param($Configuration)

    if($RMMConfig = $Configuration.NinjaOne){
        return [PSCustomObject]@{
            Name = 'NinjaOne'
            Config = $RMMConfig
        }
    }
    elseif($RMMConfig = $Configuration.NCentral){
        return [PSCustomObject]@{
            Name = 'NCentral'
            Config = $RMMConfig
        }
    }
    return $null
}


<# Old Matching Code

    $MatchedDevices = @()
    $UnmatchedPSADevices = @()
    $UnmatchedRMMDevices = @()

    foreach($PSADevice in $PSADevices){
        if($RMMDevice = $RMMDevices | Where-Object { $_.Id -eq $PSADevice.rmmId }){
            $MatchedDevices += [PSCustomObject]@{
                Name            = $PSADevice.name
                Contract        = $PSADevice.contract
                SerialNumber    = $PSADevice.serialNumber
                PSAId           = $PSADevice.psaId
                RMMId           = $PSADevice.rmmId
                RMMName         = $RMMDevice.name
            }
        }
        else {
            $UnmatchedPSADevices += [PSCustomObject]@{
                Name            = $PSADevice.name
                Contract        = $PSADevice.contract
                SerialNumber    = $PSADevice.serialNumber
                PSAId           = $PSADevice.psaId
                RMMId           = $PSADevice.rmmId
                RMMName         = $null
            }
        }
    }

    foreach($RMMDevice in $RMMDevices){
        if($PSADevice = $PSADevices | Where-Object { $_.RMMId -eq $RMMDevice.Id }){
            continue
        }
        else {
            $UnmatchedRMMDevices += [PSCustomObject]@{
                Name             = $RMMDevice.Name
                Contract         = ""
                SerialNumber     = $RMMDevice.SerialNumber
                RMMId            = $RMMDevice.Id
                RMMName          = $RMMDevice.name
            }
        }
    }


    $body = [PSCustomObject]@{
        MatchedDevices      = @($MatchedDevices)
        UnmatchedPSADevices = @($UnmatchedPSADevices)
        UnmatchedRMMDevices = @($UnmatchedRMMDevices)
    }

    $AddObject = @{
        PartitionKey    = [string]$tenantId
        RowKey          = [string]$cfgPSA.Name
        AssetData      =  [string]($body|ConvertTo-Json -Depth 10 -Compress)
    }

    $Table = Get-CIPPTable -TableName PSAAssetManagement
    Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($tenantId)'" | ForEach-Object {
        Remove-AzDataTableEntity -Force @Table -Entity $_
    }

    Add-CIPPAzDataTableEntity @Table -Entity $AddObject -Force
#>
