using namespace System.Net

[string]$baseURI = ''

function Invoke-ExecGetAzureBillingCharges {
    [CmdletBinding()]
    param(
        $Request,
        $TriggerMetadata
    )

    if ([String]::IsNullOrEmpty($request.Query.billMonth)) {
        $body = @("No date set")
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $body
            })
    }

    $CtxExtensionCfg = Get-CIPPTable -TableName Extensionsconfig
    $CfgExtensionTbl = (Get-CIPPAzDataTableEntity @CtxExtensionCfg).config | ConvertFrom-Json -Depth 10

    if (-not $CfgExtensionTbl.AzureBilling) {
        $body = @("Extension is not configured")
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @($body)
            })
    }

    $SCRIPT:baseURI = $CfgExtensionTbl.AzureBilling.APIHost

    $hdrAuth = Get-AzureBillingToken $CfgExtensionTbl

    if (-not $hdrAuth) {
        $body = @("Could not get authentication data")
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @($body)
            })
    }

    try {
        $billingContext = Get-CIPPTable -tablename AzureBillingRawCharges
        $atMappingContext = Get-CIPPTable -tablename AzureBillingMapping
        $atUnmappedContext = Get-CIPPTable -tablename AzureBillingUnmappedCharges

        $monthFilter = ([DateTime]::ParseExact($request.Query.billMonth, 'yyyyMMdd', $null).ToString('yyyy-MM'))
        $monthFilteryPartKey = ([DateTime]::ParseExact($request.Query.billMonth, 'yyyyMMdd', $null).ToString('yyyy-MM-28'))
        $monthFilterFormatted = ([DateTime]::ParseExact($request.Query.billMonth, 'yyyyMMdd', $null))

        if (Get-ChargesWereSent -BillMonth $monthFilteryPartKey) {
            Write-LogMessage -sev Warning -API 'Azure Billing' -message "Charges were already sent."
            $respData = [PSCustomObject]@{
                previousMonth = 0
                rows          = @()
                Alert         = "Billing has already been run for $($monthFilter). Please review sent charges."
            }
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = $respData
                })
        }

        $atMappingRows = Get-CIPPAzDataTableEntity @atMappingContext

        if ($atMappingRows.count -eq 0) {
            Write-LogMessage -sev Info -API 'Azure Billing' -message "Got no rows from AutotaskAzureMapping"
        }

        $prevMonth = Get-PreviousMonthSentAmount -monthFilter $monthFilterFormatted

        $body = @()

        if ([bool]::Parse($request.Query.rerunJob) -eq $false) {
            $existingData = Get-ExistingBillingData -table $billingContext -date $monthFilter
            if ($existingData.count -gt 0) {
                Write-LogMessage -sev Info -API "Azure Billing" -message "Existing records found and rerun not requested."
                $mappedUnmapped = Get-MappedUnmappedCharges -azMonthSplit $existingData -body $body -atMapping $atMappingRows
                $noDataRows = Get-NoApiDataRows -month $monthFilter
                $body = $mappedUnmapped.mapped
                if ($null -ne $noDataRows) {
                    $body += $noDataRows
                }

                $respData = [PSCustomObject]@{
                    previousMonth = $prevMonth
                    rows          = @($body)
                }

                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = $respData
                    })
            }
        }

        $customers = GetArrowCustomers -hdrAuth $hdrAuth

        $targetSKUs = $CfgExtensionTbl.AzureBilling.SKU.split(',')

        $no_data_rows = [System.Collections.Generic.List[object]]::new()
        $allCharges = [System.Collections.Generic.List[object]]::new()

        foreach ($cust in $customers) {
            $allSubscriptions = GetCustLicenses -custId $cust.Reference -hdrAuth $hdrAuth
            $subscriptions = $allSubscriptions | Where-Object { $targetSKUs -contains $_.sku } #"MS-AZR-0145P"

            foreach ($sub in $subscriptions) {
                try {
                    $conMonth = GetConsumptionMonthly -License $sub.license_id -hdrAuth $hdrAuth -MonthStart $monthFilter -MonthEnd $monthFilter
                    # 2026-09-18 - MonthlyV2 does not have "status" field. Reconstruct the old 'consumed_valid' gate:
                    # a closed report period with a numeric sell total.
                    $validity = Test-ArrowMonthlyConsumptionValid -Response $conMonth -ReportPeriod $monthFilter

                    # if ($conMonth.data.list.dataProvider.status -match 'consumed_valid') {
                    if($validity.IsValid) {
                        $azMonthSplit = GetAzureConsumptionMonthSplit -License $sub.license_id -Subscription $sub -Customer $cust -GroupBy "resource group" -hdrAuth $hdrAuth -MonthStart $monthFilter -MonthEnd $monthFilter
                        #Write-ChargesToTable -table $billingContext -charges $azMonthSplit -rerun $Request.Query.rerunJob
                        $allCharges.Add($azMonthSplit)
                    }
                    else { #if ($null -eq $conMonth -and $null -ne $sub) {
                        Write-LogMessage -sev Warning -API 'Azure Billing' -message "No valid consumption for $($sub.license_id) ($($cust.CompanyName)) in $($monthFilter): $($validity.Reason)"
                        #construct a 'no charges on sub data' object
                        $no_data_rows.Add((Get-NoDataRow -customer $cust -subscription $sub -dateval $monthFilter))
                    }
                }
                catch {
                    Write-LogMessage -sev Error -API 'Azure Billing' -message "Error processing subscription $($sub.license_id) for customer $($cust.CompanyName): $($_.Exception.Message)"
                    # Continue processing other subscriptions even if one fails
                }
            }
        }

        Write-ChargesToTable -table $billingContext -charges $allCharges -rerun $Request.Query.rerunJob
        Write-NoDataRows -charges $no_data_rows
        $data = Get-ExistingBillingData -table $billingContext -date $monthFilter
        $mappedUnmapped = Get-MappedUnmappedCharges -azMonthSplit $data -atMapping $atMappingRows -monthFilterDate $monthFilterFormatted
        $body = $mappedUnmapped.mapped
        if ($null -ne $no_data_rows) {
            $body += $no_data_rows #This is to show which subscriptions returned no data.
        }

        Write-UnmappedToTable -table $atUnmappedContext -unmappedcharges $mappedUnmapped.unmapped
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "Invoke-ExecGetAzureBillingCharges error: $($_.Exception.Message)"
        $body = @("Error getting billing data. Details have been logged.")
    }

    $respData = [PSCustomObject]@{
        previousMonth = $prevMonth
        rows          = @($body)
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $respData
        })
}

