using namespace System.Net

[string]$baseURI = ''

function Invoke-ExecGetAzureBillingCharges {
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

    $CtxExtensionCfg = Get-CIPPTable -TableName Extensionsconfig
    $CfgExtensionTbl = (Get-CIPPAzDataTableEntity @CtxExtensionCfg).config | ConvertFrom-Json -Depth 10

    if (-not $CfgExtensionTbl.AzureBilling) {
        $body = @("Extension is not configured")
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @($body)
            })
        return  # Short-circuit the function
    }

    $SCRIPT:baseURI = $CfgExtensionTbl.AzureBilling.APIHost

    $hdrAuth = Get-AzureBillingToken $CfgExtensionTbl

    if (-not $hdrAuth) {
        $body = @("Could not get authentication data")
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @($body)
            })
        return  # Short-circuit the function
    }

    try {
        $billingContext = Get-CIPPTable -tablename AzureBillingRawCharges
        $atMappingContext = Get-CIPPTable -tablename AzureBillingMapping
        $atUnmappedContext = Get-CIPPTable -tablename AzureBillingUnmappedCharges
        $atMappingRows = Get-CIPPAzDataTableEntity @atMappingContext

        if ($atMappingRows.count -eq 0) {
            Write-LogMessage -sev Info -API 'Azure Billing' -message "Got no rows from AutotaskAzureMapping"
        }

        if ([bool]::Parse($request.Query.rerunJob)) {
            Write-LogMessage -sev Info -API "Azure Billing" -message "Rerun billing job requested. $($Request.Query.rerunJob)"
        }

        $body = @()

        if ([bool]::Parse($request.Query.rerunJob) -eq $false) {
            $existingData = Get-ExistingBillingData -table $billingContext -date $request.Query.billMonth
            if ($existingData.count -gt 0) {
                Write-LogMessage -sev Info -API "Azure Billing" -message "Existing records found and rerun not requested."
                $mappedUnmapped = Get-MappedUnmappedCharges -azMonthSplit $existingData -body $body -atMapping $atMappingRows
                $body = $mappedUnmapped.mapped
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = $body
                    })
                return
            }
        }

        $monthFilter = ([DateTime]::ParseExact($request.Query.billMonth, 'yyyyMMdd', $null).ToString('yyyy-MM'))

        $customers = GetArrowCustomers -hdrAuth $hdrAuth

        $targetSKUs = $CfgExtensionTbl.AzureBilling.SKU.split(',')

        $no_data_rows = @()
        foreach ($cust in $customers) {
            #if ($cust.Reference -match $CfgExtensionTbl.AzureBilling.ExcludeCust) {
            #    continue
            #}

            $subscriptions = GetCustLicenses -custId $cust.Reference -hdrAuth $hdrAuth
            $subscriptions = $subscriptions | Where-Object { $targetSKUs -contains $_.sku } #"MS-AZR-0145P"

            foreach ($sub in $subscriptions) {
                $conMonth = GetConsumptionMonthly -License $sub.license_id -hdrAuth $hdrAuth -MonthStart $monthFilter -MonthEnd $monthFilter

                if ($conMonth.data.list.dataProvider.status -match 'consumed_valid') {
                    $azMonthSplit = GetAzureConsumptionMonthSplit -License $sub.license_id -Subscription $sub -Customer $cust -GroupBy "resource group" -hdrAuth $hdrAuth -MonthStart $monthFilter -MonthEnd $monthFilter

                    Write-ChargesToTable -table $billingContext -charges $azMonthSplit -rerun $Request.Query.rerunJob
                }
                elseif ($null -eq $conMonth -and $null -ne $sub) {
                    #construct a 'no charges on sub data' object
                    $datestr = ([DateTime]::ParseExact($request.Query.billMonth, 'yyyyMMdd', $null).ToString('MM/28/yyyy'))
                    $no_data_rows += Get-NoDataRow -customer $cust -subscription $sub -dateval $datestr
                }
            }
        }


        $data = Get-ExistingBillingData -table $billingContext -date $request.Query.billMonth
        $mappedUnmapped = Get-MappedUnmappedCharges -azMonthSplit $data -body $body -atMapping $atMappingRows
        $body = $mappedUnmapped.mapped
        $body += $no_data_rows #This is to show which subscriptions returned no data.


        Write-UnmappedToTable -table $atUnmappedContext -unmappedcharges $mappedUnmapped.unmapped
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "$($_.Exception.Message)"
        $body = @("Error getting billing data. Details have been logged.")
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($body)
        })
}

