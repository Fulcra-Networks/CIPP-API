function Invoke-SharePointUsageCollection {
    <#
    .SYNOPSIS
    Collects SharePoint site usage data for a tenant and stores it in Azure Table Storage.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        $UsageData = New-GraphGetRequest `
            -uri "https://graph.microsoft.com/beta/reports/getSharePointSiteUsageDetail(period='D7')?`$format=application/json&`$top=999" `
            -tenantid $TenantFilter `
            -AsApp $true

        if (-not $UsageData) {
            Write-LogMessage -API 'SharePointUsageReporting' -tenant $TenantFilter -message 'No SharePoint usage data returned' -sev Info
            return "No SharePoint usage data returned for $TenantFilter"
        }

        $Table = Get-CIPPTable -TableName 'SharePointUsageReporting'

        foreach ($Site in $UsageData) {
            $ReportDate = $Site.reportRefreshDate  # e.g. "2026-02-12"
            $SiteId = $Site.siteId

            if (-not $SiteId -or -not $ReportDate) { continue }

            $Entity = @{
                PartitionKey             = $TenantFilter
                RowKey                   = "$($SiteId)_$($ReportDate)"
                ReportDate               = $ReportDate
                SiteId                   = $SiteId
                SiteUrl                  = [string]($Site.siteUrl ?? '')
                OwnerDisplayName         = [string]($Site.ownerDisplayName ?? '')
                OwnerPrincipalName       = [string]($Site.ownerPrincipalName ?? '')
                IsDeleted                = [string]($Site.isDeleted ?? 'false')
                LastActivityDate         = [string]($Site.lastActivityDate ?? '')
                FileCount                = [int]($Site.fileCount ?? 0)
                ActiveFileCount          = [int]($Site.activeFileCount ?? 0)
                PageViewCount            = [int]($Site.pageViewCount ?? 0)
                VisitedPageCount         = [int]($Site.visitedPageCount ?? 0)
                StorageUsedInBytes       = [long]($Site.storageUsedInBytes ?? 0)
                StorageAllocatedInBytes  = [long]($Site.storageAllocatedInBytes ?? 0)
                RootWebTemplate          = [string]($Site.rootWebTemplate ?? '')
                ReportPeriod             = [string]($Site.reportPeriod ?? '7')
            }

            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        }

        # Collect tenant-level SharePoint quota snapshot
        try {
            $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
            $extraHeaders = @{
                'Accept' = 'application/json'
            }
            $SharePointQuota = (New-GraphGetRequest -extraHeaders $extraHeaders -scope "$($SharePointInfo.AdminUrl)/.default" -tenantid $TenantFilter -uri "$($SharePointInfo.AdminUrl)/_api/StorageQuotas()?api-version=1.3.2") | Sort-Object -Property GeoUsedStorageMB -Descending | Select-Object -First 1

            if ($SharePointQuota) {
                $QuotaDate = $UsageData[0].reportRefreshDate ?? (Get-Date -Format 'yyyy-MM-dd')
                $QuotaEntity = @{
                    PartitionKey     = $TenantFilter
                    RowKey           = "QUOTA_$($QuotaDate)"
                    ReportDate       = $QuotaDate
                    GeoUsedStorageMB = [long]$SharePointQuota.GeoUsedStorageMB
                    TenantStorageMB  = [long]$SharePointQuota.TenantStorageMB
                    UsedPercentage   = [int](($SharePointQuota.GeoUsedStorageMB / $SharePointQuota.TenantStorageMB) * 100)
                    RecordType       = 'Quota'
                }
                Add-CIPPAzDataTableEntity @Table -Entity $QuotaEntity -Force
            }
        } catch {
            Write-LogMessage -API 'SharePointUsageReporting' -tenant $TenantFilter -message "Error collecting quota: $($_.Exception.Message)" -sev Warning
        }

        $Count = @($UsageData).Count
        Write-LogMessage -API 'SharePointUsageReporting' -tenant $TenantFilter -message "Stored SharePoint usage for $Count sites" -sev Info
        return "Stored SharePoint usage for $Count sites in $TenantFilter"
    } catch {
        Write-LogMessage -API 'SharePointUsageReporting' -tenant $TenantFilter -message "Error collecting usage: $($_.Exception.Message)" -sev Error
        throw
    }
}
