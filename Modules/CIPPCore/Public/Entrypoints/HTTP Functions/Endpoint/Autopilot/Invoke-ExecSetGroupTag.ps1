using namespace System.Net

Function Invoke-ExecSetGroupTag {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $tenantfilter = $Request.Body.TenantFilter
    try {
        $body = @{
            groupTag = $Request.body.input
        } | ConvertTo-Json
        New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($request.body.Device)/UpdateDeviceProperties" -tenantid $TenantFilter -body $body -method POST
        $Results = "Successfully assigned group tag $($Request.body.input) to $($Request.body.device) for $($tenantfilter)"
    } catch {
        $Results = "Could not assign group tag $($Request.body.input) to $($Request.body.device) for $($tenantfilter) Error: $($_.Exception.Message)"
    }

    $Results = [pscustomobject]@{'Results' = "$results" }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
