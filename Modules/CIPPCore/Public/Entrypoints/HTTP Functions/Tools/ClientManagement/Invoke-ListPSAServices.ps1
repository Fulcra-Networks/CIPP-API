using namespace System.Net

function Invoke-ListPSAServices {
    [CmdletBinding()]
    param($Request,$TriggerMetadata)

    $services = Get-AutotaskServices
    $result = $services | ForEach-Object {
        [PSCustomObject]@{
            id = $_.id
            name = $_.name
        }
    }

    return ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @($result)
    })
}
