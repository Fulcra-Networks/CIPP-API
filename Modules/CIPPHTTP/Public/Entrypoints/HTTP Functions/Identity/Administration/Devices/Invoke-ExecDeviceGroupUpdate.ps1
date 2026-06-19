function Invoke-ExecDeviceGroupUpdate {
    param($Request, $TriggerMetadata)

    <# Expected JSON
    {
    "tenantFilter": "ahg-group.com",
    "action": "!Add"
    "addMember": [
        {
            "label": "SomePCName",
            "addedFields": {
                "deviceid": "00000000-0000-0000-0000-000000000000"
            },
            "value": "00000000-0000-0000-0000-000000000000"
        }
    ],
    "groupId": {
        "label": "GroupName",
        "addedFields": {
            "groupName": "GroupName",
            "groupType": "Security"
        },
        "value": "00000000-0000-0000-0000-000000000000"
    }
    }
    #>

    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    $Action = $Request.Body.action
    $GroupID = $Request.Body.groupId.value

    if ($Action -eq '!Add') {
        #https://learn.microsoft.com/en-us/graph/api/group-post-members?view=graph-rest-beta&tabs=http

        if ($Request.Body.addMember.Count -gt 1) {
            $members = $Request.Body.addMember | ForEach-Object {
                "https://graph.microsoft.com/beta/devices/$($_.value)"
            }
            $url = "https://graph.microsoft.com/beta/groups/$($GroupID)"
            $ActionBody = @{"members@odata.bind" = $members } | ConvertTo-Json -Depth 10 -Compress
            Write-Host "$('~'*60) $ActionBody"
            $Result = New-GraphPOSTRequest -uri $Url -type PATCH -tenantid $TenantFilter -body $ActionBody
        }
        else {
            $url = "https://graph.microsoft.com/beta/groups/$groupId/members/`$ref"
            $ActionBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/devices/$($Request.Body.addMember[0].Value)" } | ConvertTo-Json -Compress
            $Result = New-GraphPOSTRequest -uri $Url -type POST -tenantid $TenantFilter -body $ActionBody
        }
    }
    elseif ($Action -eq '!Remove') {
        if($Request.Body.addMember.length -ne 1){
            return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = @{'Results' = "Device ID missing from request." }
            })
        }

        #https://learn.microsoft.com/en-us/graph/api/group-delete-members?view=graph-rest-beta&tabs=http
        $DeviceID = $Request.Body.addMember[0].value
        $url = "https://graph.microsoft.com/beta/groups/$GroupId/members/$DeviceID/`$ref"
        $Result = New-GraphPOSTRequest -uri $Url -type DELETE -tenantid $TenantFilter -body ''
    }
    else {
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = @{'Results' = "$($Request.body.action) is not allowed." }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::OK
            Body       = @{ 'Results' = $Result }
        })
}
