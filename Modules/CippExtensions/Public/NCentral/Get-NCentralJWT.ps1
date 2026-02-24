Function Get-NCentralJWT {
    if (!$ENV:NCentralJWT) {
        $null = Connect-AzAccount -Identity
        $ClientSecret = (Get-CIPPKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'NCentral' -AsPlainText)
    } else {
        $ClientSecret = $ENV:NCentralJWT
    }

    return $ClientSecret
}
