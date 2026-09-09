<#
.SYNOPSIS
    Sets the API authentication information.
.DESCRIPTION
 Sets the API Authentication headers, and automatically tries to find the correct URL based on your username.
.EXAMPLE
    PS C:\> Add-AutotaskAPIAuth -ApiIntegrationcode 'ABCDEFGH00100244MMEEE333' -credentials $Creds
    Creates header information for Autotask API.
.INPUTS
    -ApiIntegrationcode: The API Integration code found in Autotask
    -Credentials : The API user credentials
.OUTPUTS
    none
.NOTES
    Function might be changed at release of new API.
#>
function Add-AutotaskAPIAuth (
    [Parameter(Mandatory = $true)]$ApiIntegrationcode,
    [Parameter(Mandatory = $true)][PSCredential]$credentials
) {
    #We convert the securestring...back to a normal string :'( Why basic auth AT? why?!
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credentials.Password)
    $Secret = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
    $Script:AutotaskAuthHeader = @{
        'ApiIntegrationcode' = $ApiIntegrationcode
        'UserName'           = $credentials.UserName
        'Secret'             = $secret
        'Content-Type'       = 'application/json'
    }
    write-host "Retrieving webservices URI based on username" -ForegroundColor Green
    try {
        # The bundled swagger (v1.json) only describes /V1.0/ paths, so the zone lookup must use
        # V1.0 as well. Autotask now advertises "V2.0" in versioninformation, but
        # /V2.0/zoneInformation returns 404 - taking the *last* advertised version breaks auth.
        $ApiVersions = (Invoke-RestMethod -Uri "https://webservices2.autotask.net/atservicesrest/versioninformation").apiVersions
        $Version = $ApiVersions | Where-Object { $_ -match '^V?1\.0$' } | Select-Object -First 1
        if (-not $Version) { $Version = 'V1.0' }
        $AutotaskBaseURI = Invoke-RestMethod -Uri "https://webservices2.autotask.net/atservicesrest/$($Version)/zoneInformation?user=$($Script:AutotaskAuthHeader.UserName)"
        write-host "Setting AutotaskBaseURI to $($AutotaskBaseURI.url) using version $Version" -ForegroundColor green
        Add-AutotaskBaseURI -BaseURI $AutotaskBaseURI.url.Trim('/')
    }
    catch {
        # Rethrow: silently returning here leaves $Script:*Parameter unset, which makes the
        # -Resource dynamic parameter disappear from every cmdlet in this module. Callers then
        # see "A parameter cannot be found that matches parameter name 'Resource'" instead of
        # the actual auth failure.
        throw "Could not retrieve Autotask baseuri (version '$Version', user '$($Script:AutotaskAuthHeader.UserName)'). E-mail address might be incorrect, or you can set the baseuri manually via Add-AutotaskBaseURI. $($_.Exception.Message)"
    }

}