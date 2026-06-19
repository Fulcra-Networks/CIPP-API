using namespace System.Net

function Invoke-ListPSABillingCodes {
    [CmdletBinding()]
    param($Request,$TriggerMetadata)

    $billingCodes = Get-AutotaskBillingCodes

    return ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @($billingCodes)
    })
}
