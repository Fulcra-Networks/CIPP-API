using namespace System.Net

function Invoke-ListPSABillingCodes {
    [CmdletBinding()]
    param($Request,$TriggerMetadata)

    $billingCodes = Get-AutotaskBillingCodes

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @($billingCodes)
    })
}
