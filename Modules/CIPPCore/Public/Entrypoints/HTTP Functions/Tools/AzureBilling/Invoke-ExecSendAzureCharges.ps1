using namespace System.Net

function Invoke-ExecSendAzureCharges {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $billingDate = (Get-Date 01.01.1970)+([System.TimeSpan]::fromseconds($Request.Body.datetime))
    $billingDate = [DateTime]::New($billingDate.Year, $billingDate.Month, 28)

    $CtxExtensionCfg = Get-CIPPTable -TableName Extensionsconfig
    $CfgExtensionTbl = (Get-CIPPAzDataTableEntity @CtxExtensionCfg).config | ConvertFrom-Json -Depth 10


    if (!$ENV:AzBillingConnStr) {
        $null = Connect-AzAccount -Identity
        $AzBillingConnStr = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'AzStorageConnStr' -AsPlainText)
    } else {
        $AzBillingConnStr = $ENV:AzBillingConnStr
    }

    if($null -eq $AzBillingConnStr){
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @("Error getting Az Billing table.")
        })
        return
    }


    $billingContext = Get-AzTableContext -connectionStr $AzBillingConnStr
    $atMappingContext = Get-CIPPTable -tablename AutotaskAzureMapping
    $atMappingRows = Get-CIPPAzDataTableEntity @atMappingContext

    $existingData = Get-BillingData -table $billingContext -date $billingDate

    $body = @()
    $charges = Get-MappedChargesToSend -azMonthSplit $existingData -body $body -atMapping $atMappingRows


    Write-Host "$('*'*60)"
    Write-Host "$($charges|ConvertTo-Json -Depth 10)"
    Write-Host "$('*'*60)"

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($charges)
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
            $chargeDate = [DateTime]::ParseExact("$($_.PartitionKey)-28",'yyyy-MM-dd',$null).ToString("MM/dd/yyyy")
        }
        else {
            Write-Host "$('*'*60) Bad chargedate value"
            continue
        }

        if($atMappingHashTable.Contains($join)){
            $mapping = $atMappingHashTable[$join]

            if($mapping.billableToAccount){
                $body += @{
                    chargeDate          = $chargeDate
                    customerId          = $_.customerRef
                    customer            = $_.customer
                    subscriptionId      = $_.licenseRef
                    "Resource Group"    = ($_.group.toupper())
                    price               = $_.totalList
                    cost                = $_.totalReseller
                    vendor              = "Arrow"
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
    }

    return $body
}
