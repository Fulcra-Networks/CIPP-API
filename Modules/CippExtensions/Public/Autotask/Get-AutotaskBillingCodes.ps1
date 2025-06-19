function Get-AutotaskBillingCodes {
    [CmdletBinding()]
    param ()

    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).Autotask

        Get-AutotaskToken -configuration $Configuration | Out-Null
        $codes = Get-AutotaskAPIResource -Resource BillingCodes -SearchQuery "{'filter':[{'op':'eq','field':'isActive','value':true},{'op':'eq','field':'billingCodeType','value':0},{'op':'eq','field':'usetype','value':4},{'op':'eq','field':'taxCategoryID','value':2}]}"
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }

        Write-LogMessage -Message "Could not get Autotask billing codes: $Message " -sev Error -tenant 'CIPP' -API 'AutotaskBillingCodes'
        $codes = @(@{name = "Could not get Autotask billing codes: $Message" })
    }
    return $codes
}
