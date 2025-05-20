using namespace System.Net

function Invoke-ExecGetSentAzureCharges {
    [CmdletBinding()]
    param($request,$TriggerMetadata)

    $SentChargesTable = Get-CIPPTable -TableName AzureBillingChargesSent

    if(-not [string]::IsNullOrEmpty($request.Body.datetime)){
        $billingDate = (Get-Date 01.01.1970)+([System.TimeSpan]::fromseconds($Request.Body.datetime))
        $billingDate = [DateTime]::New($billingDate.Year, $billingDate.Month, 28)

    }
    else{
        $pMonth = [DateTime]::Now.AddMonths(-1)
        $billingDate = [DateTime]::New($pMonth.Year,$pMonth.Month,28)
    }

    $Filter = "PartitionKey eq '$($billingDate.ToString("yyyy-MM"))'"
    $existingData = Get-CIPPAzDataTableEntity @SentChargesTable -filter $Filter

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = @($existingData)
    })
}
