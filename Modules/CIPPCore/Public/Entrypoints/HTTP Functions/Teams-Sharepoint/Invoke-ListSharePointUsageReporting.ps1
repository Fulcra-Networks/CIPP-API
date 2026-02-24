function Invoke-ListSharePointUsageReporting {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $StartDate = $Request.Query.StartDate
    $EndDate = $Request.Query.EndDate

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'tenantFilter is required'
            })
    }

    try {
        $Table = Get-CIPPTable -TableName 'SharePointUsageReporting'

        $FilterConditions = [System.Collections.Generic.List[string]]::new()
        $FilterConditions.Add("PartitionKey eq '$TenantFilter'")

        if ($StartDate) {
            $FilterConditions.Add("ReportDate ge '$StartDate'")
        }
        if ($EndDate) {
            $FilterConditions.Add("ReportDate le '$EndDate'")
        }

        $Table.Filter = $FilterConditions -join ' and '
        $AllRows = Get-CIPPAzDataTableEntity @Table
        $QuotaRows = @($AllRows | Where-Object { $_.RowKey -like 'QUOTA_*' })

        $Results = @($AllRows | Where-Object { $_.RowKey -notlike 'QUOTA_*' }) | ForEach-Object {
            [PSCustomObject]@{
                SiteId                      = $_.SiteId
                SiteUrl                     = $_.SiteUrl
                OwnerDisplayName            = $_.OwnerDisplayName
                OwnerPrincipalName          = $_.OwnerPrincipalName
                IsDeleted                   = $_.IsDeleted
                LastActivityDate            = $_.LastActivityDate
                ReportDate                  = $_.ReportDate
                FileCount                   = $_.FileCount
                ActiveFileCount             = $_.ActiveFileCount
                PageViewCount               = $_.PageViewCount
                VisitedPageCount            = $_.VisitedPageCount
                StorageUsedInBytes          = $_.StorageUsedInBytes
                StorageAllocatedInBytes     = $_.StorageAllocatedInBytes
                StorageUsedInGigabytes      = [math]::round($_.StorageUsedInBytes / 1GB, 2)
                StorageAllocatedInGigabytes = [math]::round($_.StorageAllocatedInBytes / 1GB, 2)
                RootWebTemplate             = $_.RootWebTemplate
                ReportPeriod                = $_.ReportPeriod
            }
        }

        $QuotaHistory = @($QuotaRows | Sort-Object -Property ReportDate | ForEach-Object {
                [PSCustomObject]@{
                    ReportDate       = $_.ReportDate
                    GeoUsedStorageMB = $_.GeoUsedStorageMB
                    TenantStorageMB  = $_.TenantStorageMB
                    UsedPercentage   = $_.UsedPercentage
                }
            })

        $LatestQuota = $QuotaHistory | Select-Object -Last 1

        $Body = @{
            Results  = @($Results | Sort-Object -Property ReportDate, SiteUrl)
            Metadata = @{
                Count                       = @($Results).Count
                TenantFilter                = $TenantFilter
                StartDate                   = $StartDate
                EndDate                     = $EndDate
                TotalStorageUsedInGigabytes = [math]::round(($Results | Measure-Object -Property StorageUsedInBytes -Sum).Sum / 1GB, 2)
                Quota                       = $LatestQuota
                QuotaHistory                = $QuotaHistory
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{
            Results = @()
            Error   = Get-NormalizedError -Message $_.Exception.Message
        }
        Write-LogMessage -API 'SharePointUsageReporting' -tenant $TenantFilter -message "Error retrieving usage: $($_.Exception.Message)" -sev Error
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
