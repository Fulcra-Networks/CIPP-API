
function Get-CIPPTenantCapabilities {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Get Tenant Capabilities',
        $Headers
    )


    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Getting Tenant Capabilities: $TenantFilter)" -sev Info

    $Org = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter
    $Plans = $Org.servicePlans | Where-Object { $_.provisioningStatus -eq 'Success' } | Sort-Object -Property serviceplanName -Unique | Select-Object servicePlanName, provisioningStatus
    $Results = @{}
    foreach ($Plan in $Plans) {
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Tenant Capability: $($Plan.servicePlanName)-$($Plan.provisioningStatus))" -sev Info
        $Results."$($Plan.servicePlanName)" = $Plan.provisioningStatus -eq 'Success'
    }
    [PSCustomObject]$Results
}