#This will return a row indicating a subscription had no data.
function Get-NoDataRow {
    param($customer, $subscription, $dateval)
    return @{
        chargeDate        = $dateval
        customerId        = $customer.XacEndCustomerId
        customer          = $customer.companyName
        subscriptionId    = $subscription.Reference
        "Resource Group"  = "NO DATA FROM ARROW"
        price             = 0.0
        cost              = 0.0
        vendor            = "Arrow"
        atCustId          = -1
        allocationCodeId  = -1
        chargeName        = "N/A"
        appendGroup       = $false
        contractId        = -1
        billableToAccount = $false
        atSumGroup        = $false
    }

}

function Get-MappedUnmappedCharges {
    param($azMonthSplit, $body, $atMapping)


    $unmappedCharges = @()

    $atMappingHashTable = @{}
    $atMapping | ForEach-Object {
        if (-not [string]::IsNullOrEmpty($_.PartitionKey) -and -not [string]::IsNullOrEmpty($_.paxResourceGroupName)) {
            $join = ("$($_.PartitionKey.Trim()) - $($_.paxResourceGroupName.Trim())").ToUpper()
            $atMappingHashTable[$join] = $_
        }
    }

    #Expected final columns
    #chargeDate_customerId_customer_ResourceGroup_price_Vendor_cost_atCustId_allocationCodeId_chargeName_contractId_appendGroup_billableToAccount_atSumGroup
    $azMonthSplit | ForEach-Object {
        $join = ("$($_.licenseRef.Trim()) - $($_.group.Trim())").ToUpper()

        if ($null -ne $_.PartitionKey) {
            $chargeDate = [DateTime]::ParseExact("$($_.PartitionKey)-28", 'yyyy-MM-dd', $null).ToString("MM/dd/yyyy")
        }
        else {
            continue
        }

        if ($atMappingHashTable.Contains($join)) {
            $mapping = $atMappingHashTable[$join]

            $price = $_.totalList

            if ($mapping.markup) {
                $price += ($price * $mapping.markup)
            }

            # if($mapping.billableToAccount){
            # }

            $body += @{
                chargeDate        = $chargeDate
                customerId        = $_.customerRef
                customer          = $_.customer
                subscriptionId    = $_.licenseRef
                "Resource Group"  = ($_.group.toupper())
                price             = $price
                cost              = $_.totalReseller
                vendor            = "Arrow"
                atCustId          = $mapping.atCustId
                allocationCodeId  = $mapping.allocationCodeId
                chargeName        = $mapping.chargeName
                appendGroup       = $mapping.appendGroup
                contractId        = $mapping.contractId
                billableToAccount = $mapping.billableToAccount
                atSumGroup        = $mapping.atSumGroup
            }
        }
        else {
            $unmappedCharges += @{
                chargeDate       = $chargeDate
                customerId       = $_.customerRef
                customer         = $_.customer
                subscriptionId   = $_.licenseRef
                "Resource Group" = ($_.group.toupper())
                price            = $_.totalList
                cost             = $_.totalReseller
                vendor           = "Arrow"
            }
        }
    }

    return @{mapped = $body; unmapped = $unmappedCharges }
}

