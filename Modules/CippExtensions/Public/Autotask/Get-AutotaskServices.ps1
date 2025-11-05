function Get-AutotaskServices {
    [CmdletBinding()]
    param ()

    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).Autotask

        $searchQuery = [PSCustomObject]@{
            filter = @(
                [pscustomObject]@{
                    field = 'isActive'
                    value = $true
                    op = "eq"
                },
                [pscustomobject]@{
                    field = 'name'
                    op = 'contains'
                    value = 'Managed Services~'
                }
            )
        }

        Get-AutotaskToken -configuration $Configuration | Out-Null
        $codes = Get-AutotaskAPIResource -Resource Services -SearchQuery ($searchQuery|ConvertTo-JSON -Depth 5 -Compress)
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }

        Write-Host "$('*'*60)`n$($_.Exception.Message)"

        Write-LogMessage -Message "Could not get Autotask billing codes: $Message " -sev Error -tenant 'CIPP' -API 'AutotaskBillingCodes'
        $codes = @(@{name = "Could not get Autotask billing codes: $Message" })
    }
    return $codes
}
