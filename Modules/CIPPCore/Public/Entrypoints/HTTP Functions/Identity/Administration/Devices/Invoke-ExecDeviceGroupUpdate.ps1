function Invoke-ExecDeviceGroupUpdate {
    param($Request, $TriggerMetadata)

    <#
    {
    "tenantFilter": "ahg-group.com",
    "action": "!Add"
    "addMember": [
        {
            "label": "DESKTOP-N01BP4E",
            "addedFields": {
                "deviceid": "207436d7-d58b-4118-8283-b54d396a8d43"
            },
            "value": "3bf6b121-90b6-44d7-81a9-44222b140a59"
        }
    ],
    "groupId": {
        "label": "ManagedPCs-BLOCK",
        "addedFields": {
            "groupName": "ManagedPCs-BLOCK",
            "groupType": "Security"
        },
        "value": "a924858f-891e-40c4-8293-420fff0e56b1"
    }
    }
    #>

    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    $Action = $Request.Body.action
    $GroupID = $Request.Body.groupId.value

    #Write-Host "$('~'*60) $($Request.Body|ConvertTo-Json -Depth 10)"
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
        if($Request.Body.addMember.lenth -ne 1){
            return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = @{'Results' = "Device ID missing from request." }
            })
        }

        #DELETE https://graph.microsoft.com/beta/groups/{group-id}/members/{directory-object-id}/$ref
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
