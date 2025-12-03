using namespace System.Net

function Invoke-ExecSendAzureCharges {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $billingDate = (Get-Date 01.01.1970) + ([System.TimeSpan]::fromseconds($Request.Body.billMonth))
    $billingDate = [DateTime]::New($billingDate.Year, $billingDate.Month, 28)

    $CtxExtensionCfg = Get-CIPPTable -TableName Extensionsconfig
    $CfgExtensionTbl = (Get-CIPPAzDataTableEntity @CtxExtensionCfg).config | ConvertFrom-Json -Depth 10

    $SentChargesTable = Get-CIPPTable -TableName AzureBillingChargesSent

    Get-AutotaskToken -configuration $CfgExtensionTbl.Autotask

    $billingContext = Get-CIPPTable -tablename AzureBillingRawCharges #Get-AzTableContext -connectionStr $AzBillingConnStr
    $atMappingContext = Get-CIPPTable -tablename AzureBillingMapping
    $atMappingRows = Get-CIPPAzDataTableEntity @atMappingContext

    $existingData = Get-BillingData -table $billingContext -date $billingDate

    <# TODO - AzureBillingChargesSent table duplicate checking
    The 'sent charges table' having the charge date row key should cause the application to kick out an error.
    This will help prevent duplicate charges being sent, however a situation could arise where a charge would
    be sent for a month but potentially a billing issue at Arrow etc. could cause use to have to wait to send
    the second charge.
    Alternatively we could use the group/charge name and contract ID to prevent duplicates.
    #>


    $body = @()
    $charges = Get-MappedChargesToSend -azMonthSplit $existingData -body $body -atMapping $atMappingRows

    $isErrorState = $false
    $results = @()
    $testVal = 0
    foreach ($charge in $charges) {

        try {

            $chargeObj = [PSCustomObject]@{
                name                = $charge.ChargeName
                contractID          = $charge.contractId
                billingCodeID       = $charge.allocationCodeId
                isBillableToCompany = $charge.billableToAccount
                unitCost            = [decimal]::round($charge.cost, 2)
                unitPrice           = [decimal]::round($charge.price, 2)
                datePurchased       = $charge.chargeDate.ToString("MM-dd-yyyy")
                chargeType          = 1 # Operational
                status              = 6 # Delivered/Shipped Full
                unitQuantity        = 1
            }

            if ($charge.appendGroup) { $chargeObj.name = "$($charge.chargeName) - $($charge."Resource Group")" }

            Write-LogMessage -sev Info -API "Azure Billing" -message "$($chargeObj|ConvertTo-Json -Depth 5)"


            $sentCharge = @{
                PartitionKey = $charge.chargeDate.ToString("yyyy-MM-dd") # Get-MappedChargesToSend returns a datetime object.
                RowKey       = "$($charge.customerId) - $($charge."Resource Group")"
                ContractId   = $charge.contractId
                Customer     = $charge.customer
                cost         = $charge.cost
                price        = $charge.price
            }

            Add-CIPPAzDataTableEntity @SentChargesTable -Entity $sentCharge

            New-AutotaskAPIResource -Resource ContractChargesChild -ParentId $charge.contractId -Body $chargeObj
            $results += @{"resultText" = "Sent charge $($chargeObj.name) - `$$($chargeObj.unitPrice)"; "state" = "success" }
        }
        catch {
            Write-LogMessage -sev Error -API "Azure Billing" -message "Error sending charge: $($_.Exception.Message)"
            $results += @{"resultText" = "Error sending charge ($($chargeObj.name)): $($_.Exception.Message)"; "state" = "error" }
            $isErrorState = $true
        }
        $testVal += 1
    }

    $resp = ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($results)
        })

    if ($isErrorState) {
        $resp.StatusCode = [HttpStatusCode]::UnprocessableEntity
    }

    return $resp
}

function Get-BillingData {
    param($table, $date)
    $existingData = @()

    $Filter = "PartitionKey eq '$($date.ToString("yyyy-MM"))'"
    $existingData = Get-CIPPAzDataTableEntity @table -filter $Filter

    return $existingData
}

function Get-MappedChargesToSend {
    param($azMonthSplit, $body, $atMapping)

    $atMappingHashTable = @{}
    $atMapping | ForEach-Object {
        if ([string]::IsNullOrEmpty($_.PartitionKey) -or [string]::IsNullOrEmpty($_.paxResourceGroupName)) {
            Write-Host "$('*'*60) Empty PartitionKey or paxResourceGroupName..."
        }
        else {
            $join = ("$($_.PartitionKey.Trim()) - $($_.paxResourceGroupName.Trim())").ToUpper()
            $atMappingHashTable[$join] = $_
        }
    }

    #Expected final columns
    #chargeDate	customerId	customer	ResourceGroup	price	Vendor	cost	atCustId	allocationCodeId	chargeName	contractId	appendGroup	billableToAccount	atSumGroup
    $azMonthSplit | ForEach-Object {
        $join = ("$($_.licenseRef.Trim()) - $($_.group.Trim())").ToUpper()

        if ($null -ne $_.PartitionKey) {
            $chargeDate = [DateTime]::ParseExact("$($_.PartitionKey)-28", 'yyyy-MM-dd', $null)
        }
        else {
            Write-Host "$('*'*60) Bad chargedate value"
            continue
        }

        if ($atMappingHashTable.Contains($join)) {
            $mapping = $atMappingHashTable[$join]

            #if($mapping.billableToAccount){
            #}
            $body += @{
                chargeDate        = $chargeDate
                customerId        = $_.customerRef
                customer          = $_.customer
                subscriptionId    = $_.licenseRef
                "Resource Group"  = ($_.group.toupper())
                price             = $_.totalList
                cost              = $_.totalReseller
                vendor            = "Arrow" # TODO - Set this via the billing extension config options.
                atCustId          = $mapping.atCustId
                allocationCodeId  = $mapping.allocationCodeId
                chargeName        = $mapping.chargeName
                appendGroup       = $mapping.appendGroup
                contractId        = $mapping.contractId
                billableToAccount = $mapping.billableToAccount
                atSumGroup        = $mapping.atSumGroup
            }
        }
    }

    return $body
}
