using namespace System.Net

function Invoke-ExecGetSentAzureCharges {
    [CmdletBinding()]
    param($request,$TriggerMetadata)

    $SentChargesTable = Get-CIPPTable -TableName AzureBillingChargesSent

    if(-not [string]::IsNullOrEmpty($Request.query.DateFilter)){
        $billingDate = [DateTime]::ParseExact($request.query.DateFilter, "yyyyMMdd", $null)
        $billingDate = [DateTime]::New($billingDate.Year, $billingDate.Month, 28)
    }
    else{
        $pMonth = [DateTime]::Now.AddMonths(-1)
        $billingDate = [DateTime]::New($pMonth.Year,$pMonth.Month,28)
    }

    $Filter = "PartitionKey eq '$($billingDate.ToString("yyyy-MM-dd"))'"
    Write-Host "$('*'*60) $filter"
    $existingData = Get-CIPPAzDataTableEntity @SentChargesTable -filter $Filter
    Write-Host "$('*'*60) Got $($existingData.count) charges"

    $resp = @()

    foreach($charge in $existingData){
        $resp += @{
            customer    = $charge.Customer
            sentDate    = $charge.Timestamp
            chargedate  = $charge.PartitionKey
            contract    = $charge.contractID
            cost        = $charge.cost
            price       = $charge.price
        }
    }

    #write-host "$('*'*60) $($resp|ConvertTo-Json -Depth 10)"

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($resp)
    })
}
