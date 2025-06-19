using namespace System.Net

Function Invoke-ListPSACompanies {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10

    foreach ($ConfigItem in $Configuration.psobject.properties.name) {
        switch ($ConfigItem) {
            'Autotask' {
                If ($Configuration.Autotask.enabled) {
                    $Result = Get-AutotaskCompanies
                    $Result = $Result | Select-Object { $_.id, $_.companyName}
                }
            }
            'HaloPSA' {
                $Result = $null
            }
            'NinjaOne' {
                $Result = $null
            }
        }
    }

    Write-Host "$('*'*60)-$($Result|ConvertTo-JSON -Depth 5)"

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Result)
        })

}
