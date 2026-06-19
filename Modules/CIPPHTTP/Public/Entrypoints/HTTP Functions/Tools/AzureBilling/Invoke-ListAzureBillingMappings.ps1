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
    # Get-AutotaskAPIResource's -Resource is a *dynamic* parameter that only exists after
    # Add-AutotaskAPIAuth (run inside Get-AutotaskCompanies above) authenticates to Autotask
    # and downloads its entity list. If that auth fails, the dynamic param never registers and
    # a direct call throws a cryptic binding error. Guard it so the page degrades gracefully.
    try {
        $atContracts = Get-AutotaskAPIResource -Resource contracts -SearchQuery ($contractQuery | ConvertTo-Json -Depth 10 -Compress)
    } catch {
        $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-LogMessage -Message "Could not get Autotask contracts, error: $Message" -sev Error -tenant 'CIPP' -API 'AutotaskMapping'
        $atContracts = @()
    }

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
        [bool]$isEnabled = $true;
        if($mapping.isEnabled -ne $null){
            $isEnabled = $mapping.isEnabled
        }

        if (-not [String]::IsNullOrEmpty($mapping.markup)) { $markup = "$($mapping.markup*100)%" }
        $results += [PSCustomObject] @{
            key           = "$($mapping.PartitionKey)~$($mapping.RowKey)"
            Customer      = ($atCompanies | ? { $_.id -eq $mapping.atCustId }).companyName
            Contract      = ($atContracts | ? { $_.Id -eq $mapping.contractId }).contractName
            Billable      = $mapping.billableToAccount
            Markup        = $markup
            ResourceGroup = $mapping.paxResourceGroupName
            Enabled       = $isEnabled
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($results)
        })
}
