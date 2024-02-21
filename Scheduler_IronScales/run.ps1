# Input bindings are passed in via param block.
param($Timer)

try {
    Write-LogMessage -API "IronScales_Tickets" -tenant "none" -message "Starting IronScales processing." -sev Info

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10
    if(!$Configuration.IronScales.enabled) {
        return
    }
        
    Write-Host "Getting IronScales Incidents"
    Get-IronScalesIncidents -configuration $Configuration.IronScales
}
catch {
    Write-Host $($_.Exception.Message)
    Write-LogMessage -API "Scheduler_IronScales" -tenant "none" -message "Could not start IronScales processing $($_.Exception.Message)" -sev Error
}
