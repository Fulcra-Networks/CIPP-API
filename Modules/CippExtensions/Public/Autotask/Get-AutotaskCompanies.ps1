function Get-AutotaskCompanies {
    [CmdletBinding()]
    param ()

    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).Autotask

        Get-AutotaskToken -configuration $Configuration | Out-Null
        $RawAutotaskCustomers = Get-AutotaskAPIResource -Resource Companies -SearchQuery "{'filter':[{'op':'and',items:[{'op':'eq','field':'isactive','value':true},{'op':'eq','field':'companyType','value':'1'}]}]}"
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }

        Write-LogMessage -Message "Could not get Autotask Clients, error: $Message " -sev Error -tenant 'CIPP' -API 'AutotaskMapping'
        $RawAutotaskCustomers = @(@{name = "Could not get Autotask Clients, error: $Message" })
    }
    return $RawAutotaskCustomers
}
