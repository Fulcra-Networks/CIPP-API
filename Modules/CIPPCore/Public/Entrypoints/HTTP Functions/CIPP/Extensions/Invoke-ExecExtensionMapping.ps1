using namespace System.Net

Function Invoke-ExecExtensionMapping {
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

    $Table = Get-CIPPTable -TableName CippMapping

    Write-LogMessage -Message "Extension Mapping: $($Request.Query.List)" -sev Info -tenant 'CIPP' -API $APIName

    if ($Request.Query.List) {
        switch ($Request.Query.List) {
            'Autotask' {
                $Body = Get-AutotaskMapping -CIPPMapping $Table
            }
            'AutotaskManaged' {
                $Body = Get-AutotaskManaged -CIPPMapping $Table
            }
            'IronScales' {
                $Body = Get-IronScalesMapping -CIPPMapping $Table
            }
            'NCentral'{
                $Body = Get-NCentralMapping -CIPPMapping $Table
            }
            'HaloPSA' {
                $Result = Get-HaloMapping -CIPPMapping $Table
            }
            'NinjaOne' {
                $Result = Get-NinjaOneOrgMapping -CIPPMapping $Table
            }
            'NinjaOneFields' {
                $Result = Get-NinjaOneFieldMapping -CIPPMapping $Table
            }
            'Hudu' {
                $Result = Get-HuduMapping -CIPPMapping $Table
            }
            'HuduFields' {
                $Result = Get-HuduFieldMapping -CIPPMapping $Table
            }
            'Sherweb' {
                $Result = Get-SherwebMapping -CIPPMapping $Table
            }
            'HaloPSAFields' {
                $TicketTypes = Get-HaloTicketType
                $Result = @{'TicketTypes' = $TicketTypes }
            }
            'PWPushFields' {
                $Accounts = Get-PwPushAccount
                $Result = @{
                    'Accounts' = $Accounts
                }
            }
        }
    }

    try {
        if ($Request.Query.AddMapping) {
            switch ($Request.Query.AddMapping) {
                'Autotask' {
                    $Body = Set-AutotaskMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'AutotaskManaged' {
                    $Body = Set-AutotaskManaged -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'IronScales' {
                    $Body = Set-IronScalesMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'NCentral'{
                    $Body = Set-NCentralMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'Sherweb' {
                    $Result = Set-SherwebMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'HaloPSA' {
                    $Result = Set-HaloMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'NinjaOne' {
                    $Result = Set-NinjaOneOrgMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                    Register-CIPPExtensionScheduledTasks
                }
                'NinjaOneFields' {
                    $Result = Set-NinjaOneFieldMapping -CIPPMapping $Table -APIName $APIName -Request $Request -TriggerMetadata $TriggerMetadata
                    Register-CIPPExtensionScheduledTasks
                }
                'Hudu' {
                    $Result = Set-HuduMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                    Register-CIPPExtensionScheduledTasks
                }
                'HuduFields' {
                    $Result = Set-ExtensionFieldMapping -CIPPMapping $Table -APIName $APIName -Request $Request -Extension 'Hudu'
                    Register-CIPPExtensionScheduledTasks
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Mapping API failed. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    try {
        if ($Request.Query.AutoMapping) {
            switch ($Request.Query.AutoMapping) {
                'NinjaOne' {
                    $Batch = [PSCustomObject]@{
                        'NinjaAction'  = 'StartAutoMapping'
                        'FunctionName' = 'NinjaOneQueue'
                    }
                    $InputObject = [PSCustomObject]@{
                        OrchestratorName = 'NinjaOneOrchestrator'
                        Batch            = @($Batch)
                    }
                    #Write-Host ($InputObject | ConvertTo-Json)
                    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                    Write-Host "Started permissions orchestration with ID = '$InstanceId'"
                    $Result = 'AutoMapping Request has been queued. Exact name matches will appear first and matches on device names and serials will take longer. Please check the CIPP Logbook and refresh the page once complete.'
                }

            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Mapping API failed. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Result
        })

}
