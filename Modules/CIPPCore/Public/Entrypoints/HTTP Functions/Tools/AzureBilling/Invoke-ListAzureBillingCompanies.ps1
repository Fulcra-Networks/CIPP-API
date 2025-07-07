using namespace System.Net

function Invoke-ListAzureBillingCompanies {
    [CmdletBinding()]
    param($Request,$TriggerMetadata)

    write-host "$('*'*60) Getting Azure companies...."
    $companies = Get-AzureBillingCompanies

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @($companies)
    })
}
