
Function Get-AzureBillingToken {
    [CmdletBinding()]
    param($Configuration)

    $secret = GetAzureBillingSecret

    if([string]::IsNullOrEmpty($secret)){
        write-host "$('*'*60) No API secret"
        return $null
    }

    if([string]::IsNullOrEmpty($Configuration.AzureBilling.APIAuthKey)){
        write-host "$('*'*60) No API Auth Key"
        return $null
    }

    $hdrAuth = @{apiKey = $Configuration.AzureBilling.APIAuthKey; secret = $secret}

    try{
        $res = Invoke-RestMethod -Uri 'https://xsp.arrow.com/index.php/api/whoami' `
            -Method 'GET' `
            -Headers $hdrAuth

        #TODO Add to configuration
        if($res.data.companyName -ne 'FULCRA NETWORKS LLC'){
            write-host "$('*'*60) Bad response from API"
            return $null
        }
    }
    catch{
        Write-LogMessage -Sev Error -API 'Azure Billing' -Message "Error connecting to AzureBilling API. $($_.Exception.Message)"
        write-host "$('*'*60) $($_.Exception.Message)"
        return $null
    }

    return $hdrAuth
}

function GetAzureBillingSecret {
    $secret = ''

    if (!$ENV:ArrowSecret) {
        $null = Connect-AzAccount -Identity
        $secret = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'AzureBilling' -AsPlainText)
    } else {
        $secret = $ENV:ArrowSecret
    }


    return $secret
}
