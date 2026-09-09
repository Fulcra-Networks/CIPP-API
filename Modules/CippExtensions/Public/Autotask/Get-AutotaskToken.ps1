function Get-AutotaskToken {
    [CmdletBinding()]
    param (
        $Configuration
        )

    Import-Module AutotaskAPI

    if (!$ENV:AutotaskSecret) {
        #$null = Connect-AzAccount -Identity
        $ClientSecret = (Get-CIPPKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'Autotask' -AsPlainText)
    } else {
        $ClientSecret = $ENV:AutotaskSecret
    }

    $pass = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
    [pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($Configuration.APIUser, $pass)

    try {
        Add-AutotaskAPIAuth -ApiIntegrationcode $Configuration.APIIntegrationCode -credentials $credObject
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }
        Write-LogMessage -Message $Message -sev error -API 'Autotask'
        # Without this, callers continue with an unauthenticated module whose cmdlets have no
        # -Resource dynamic parameter, producing a misleading parameter-binding error far from
        # the real cause.
        throw "Autotask authentication failed: $Message"
    }
    return $null

}
