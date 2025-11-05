using namespace System.Net

function Invoke-ListAzureBillingMappings {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    write-host "$('*'*60) Getting Azure companies...."
    $mappingContext = Get-CIPPTable -tablename AzureBillingMapping

    $mappings = Get-CIPPAzDataTableEntity @mappingContext

    #unique customer ids
    $custIds = $mappings | Select-Object -Property atCustId -Unique

    #get unique contract Ids
    $contrs = $mappings | Select-Object -Property contractid -Unique

    $custQuery = [PSCustomObject]@{
        filter = @(
            [PSCustomObject]@{
                op    = 'in'
                field = 'id'
                value = $custIds.atCustId
            }
        )
    }

    $atCompanies = Get-AutotaskCompanies -queryObj $custQuery

    $contractQuery = [PSCustomObject]@{
        filter = @(
            [PSCustomObject]@{
                op    = 'in'
                field = 'id'
                value = $contrs.contractId
            }
        )
    }
    $atContracts = Get-AutotaskAPIResource -Resource contracts -SearchQuery ($contractQuery | ConvertTo-Json -Depth 10 -Compress)

    <#
    key=PartitionKey+RowKey of the mapping
    cust=Customer the mapping applies to
    contr=Contract the mapping uses
    billTo=T/F billable to account
    markup=% markup
    rgName=Resource group the mapping applies to
   #>


    $results = @()
    foreach ($mapping in $mappings) {
        $markup = "0%"
        if (-not [String]::IsNullOrEmpty($mapping.markup)) { $markup = "$($mapping.markup*100)%" }
        $results += [PSCustomObject] @{
            key           = "$($mapping.PartitionKey)~$($mapping.RowKey)"
            Customer      = ($atCompanies | ? { $_.id -eq $mapping.atCustId }).companyName
            Contract      = ($atContracts | ? { $_.Id -eq $mapping.contractId }).contractName
            Billable      = $mapping.billableToAccount
            Markup        = $markup
            ResourceGroup = $mapping.paxResourceGroupName
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($results)
        })
}
