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


    $Table = Get-CIPPTable -TableName CippMapping

    if ($Request.Query.List) {
        switch ($Request.Query.List) {
            'Autotask' {
                $Result = Get-AutotaskMapping -CIPPMapping $Table
            }
            'AutotaskManaged' {
                $Result = Get-AutotaskManaged -CIPPMapping $Table
            }
            'IronScales' {
                $Result = Get-IronScalesMapping -CIPPMapping $Table
            }
            'NCentral' {
                $Result = Get-NCentralMapping -CIPPMapping $Table
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
                $Outcomes = Get-HaloTicketOutcome
                $Result = @{
                    'TicketTypes' = $TicketTypes
                    'Outcomes'    = $Outcomes
                }
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
                    $Result = Set-AutotaskMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'AutotaskManaged' {
                    $Result = Set-AutotaskManaged -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'IronScales' {
                    $Result = Set-IronScalesMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'NCentral' {
                    $Result = Set-NCentralMapping -CIPPMapping $Table -APIName $APIName -Request $Request
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
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Mapping API failed. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Result
        })

}
