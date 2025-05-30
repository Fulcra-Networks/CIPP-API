using namespace System.Net

Function Invoke-ExecExtensionSync {
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

    switch ($Request.Query.Extension) {
        'Gradient' {
            try {
                Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message 'Starting billing processing.' -sev Info
                $Table = Get-CIPPTable -TableName Extensionsconfig
                $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10

                foreach ($ConfigItem in $Configuration.psobject.properties.name) {
                    switch ($ConfigItem) {
                        'Gradient' {
                            If ($Configuration.Gradient.enabled -and $Configuration.Gradient.BillingEnabled) {
                                $ProcessorQueue = Get-CIPPTable -TableName 'ProcessorQueue'
                                $ProcessorFunction = [PSCustomObject]@{
                                    PartitionKey = 'Function'
                                    RowKey       = 'New-GradientServiceSyncRun'
                                    FunctionName = 'New-GradientServiceSyncRun'
                                }
                                Add-AzDataTableEntity @ProcessorQueue -Entity $ProcessorFunction -Force
                                $Results = [pscustomobject]@{'Results' = 'Successfully queued Gradient Sync' }
                            }
                        }
                    }
                }
            } catch {
                $Results = [pscustomobject]@{'Results' = "Could not start Gradient Sync: $($_.Exception.Message)" }

                Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message "Could not start billing processing $($_.Exception.Message)" -sev Error
            }
        }

        'NinjaOne' {
            try {
                $Table = Get-CIPPTable -TableName NinjaOneSettings

                $CIPPMapping = Get-CIPPTable -TableName CippMapping
                $Filter = "PartitionKey eq 'NinjaOneMapping'"
                $TenantsToProcess = Get-AzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.IntegrationId -and $_.IntegrationId -ne '' }

                if ($Request.Query.TenantID) {
                    $Tenant = $TenantsToProcess | Where-Object { $_.RowKey -eq $Request.Query.TenantID }
                    if (($Tenant | Measure-Object).count -eq 1) {
                        $Batch = [PSCustomObject]@{
                            'NinjaAction'  = 'SyncTenant'
                            'MappedTenant' = $Tenant
                            'FunctionName' = 'NinjaOneQueue'
                        }
                        $InputObject = [PSCustomObject]@{
                            OrchestratorName = 'NinjaOneOrchestrator'
                            Batch            = @($Batch)
                        }
                        #Write-Host ($InputObject | ConvertTo-Json)
                        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)

                        $Results = [pscustomobject]@{'Results' = "NinjaOne Synchronization Queued for $($Tenant.IntegrationName)" }
                    } else {
                        $Results = [pscustomobject]@{'Results' = 'Tenant was not found.' }
                    }

                } else {
                    $Batch = [PSCustomObject]@{
                        'NinjaAction'  = 'SyncTenants'
                        'FunctionName' = 'NinjaOneQueue'
                    }
                    $InputObject = [PSCustomObject]@{
                        OrchestratorName = 'NinjaOneOrchestrator'
                        Batch            = @($Batch)
                    }
                    #Write-Host ($InputObject | ConvertTo-Json)
                    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                    Write-Host "Started permissions orchestration with ID = '$InstanceId'"
                    $Results = [pscustomobject]@{'Results' = "NinjaOne Synchronization Queuing $(($TenantsToProcess | Measure-Object).count) Tenants" }

                }
            } catch {
                $Results = [pscustomobject]@{'Results' = "Could not start NinjaOne Sync: $($_.Exception.Message)" }
                Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message "Could not start NinjaOne Sync $($_.Exception.Message)" -sev Error
            }
        }
        'Hudu' {
            Register-CIPPExtensionScheduledTasks -Reschedule
            $Results = [pscustomobject]@{'Results' = 'Extension sync tasks have been rescheduled and will start within 15 minutes' }
        }

    }

    if ($Request.Query.Extension -eq 'IronScales') {
        Write-LogMessage -API 'IronScales' -tenant 'none' -message 'Force Sync Requested for IronScales' -sev Info
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10
        if(!$Configuration.IronScales.enabled) {
            $Results = [PSCustomObject]@{'Results' = 'IronScales is not enabled.'}
        }            
        else {
            Push-OutputBinding -Name ironscalesqueue -Value 'LetsGo'
            $Results = [pscustomobject]@{'Results' = 'Succesfully started IronScales Sync' }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
