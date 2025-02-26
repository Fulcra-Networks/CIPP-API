using namespace System.Net

Function Invoke-ExecAssetManagement {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.TenantFilter
    if ($Request.Query.TenantFilter -eq 'AllTenants') {
        return 'Not Supported'
    }
    Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10

    $cfgPSA = Get-PSAConfig $Configuration
    if(!$cfgPSA){
        return 'No PSA Configured'
    }
    $cfgRMM = Get-RMMConfig $Configuration
    if(!$cfgPSA){
        return 'No PSA Configured'
    }

    Switch ($cfgPSA.Name) {
        'Autotask' {
            $PSADevices = Get-AutotaskDevices -tenantId $TenantFilter
        }
        'HaloPSA' {
            $PSADevices = @()
        }
    }

    Switch ($cfgRMM.Name) {
        'NCentral' {
            $RMMDevices = Get-NCentralDevices -tenantId $TenantFilter
        }
        'NinjaOne' {
            $RMMDevices = @()
        }
    }

    #Now create a merged list of devices
    $MatchedDevices = @()
    $UnmatchedPSADevices = @()
    $UnmatchedRMMDevices = @()

    foreach($PSADevice in $PSADevices){
        if($RMMDevice = $RMMDevices | Where-Object { $_.Id -eq $PSADevice.rmmId }){
            $MatchedDevices += [PSCustomObject]@{
                Name = $PSADevice.Name
                SerialNumber = $PSADevice.SerialNumber
                RMMId = $PSADevice.RMMId
                RMMName= $RMMDevice.name
            }
        }
        else {
            $UnmatchedPSADevices += [PSCustomObject]@{
                Name = $PSADevice.Name
                SerialNumber = $PSADevice.SerialNumber
                RMMId = $null
                RMMName= $null
            }
        }
    }

    foreach($RMMDevice in $RMMDevices){
        if($PSADevice = $PSADevices | Where-Object { $_.RMMId -eq $RMMDevice.Id }){
            continue
        }
        else {
            $UnmatchedRMMDevices += [PSCustomObject]@{
                Name = $RMMDevice.Name
                SerialNumber = $RMMDevice.SerialNumber
                RMMId = $RMMDevice.Id
                RMMName= $RMMDevice.name
            }
        }
    }


    $body = [PSCustomObject]@{
        MatchedDevices      = @($MatchedDevices)
        UnmatchedPSADevices = @($UnmatchedPSADevices)
        UnmatchedRMMDevices = @($UnmatchedRMMDevices)
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
}

Function Get-PSAConfig {
    param($Configuration)

    if($PSAconfig = $Configuration.Autotask){
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
