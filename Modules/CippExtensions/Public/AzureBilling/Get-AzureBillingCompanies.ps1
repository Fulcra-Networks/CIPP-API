function Get-AzureBillingCompanies {
    [CmdletBinding()]
    param()

    $CtxExtensionCfg = Get-CIPPTable -TableName Extensionsconfig
    $CfgExtensionTbl = (Get-CIPPAzDataTableEntity @CtxExtensionCfg).config | ConvertFrom-Json -Depth 10

    $hdrAuth = Get-AzureBillingToken $CfgExtensionTbl
    if($null -eq $hdrAuth) {
        write-host "$('*'*60) Did not get billing token...."
        return @({reference="0000000"; CompanyName="Error getting token"})
    }

    [string]$baseURI = ''

    if(-not $CfgExtensionTbl.AzureBilling){
        write-host "$('*'*60) No extension configuration...."
       return @({reference="0000000"; CompanyName="Error Azure billing extension configuration not found"})
    }

    $baseURI = $CfgExtensionTbl.AzureBilling.APIHost


    try {
        $uriCustomers = "$($baseURI)/index.php/api/customers"

        $resp = Invoke-RestMethod -Uri $uriCustomers -Method "GET" `
            -ContentType "application/json" `
            -Headers $hdrAuth

        write-host "$('*'*60) $($resp.data.customers)"

        return $resp.data.customers
    }
    catch {
        write-host "$('*'*60) Exception $($_.Exception.Message)...."
        Write-LogMessage -sev Error -API "Azure Billing" -message "$($_.Exception.Message)"
        return @({reference="0000000"; CompanyName="Error getting Azure customers from API."})
    }
}
