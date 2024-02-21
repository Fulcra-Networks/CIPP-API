function Get-IronScalesToken {
    [CmdletBinding()]
    param($Configuration)

    $is_endpoint = @{
        auth= "/get-token/"
        campaigns="/campaigns/"
        companies= "/company/"
        incidents = "/incident/"
    }


    if (!$ENV:IronScalesSecret) {
        $null = Connect-AzAccount -Identity
        $ClientSecret = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'IronScales' -AsPlainText)
    } else {
        $ClientSecret = $ENV:IronScalesSecret
    }

    #TODO: Move scopes to config
    $scopes = @("partner.all")
    $body = @{
        "key" = "$($ClientSecret)"
        "scopes" = $scopes
    }
    try {
        $resp = Invoke-RestMethod -Method Post -ContentType "application/json" -Uri "$($Configuration.ApiHost+$is_endpoint.auth)" -Body $($body|ConvertTo-Json) 
        return $resp.jwt
    }
    catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }
        Write-LogMessage -Message $Message -sev error -API 'IronScales'
    }
    return $null
}