function Get-ChargesWereSent {
    param($BillMonth)

    $filter = "PartitionKey eq '$BillMonth'"
    $tableContext = Get-CIPPTable -tablename AzureBillingChargesSent
    $results = Get-CIPPAzDataTableEntity @tableContext -filter $Filter

    return ($null -ne $results)
}

#This will return a row indicating a subscription had no data.
function Get-NoDataRow {
    param($customer, $subscription, $dateval)
    return @{
        chargeDate        = $dateval
        customerId        = $customer.Reference
        customer          = $customer.companyName
        subscriptionId    = $subscription.license_id
        "ResourceGroup"   = "NO DATA FROM ARROW"
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
    param(
        $azMonthSplit,
        $body,
        $atMapping,
        $monthFilterDate
    )

    $mappedCharges = [System.Collections.Generic.List[object]]::new()
    $unmappedCharges = [System.Collections.Generic.List[object]]::new()

    $atMappingHashTable = @{}
    foreach ($mapping in $atMapping) {
        if ($mapping.PSObject.Properties.Name -contains 'isEnabled') {
            if ($mapping.isEnabled -eq $false) {
                continue;
            }
        }
        if (-not [string]::IsNullOrEmpty($mapping.PartitionKey) -and -not [string]::IsNullOrEmpty($mapping.paxResourceGroupName)) {
            $join = ("$($mapping.PartitionKey.Trim()) - $($mapping.paxResourceGroupName.Trim())").ToUpper()
            $atMappingHashTable[$join] = $mapping
        }
    }

    #Expected final columns
    #chargeDate_customerId_customer_ResourceGroup_price_Vendor_cost_atCustId_allocationCodeId_chargeName_contractId_appendGroup_billableToAccount_atSumGroup
    foreach ($charge in $azMonthSplit) {
        $join = ("$($charge.licenseRef.Trim()) - $($charge.group.Trim())").ToUpper()

        if ($null -ne $charge.PartitionKey) {
            $chargeDate = [DateTime]::ParseExact("$($charge.PartitionKey)-28", 'yyyy-MM-dd', $null).ToString("MM/dd/yyyy")
        }
        else {
            continue
        }

        if ($atMappingHashTable.Contains($join)) {
            $mapping = $atMappingHashTable[$join]

            $price = $charge.totalList

            if ($mapping.markup) {
                $price += ($price * $mapping.markup)
            }

            $mappedCharges.Add(@{
                    chargeDate        = $chargeDate
                    customerId        = $charge.customerRef
                    customer          = $charge.customer
                    subscriptionId    = $charge.licenseRef
                    "Resource Group"  = ($charge.group.toupper())
                    price             = $price
                    cost              = $charge.totalReseller
                    vendor            = "Arrow"
                    atCustId          = $mapping.atCustId
                    allocationCodeId  = $mapping.allocationCodeId
                    chargeName        = $mapping.chargeName
                    appendGroup       = $mapping.appendGroup
                    contractId        = $mapping.contractId
                    billableToAccount = $mapping.billableToAccount
                    atSumGroup        = $mapping.atSumGroup
                })
        }
        else {
            $unmappedCharges.Add(@{
                    chargeDate       = $chargeDate
                    customerId       = $charge.customerRef
                    customer         = $charge.customer
                    subscriptionId   = $charge.licenseRef
                    "Resource Group" = ($charge.group.toupper())
                    price            = $charge.totalList
                    cost             = $charge.totalReseller
                    vendor           = "Arrow"
                })
        }
    }

    return @{mapped = $mappedCharges.ToArray(); unmapped = $unmappedCharges.ToArray() }
}

function Write-NoDataRows {
    param($charges)

    $noDataContext = Get-CIPPTable -tablename AzureBillingNoDataSubscriptions
    $addObjects = @()
    try {
        $addObjects = foreach ($line in $charges) {
            @{
                PartitionKey      = $line.chargeDate
                RowKey            = "ND-$($line.subscriptionId) - $($line.customerId)-ND"
                subscriptionId    = $line.subscriptionId
                chargeDate        = $line.chargeDate
                customerId        = $line.customerId
                customer          = $line.customer
                "ResourceGroup"   = "NO DATA FROM ARROW"
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

        Add-CIPPAzDataTableEntity @noDataContext -Entity $addObjects -Force
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "Write-NoDataRows error: $($_.Exception.Message). $($addObjects|ConvertTo-Json -Depth 10 -Compress)"
    }
}

function Write-ChargesToTable {
    param(
        $table,
        $charges,
        $rerun
    )



    $addObjects = @()
    try {
        $addObjects = foreach ($line in $charges | Select-Object -ExpandProperty lines) {
            if ($line.group -eq "N/A") {
                $line.group = "NA"
            }

            @{
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
        }


        if ([bool]::Parse($rerun)) {
            Add-CIPPAzDataTableEntity @table -Entity $addObjects -Force
        }
        else {
            Add-CIPPAzDataTableEntity @table -Entity $addObjects
        }
        Write-LogMessage -sev Debug -API 'Azure Billing' -message "Batch wrote $($addObjects.Count) charge records"
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "Write-ChargesToTable error: $($_.Exception.Message). $($addObjects|ConvertTo-Json -Depth 10 -Compress)"
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
    param(
        $table,
        $date
    )

    try {
        $Filter = "PartitionKey eq '$date'"
        $existingData = Get-CIPPAzDataTableEntity @table -filter $Filter

        return $existingData
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "Error getting existing billing data: $($_.Exception.Message)"
        return @()
    }
}

function Get-NoApiDataRows {
    param($monthFilter)
    try {
        $noDataContext = Get-CIPPTable -tablename AzureBillingNoDataSubscriptions

        $Filter = "PartitionKey eq '$monthFilter'"
        $existingData = Get-CIPPAzDataTableEntity @noDataContext -filter $Filter

        $noDataRows = $existingData | ForEach-Object {
            @{
                chargeDate        = $_.PartitionKey
                customerId        = $_.customerId
                customer          = $_.customer
                subscriptionId    = $_.subscriptionId
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

        return $noDataRows
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "Error getting no-apidata rows: $($_.Exception.Message)"
        return @()
    }
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

    # DEPRECATED Endpoint - Order {} data removed
    #    $uriSuffix = "/index.php/api/customers/$custId/licenses?state=$state"
    # New Customer endpoint - Offers ?state param for license active state.
    $uriSuffix = "/index.php/api/customers/v2/$custId/licenses?state=$state"

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
        # DEPRECATED ENDPOINT
        # $uriSuffix = "/index.php/api/consumption/license/$($License)/monthly/?billingMonthStart=$($MonthStart)&billingMonthEnd=$($MonthEnd)"
        $uriSuffix = "/index.php/api/consumption/monthly/license/$($License)?reportPeriodStart=$($MonthStart)&reportPeriodEnd=$($MonthEnd)"
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
        # DEPRECATED Endpoint - Removed 2026-09-30
        #$uriSuffix = "/index.php/api/consumption/license/$($License)/monthlySplit/?group_by=$($GroupBy)&billingMonthStart=$($MonthStart)&billingMonthEnd=$($MonthEnd)"

        # Line V2 is a single-period and paginated, no server-side group by.
        # Fetch every page. Aggregate client-side.
        # Deprecated 2025-07-31 and retiring 2026-12-31
        # See "Consumption Detail V2" https://arrowsphere-api.readme.io/reference/requestconsumptiondetailv2
        $lines = Get-ArrowConsumptionLines -License $License -Period $MonthStart -hdrAuth $hdrAuth

        $azMonth = [azConsumptionMonthSplit]::new()
        $azMonth.groupBy = $GroupBy

        if($lines.Count -eq 0) {
            $azMonth.lines = @()
            return $azMonth
        }

        $groupColumn = switch($GroupBy.ToLower()){
            'resource group' { 'Resource Group' }
            default { throw "Unsupported GroupBy '$GroupBy' for Line V2"}
        }

        $groups = [ordered]@{}
        foreach($line in $lines){
            $groupName = "$($line.$groupColumn)".Trim()
            # Old endpoint reported ungrouped consumption as "N/A";
            # Write-ChargesToTable already normalizes that to "NA" for RowKey.
            if([string]::IsNullOrWhiteSpace(($groupName)) -or $groupName -eq 'null'){
                $groupName = 'N/A'
            }

            if(-not $groups.Contains($groupName)){
                $groups[$groupName] = @{ sell = [decimal]0; buy = [decimal]0; currency = $line.'Country currency code' }
            }
            $groups[$groupName].sell += ConvertTo-ArrowDecimal $line.'Total sell price'
            $groups[$groupName].buy += ConvertTo-ArrowDecimal $line.'Total buy price'
        }

        $azLines = [System.Collections.Generic.List[azConsumptionMonthSplitLines]]::new()
        foreach($groupName in $groups.Keys){
            $g = $groups[$groupName]
            $azLine = [azConsumptionMonthSplitLines]::new()
            $azLine.customer = $Customer.CompanyName
            $azLine.customerRef = $Customer.Reference
            $azLine.month = $MonthStart
            $azLine.licenseRef = $Subscription.license_id
            $azLine.currency = $g.currency
            $azLine.group = $groupName
            # Price tier mapping (old -> Line V2):
            #   customer.consumption -> Total sell price
            #   reseller.consumption -> Total buy price
            #   list.consumption     -> NO EQUIVALENT in V2. Get-MappedUnmappedCharges prices the
            #                           customer off totalList and applies mapping.markup on top.
            #                           Aliased to sell price pending the business decision recorded
            #                           in the migration plan (Phase 2, totalList).
            $azLine.totalCustomer = $g.sell
            $azLine.totalReseller = $g.buy
            $azLine.totalList = $g.sell
            $azLines.Add($azLine)
        }

        $azMonth.lines = $azLines.ToArray()
        return $azMonth
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "Error in GetAzureConsumptionMonthSplit: $($_.Exception.Message)"
        return $null
    }
}

function Get-PreviousMonthSentAmount {
    param($monthFilter)

    $sentAmount = 0.00

    try {
        #This takes the month filter passed by the UI and reduces the months by 1 and formats it for the partition key for the "AzureBillingChargesSent" table.
        $monthFilter = $monthFilter.AddMonths(-1).ToString('yyyy-MM-28')

        $table = Get-CIPPTable -tablename AzureBillingChargesSent


        $sentFilter = "PartitionKey eq '$monthFilter'"
        $sentData = Get-CIPPAzDataTableEntity @table -filter $sentFilter

        if ($null -eq $sentData) {
            return $sentAmount
        }

        $sentAmount = (($sentData | Measure-Object -Property price -Sum).Sum).ToString("0.00")
        return $sentAmount
    }
    catch {
        Write-LogMessage -sev Error -API 'Azure Billing' -message "Error in Get-PreviousMonthSentAmount: $($_.Exception.Message)"
        return $sentAmount;
    }
}

function ConvertFrom-ArrowHeadersLines {
    param($data)

    if (-not $data.headers -or -not $data.lines) {
        Write-Host "ConvertFrom-ArrowHeadersLines did not receive a data.headers[]; data.lines[] object"
        return @()
    }

    $headers = @($data.headers)
    foreach($line in $data.lines){
        $obj = [ordered]@{}
        for($i = 0; $i -lt $headers.Count; $i++){
            $obj[$headers[$i]] = $line[$i]
        }
        [PSCustomObject]$obj
    }
}

function Get-ArrowConsumptionLines {
    param(
        [string]$License,
        [string]$Period,
        [int]$PerPage = 2000, # This is the max the API provides
        [int]$MaxPages = 500, # API limit to 1m rows.
        [Parameter(Mandatory = $true)]$hdrAuth
    )

    $all = [System.Collections.Generic.List[object]]::new()
    $page = 1

    do {
        $uriSuffix = "/index.php/api/consumption/line/license/$($License)/$($Period)?page=$($page)&perPage=$($PerPage)"
        $resp = Invoke-RestMethod -Uri ($baseURI + $uriSuffix) -Method "GET" `
            -ContentType "application/json" `
            -Headers $hdrAuth

        $pageLines = @(ConvertFrom-ArrowHeadersLines -data $resp.data)
        foreach($l in $pageLines) { $all.Add($l) }
        $page++
    }
    while ($pageLines.Count -eq $PerPage -and $page -le $MaxPages)

    if($page -gt $MaxPages){
        Write-LogMessage -sev Warning -API 'Azure Billing' -message "Line V2 for $License & $Period hit $MaxPages page cap. Consumption may be truncated"
    }
    return $all
}

function ConvertTo-ArrowDecimal {
    param($Value)

    if($null -eq $Value -or "$Value" -eq 'null' -or "$Value" -eq '') { return [decimal]0 }
    $d = $Value -as [decimal]
    if($null -eq $d){ return [decimal]0 }
    return $d
}

function Test-ArrowMonthlyConsumptionValid {
    param(
        $Response,
        [string]$ReportPeriod
    )

    if($null -eq $Response){
        return @{ IsValid = $false; Reason = 'No response from Arrow' }
    }

    $lines = ConvertFrom-ArrowHeadersLines -Data $Response.data
    $line = $lines | Where-Object { $_.'Report Period' -eq $ReportPeriod } | Select-Object -First 1

    if($null -eq $line){
        return @{ IsValid = $false; Reason = "No line for report period $ReportPeriod" }
    }

    # 'null' string means arrow couldn't aggregate the value consistently for the period...
    $sell = $line.'Total sell price'
    if($null -eq $sell -or "$sell" -eq 'null' -or $null -eq ($sell -as [decimal])){
        return @{ IsValid = $false; Reason = "Total sell price is null/non-numeric"; Line = $line }
    }
    return @{ IsValid = $true; Reason = 'ok'; Line = $line }
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
