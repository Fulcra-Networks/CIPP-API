function Get-AutotaskDevices {
    [CmdletBinding()]
    param($tenantId)

    $ExtensionMappings = Get-ExtensionMapping -Extension 'Autotask'

    try{
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).Autotask

        $ATCustomerID = $ExtensionMappings | Where-Object { $_.rowKey -eq $tenantId } | Select-Object -ExpandProperty IntegrationId

        Get-AutotaskToken -configuration $Configuration | Out-Null


        $customerContracts = Get-AutotaskAPIResource -resource Contracts -SimpleSearch "companyid eq $($ATCustomerID)"


        #Retrieve all Active, Workstation type devices for the tenant
        $filter = [PSCustomObject]@{
            "filter"=@(
                [PSCustomObject]@{op="eq";field="productID";value="29683512"}
                [PSCustomObject]@{op="eq";field="configurationItemType";value="1"},
                [PSCustomObject]@{op="eq";field="isActive";value="true"},
                [PSCustomObject]@{op="eq";field="companyID";value="$ATCustomerID"}
            )
        }

        $confItems = Get-AutotaskAPIResource -Resource configurationItems -SearchQuery ($filter|ConvertTo-Json -Depth 10 -Compress)
    }
    catch{
        Write-LogMessage -Message "Could not get Autotask Devices, error: $($_.Exception.Message)" -sev Error -tenant 'CIPP' -API 'AutotaskDevices'
    }

    #Structure the results for consistency across other Extensions.
    $results = @()
    foreach($conf in $confItems) {
        $devInfo = ($conf.userDefinedFields|Where-Object { $_.name -eq 'N-central Device ID'})

        $confContract = ""
        if(![String]::IsNullOrEmpty($conf.contractID)){
            $confContract = $customerContracts | Where-Object { $_.id -eq $conf.contractID}
        }

        $results += [PSCustomObject]@{
            name         = $conf.referenceTitle
            serialNumber = $conf.serialNumber
            psaId        = $conf.id
            rmmId        = $devInfo.value
            contract     = $confContract.contractName
        }
    }

    return $results
}