function Write-ChargesToTable {
    param($table, $charges, $rerun)

    foreach ($line in $azMonthSplit.lines) {

        try {
            switch ($($line.group)) {
                "N/A" { $line.group = "NA"; break }
            }

            $AddObject = @{
                PartitionKey  = $line.month
                RowKey        = "$($line.licenseRef) - $($line.group)"
                currency      = $line.currency
                customer      = $line.customer
                customerRef   = $line.customerRef
                group         = $line.group
                licenseRef    = $line.licenseRef
                totalCustomer = ([math]::Round($line.totalCustomer, 2))
                totalList     = ([math]::Round($line.totalList, 2))
                totalReseller = ([math]::Round($line.totalReseller, 2))
            }

            if ([bool]::Parse($rerun)) {
                Add-CIPPAzDataTableEntity @table -Entity $AddObject -Force
            }
            else {
                Add-CIPPAzDataTableEntity @table -Entity $AddObject
            }
            Write-LogMessage -sev Debug -API 'Azure Billing' -message "Added azure billing for $($line.customer)"
        }
        catch {
            Write-LogMessage -sev Error -API 'Azure Billing' -message "Error writing charges to table $($_.Exception.Message)"
        }
    }
}

function Write-UnmappedToTable {
    param($table, $unmappedcharges)

    foreach ($line in $unmappedcharges) {
        $AddObject = @{
            PartitionKey   = ($line.chargeDate.replace('/', '-'))
            RowKey         = "$($line.subscriptionId) - $($line."Resource Group")"
            customer       = $line.customer
            subscriptionId = $line.subscriptionId
            ResourceGroup  = $line."Resource Group"
            price          = ([math]::Round($line.price, 2))
            cost           = ([math]::Round($line.cost, 2))
            vendor         = $line.vendor
        }

        try {
            Add-CIPPAzDataTableEntity @table -Entity $AddObject -Force
            Write-LogMessage -sev Debug -API 'Azure Billing' -message "Added unmapped billing for $($line.customer)"
        }
        catch {
            Write-LogMessage -sev Error -API 'Azure Billing' -message "Error writing unmapped charges to table $($_.Exception.Message)"
        }
    }
}

function Get-ExistingBillingData {
    param($table, $date)
    $existingData = @()

    $Filter = "PartitionKey eq '$([DateTime]::ParseExact($date,'yyyyMMdd',$null).ToString('yyyy-MM'))'"
    $existingData = Get-CIPPAzDataTableEntity @table -filter $Filter

    return $existingData
}

function GetArrowCustomers {
    param(
        [string] $reference = "",
        [Parameter(Mandatory = $true)]$hdrAuth
    )

    $uriSuffix = "/index.php/api/customers/$reference"

    try {
        $resp = Invoke-RestMethod -Uri ($baseURI + $uriSuffix) -Method "GET" `
            -ContentType "application/json" `
            -Headers $hdrAuth

        if (-not $resp.data.customers) {
            Write-LogMessage -sev Error -API 'Azure Billing' -message "No customers found in response."
            return
        }

        return ($resp.data.customers)
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "Error in GetArrowCustomers: $($_.Exception.Message)"
        return @()
    }
}

function GetCustLicenses {
    param(
        [string] $custId = "",
        [string] $sku = "",
        [string] $state = "", #"active",
        [Parameter(Mandatory = $true)]$hdrAuth

    )

    $uriSuffix = "/index.php/api/customers/$custId/licenses?state=$state"

    if ($sku -ne "") {
        $uriSuffix += "&sku=$sku"
    }

    $resp = Invoke-RestMethod -Uri ($baseURI + $uriSuffix) -Method "GET" `
        -ContentType "application/json" `
        -Headers $hdrAuth

    return $resp.data.licenses
}

function GetConsumptionMonthly {
    param(
        [string] $License = "XSP1703764",
        [string] $MonthStart = [DateTime]::Now.AddMonths(-1).ToString("yyyy-MM"),
        [string] $MonthEnd = [DateTime]::Now.AddMonths(-1).ToString("yyyy-MM"),
        [Parameter(Mandatory = $true)]$hdrAuth
    )

    try {
        $uriSuffix = "/index.php/api/consumption/license/$($License)/monthly/?billingMonthStart=$($MonthStart)&billingMonthEnd=$($MonthEnd)"
        $resp = Invoke-RestMethod -Uri ($baseURI + $uriSuffix) -Method "GET" `
            -ContentType "application/json" `
            -Headers $hdrAuth

        return $resp
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "Error in GetConsumptionMonthly: billingMonthStart=$($MonthStart)&billingMonthEnd=$($MonthEnd) $($_.Exception.Message)"
        return $null
    }
}

