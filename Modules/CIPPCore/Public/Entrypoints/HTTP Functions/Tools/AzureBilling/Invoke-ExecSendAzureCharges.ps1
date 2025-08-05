using namespace System.Net

function Invoke-ExecSendAzureCharges {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $billingDate = (Get-Date 01.01.1970)+([System.TimeSpan]::fromseconds($Request.Body.billMonth))
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

    $results = @()
    foreach($charge in $charges){
        try{
            $atCharge = New-AutotaskBody -Resource ContractCharges -NoContent
            if($charge.appendGroup) { $atCharge.name = "$($charge.chargeName) - $($charge."Resource Group")" }
            else { $atCharge.name = $charge.ChargeName }
            $atCharge.contractID            = $charge.contractId
            $atCharge.billingCodeID         = $charge.allocationCodeId
            $atCharge.isBillableToCompany   = $charge.billableToAccount
            $atCharge.unitCost              = [decimal]::round($charge.cost,2)
            $atCharge.unitPrice             = [decimal]::round($charge.price,2)
            $atCharge.datePurchased         = $charge.chargeDate
            $atCharge.chargeType            = 1 # Operational
            $atCharge.status                = 6 # Delivered/Shipped Full
            $atCharge.unitQuantity          = 1

            New-AutotaskAPIResource -Resource ContractCharges -Body $atCharge
            $results += $atCharge

            $sentCharge = @{
                PartitionKey = $charge.chargeDate.ToString("yyyy-MM-dd") # Get-MappedChargesToSend returns a datetime object.
                RowKey       = "$($charge.customerId) - $($charge."Resource Group")"
                ContractId   = $charge.contractId
                Customer     = $charge.customer
                cost         = $charge.cost
                price        = $charge.price
            }

            Add-CIPPAzDataTableEntity @SentChargesTable -Entity $sentCharge -Force
        }
        catch {
            Write-LogMessage -sev Error -API "Azure Billing" -message "Error sending charge: $($_.Exception.Message)"
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = "Sent $($results.count) of $($charges.count) charges."
    })
}

function Get-BillingData {
    param($table,$date)
    $existingData = @()

    $Filter = "PartitionKey eq '$($date.ToString("yyyy-MM"))'"
    $existingData = Get-CIPPAzDataTableEntity @table -filter $Filter

    return $existingData
}

function Get-MappedChargesToSend {
    param($azMonthSplit, $body, $atMapping)

    $atMappingHashTable = @{}
    $atMapping| ForEach-Object {
        if([string]::IsNullOrEmpty($_.PartitionKey) -or [string]::IsNullOrEmpty($_.paxResourceGroupName)) {
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

        if($null -ne $_.PartitionKey){
            $chargeDate = [DateTime]::ParseExact("$($_.PartitionKey)-28",'yyyy-MM-dd',$null)
        }
        else {
            Write-Host "$('*'*60) Bad chargedate value"
            continue
        }

        if($atMappingHashTable.Contains($join)){
            $mapping = $atMappingHashTable[$join]

            #if($mapping.billableToAccount){
            #}
            $body += @{
                chargeDate          = $chargeDate
                customerId          = $_.customerRef
                customer            = $_.customer
                subscriptionId      = $_.licenseRef
                "Resource Group"    = ($_.group.toupper())
                price               = $_.totalList
                cost                = $_.totalReseller
                vendor              = "Arrow" # TODO - Set this via the billing extension config options.
                atCustId            = $mapping.atCustId
                allocationCodeId    = $mapping.allocationCodeId
                chargeName          = $mapping.chargeName
                appendGroup         = $mapping.appendGroup
                contractId          = $mapping.contractId
                billableToAccount   = $mapping.billableToAccount
                atSumGroup          = $mapping.atSumGroup
            }
        }
    }

    return $body
}
