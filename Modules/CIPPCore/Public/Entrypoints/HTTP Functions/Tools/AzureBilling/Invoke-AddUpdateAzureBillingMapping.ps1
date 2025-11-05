using namespace System.Net;

function Invoke-AddUpdateAzureBillingMapping {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-Host "$('*'*60) $($Request|ConvertTo-JSON -Depth 10)"

    $resp =  ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @("OK")
        })
    return $resp
}
