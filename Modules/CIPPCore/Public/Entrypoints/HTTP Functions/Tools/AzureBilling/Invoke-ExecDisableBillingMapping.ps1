using namespace System.Net

function Invoke-ExecDisableBillingMapping {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    write-host "$('*'*60) $($Request.Query.action)ing mapping"
    write-host "$($Request|ConvertTo-JSON -Depth 10)"
    $action = $Request.Query.action.ToLower() -eq "enable"
    $mappingContext = Get-CIPPTable -tablename AzureBillingMapping

    $mappings = Get-CIPPAzDataTableEntity @mappingContext

    $mappingStrs = $Request.Query.mappingId.split('~')
    if ($mappingStrs.length -lt 2) {
        return ([httpresponsecontext]@{
                StatusCode = [HttpStatusCode]::NotModified
                Body       = @{ Result = "Invalid mapping ID" }
            })
    }

    $mapping = $mappings | Where-Object { $_.PartitionKey -eq $mappingStrs[0] -and $_.RowKey -eq $mappingStrs[1] }

    if ($mapping) {
        if ($mapping | Get-Member -Name 'IsEnabled' -MemberType Properties) { $mapping.isEnabled = $action }
        else {
            $mapping | Add-Member -NotePropertyMembers @{ isEnabled = $action }
        }
        Update-AzDataTableEntity -Force @mappingContext -Entity ([pscustomobject]$mapping)

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{Results = "Mapping updated." }
            })
    }
    else {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = @{Result = "No mapping found for $($mappingStrs[0..1])" }
            })
    }
}
