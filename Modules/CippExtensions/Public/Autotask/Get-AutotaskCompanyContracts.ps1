function Get-AutotaskCompanyContracts {
    [CmdletBinding()]
    param ($CompanyId)

    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).Autotask

        Get-AutotaskToken -configuration $Configuration | Out-Null
        $Contracts = Get-AutotaskAPIResource -Resource Contracts -SearchQuery "{'filter':[{'op':'eq','field':'companyId','value':$CompanyId},{'op':'eq','field':'status','value':1},{'op':'eq','field':'contractType','value':7}]}"
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }

        Write-LogMessage -Message "Could not get Company contracts, error: $Message " -sev Error -tenant 'CIPP' -API 'AutotaskContracts'
        $Contracts = @(@{name = "Could not get Autotask contracts, error: $Message" })
    }
    return $Contracts
}
