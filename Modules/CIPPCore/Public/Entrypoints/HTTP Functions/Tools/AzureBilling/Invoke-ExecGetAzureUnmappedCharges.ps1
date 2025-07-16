using namespace System.Net


function Invoke-ExecGetAzureUnmappedCharges {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    if ([String]::IsNullOrEmpty($request.Query.billMonth)) {
        $body = @("No date set")
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = $body
        })
        return  # Short-circuit the function
    }

    try{
        #Unmapped charges are always the 28th of the month (04-28-2025)
        $monthFilter = [DateTime]::ParseExact($request.Query.billMonth,'yyyyMMdd',$null)
        $monthFilter = [DateTime]::New($monthFilter.Year,$monthFilter.Month, 28)

        $atUnmappedContext = Get-CIPPTable -tablename AzureBillingUnmappedCharges
        $unmappedFilter = "PartitionKey eq '$($monthFilter.ToString("MM-dd-yyyy"))'"
        $unmappedCharges = Get-CIPPAzDataTableEntity @atUnmappedContext -filter $unmappedFilter

        $body = @()

        foreach($unmappedCharge in $unmappedCharges){
            $body += @{
                chargeDate          = $unmappedCharge.PartitionKey
                customerId          = $unmappedCharge.subscriptionId
                customer            = $unmappedCharge.customer
                'Resource Group'    = $unmappedCharge.ResourceGroup
                price               = $unmappedCharge.price
                cost                = $unmappedCharge.cost
            }
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($body)
        })
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "$($_.Exception.Message)"
        $body = @("Error getting billing data. Details have been logged.")
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
    }
}
