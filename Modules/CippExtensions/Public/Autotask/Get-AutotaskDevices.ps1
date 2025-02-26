function Get-AutotaskDevices {
    [CmdletBinding()]
    param($tenantId)

    $ExtensionMappings = Get-ExtensionMapping -Extension 'Autotask'

    try{
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).Autotask

        $AtCustID = $ExtensionMappings | Where-Object { $_.rowId -eq $tenantId } | Select-Object -ExpandProperty IntegrationId

        Get-AutotaskToken -configuration $Configuration | Out-Null

        #Retrieve all Active, Workstation type devices for the tenant
        $filter = [PSCustomObject]@{
            "filter"=@(
                [PSCustomObject]@{op="eq";field="productID";value="29683512"}
                [PSCustomObject]@{op="eq";field="configurationItemType";value="1"},
                [PSCustomObject]@{op="eq";field="isActive";value="true"},
                [PSCustomObject]@{op="eq";field="companyID";value="$AtCustID"}
            )
        }

        $confItems = Get-AutotaskAPIResource -Resource configurationItems -SearchQuery ($filter|ConvertTo-Json -Depth 10 -Compress)
    }
    catch{
        Write-LogMessage -Message "Could not get Autotask Devices, error: $($_.Exception.Message)" -Level Error -tenant 'CIPP' -API 'AutotaskDevices'
    }

    #Structure the results for consistency across other Extensions.
    $results = $confItems | Sort-Object -Property name | ForEach-Object {
        $devInfo = ($_.userDefinedFields|Where-Object { $_.name -eq 'N-central Device ID'})
        [PSCustomObject]@{
            name         = $_.referenceTitle
            serialNumber = $_.serialNumber
            rmmId        = $devInfo.value
        }
    }

    return $results
}
