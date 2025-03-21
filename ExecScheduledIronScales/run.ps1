param($QueueItem)

try {
    Write-LogMessage -API "ExecScheduled_IronScales" -tenant "none" -message "Starting IronScales processing.XXXX" -sev Info

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10
    if(!$Configuration.IronScales.enabled) {
        return
    }

    Get-IronScalesIncidents -configuration $Configuration.IronScales
}
catch {
    Write-Host $($_.Exception.Message)
    Write-LogMessage -API "Scheduler_IronScales" -tenant "none" -message "Could not start IronScales processing $($_.Exception.Message)" -sev Error
}
