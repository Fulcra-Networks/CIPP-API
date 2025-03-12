using namespace System.Net

Function Invoke-ExecAssetManagement {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.TenantFilter
    if ($Request.Query.TenantFilter -eq 'AllTenants') {
        return 'Not Supported'
    }

    $TblTenant = Get-CIPPTable -TableName Tenants
    $Tenants = Get-CIPPAzDataTableEntity @TblTenant -Filter "PartitionKey eq 'Tenants'"

    $tenantId = $Tenants | Where-Object { $_.defaultDomainName -eq $TenantFilter } | Select-Object -ExpandProperty RowKey

    $Table = Get-CIPPTable -TableName Extensionsconfig
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
            $PSADevices = Get-AutotaskDevices -tenantId $tenantId
        }
        'HaloPSA' {
            $PSADevices = @()
        }
    }

    Switch ($cfgRMM.Name) {
        'NCentral' {
            $RMMDevices = Get-NCentralDevices -tenantId $tenantId
        }
        'NinjaOne' {
            $RMMDevices = @()
        }
    }

    #Now create a merged list of devices
    $MatchedDevices = @()
    $UnmatchedPSADevices = @()
    $UnmatchedRMMDevices = @()

    Write-Host "$('-'*20)> Got $($RMMDevices.Count) RMM Devices and $($PSADevices.Count) PSA Devices"
    foreach($PSADevice in $PSADevices){
        if($RMMDevice = $RMMDevices | Where-Object { $_.Id -eq $PSADevice.rmmId }){
            $MatchedDevices += [PSCustomObject]@{
                Name            = $PSADevice.Name
                Contract        = $PSADevice.Contract
                SerialNumber    = $PSADevice.SerialNumber
                RMMId           = $PSADevice.RMMId
                RMMName         = $RMMDevice.name
            }
        }
        else {
            $UnmatchedPSADevices += [PSCustomObject]@{
                Name            = $PSADevice.Name
                Contract        = $PSADevice.Contract
                SerialNumber    = $PSADevice.SerialNumber
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

    Write-Host "$($body|ConvertTo-json -depth 10)"

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