function GetAzureConsumptionMonthSplit {
    param(
        [string] $GroupBy = "resource group",
        [string] $License = "XSP1703764",
        [string] $MonthStart = [DateTime]::Now.AddMonths(-1).ToString("yyyy-MM"),
        [string] $MonthEnd = [DateTime]::Now.AddMonths(-1).ToString("yyyy-MM"),
        $Subscription,
        $Customer,
        [Parameter(Mandatory = $true)]$hdrAuth
    )

    try {
        $uriSuffix = "/index.php/api/consumption/license/$($License)/monthlySplit/?group_by=$($GroupBy)&billingMonthStart=$($MonthStart)&billingMonthEnd=$($MonthEnd)"

        $azMonth = [azConsumptionMonthSplit]::new()
        $azMonth.groupBy = $GroupBy
        $resp = Invoke-RestMethod -Uri ($baseURI + $uriSuffix) -Method "GET" `
            -ContentType "application/json" `
            -Headers $hdrAuth

        $i = 0
        foreach ($line in $resp.data.list.dataProvider) {
            $azLine = [azConsumptionMonthSplitLines]::new()
            $azLine.customer = $Customer.CompanyName
            $azLine.customerRef = $Customer.Reference
            $azLine.month = $MonthStart
            $azLine.licenseRef = $Subscription.license_id
            $azLine.currency = $resp.data.list.currency
            $azLine.totalCustomer = $resp.data.customer.dataProvider[$($i)].consumption
            $azLine.totalList = $resp.data.list.dataProvider[$($i)].consumption
            $azLine.totalReseller = $resp.data.reseller.dataProvider[$($i)].consumption
            $azLine.group = $resp.data.list.dataProvider[$($i)].group_by
            $azMonth.lines += $azLine
            $i++
        }


        return $azMonth
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "Error in GetAzureConsumptionMonthSplit: $($_.Exception.Message)"
        return $null
    }
}

class consumptionMonthLine {
    [string]$Month
    [string]$UOM
    [string]$Region
    [string]$CountryCurrencyCode
    [decimal]$CountryCustomerUnit
    [decimal]$LevelChargeableQuantity
    [string]$VendorProductName
    [string]$ResourceGroup
    [string]$VendorRessourceSKU
    [string]$VendorMeterCategory
    [string]$VendorMeterSubCategory

    # Constructor
    consumptionMonthLine ([string]$Month, [string]$UOM, [string]$Region, [string]$CountryCurrencyCode, [string]$CountryCustomerUnit, [string]$LevelChargeableQuantity, [string]$VendorProductName, [string]$ResourceGroup, [string]$VendorRessourceSKU, [string]$VendorMeterCategory, [string]$VendorMeterSubCategory) {
        $this.Month = $Month
        $this.UOM = $UOM
        $this.Region = $Region
        $this.CountryCurrencyCode = $CountryCurrencyCode
        $this.CountryCustomerUnit = $CountryCustomerUnit
        $this.LevelChargeableQuantity = $LevelChargeableQuantity
        $this.VendorProductName = $VendorProductName
        $this.ResourceGroup = $ResourceGroup
        $this.VendorRessourceSKU = $VendorRessourceSKU
        $this.VendorMeterCategory = $VendorMeterCategory
        $this.VendorMeterSubCategory = $VendorMeterSubCategory
    }

}

class azConsumptionMonthSplitLines {
    [string]$customer
    [string]$customerRef
    [string]$licenseRef
    [string]$currency
    [decimal]$totalCustomer
    [decimal]$totalList
    [decimal]$totalReseller
    [string]$month
    [string]$group
}

class azConsumptionMonthSplit {
    [string]$groupBy
    #[string]$month
    [azConsumptionMonthSplitLines[]]$lines
}
