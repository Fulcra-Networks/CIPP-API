using namespace System.Net

function Invoke-GetAzureBillingMapping {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    $split = $Request.Query.mappingId.split('~')
    if ($split.length -ne 2) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @("Parameter split failed")
            })
    }

    $parKey = $split[0]
    $rowKey = $split[1]

    if ([string]::IsNullOrEmpty($parKey)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @("No partition key found")
            })
    }
    if ([string]::IsNullOrEmpty($rowKey)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @("No row key found")
            })
    }

    $mappingContext = Get-CIPPTable -tablename AzureBillingMapping

    $mapping = Get-CIPPAzDataTableEntity @mappingContext -filter "PartitionKey eq '$($parKey)' and RowKey eq '$($rowKey)'"

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).Autotask

    Get-AutotaskToken -configuration $Configuration | Out-Null
    $atCust = Get-AutotaskAPIResource -Resource Companies -ID $mapping.atCustId
    $atContract = Get-AutotaskAPIResource -Resource Contracts -ID $mapping.contractId
    $atBilling = Get-AutotaskAPIResource -Resource BillingCodes -ID $mapping.allocationCodeId


    $result = [PSCustomObject]@{
        Subscription  = $mapping.PartitionKey
        ResourceGroup = $mapping.paxResourceGroupName
        appendGroup   = $mapping.appendGroup
        sumGroup      = $mapping.sumGroup
        billable      = $mapping.billableToAccount
        chargeName    = $mapping.chargeName
        markup        = $mapping.markup
        company       = @{label = $atCust.companyName; value = $mapping.atCustId }
        contract      = @{label = $atContract.contractName; value = $mapping.contractId }
        billingcode   = @{label = $atBilling.name; value = $mapping.allocationCodeId }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $result
        })
}
