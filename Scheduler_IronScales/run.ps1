# Input bindings are passed in via param block.
param($Timer)

try {
    Write-LogMessage -API "Scheduler_IronScales" -tenant "none" -message "Starting IronScales processing from timer." -sev Info

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10
    if(!$Configuration.IronScales.enabled) {
        return
    }

    Get-IronScalesIncidents -configuration $Configuration
}
catch {
    Write-Host $($_.Exception.Message)
    Write-LogMessage -API "Scheduler_IronScales" -tenant "none" -message "BBBBCould not start IronScales processing $($_.Exception.Message)" -sev Error
}
