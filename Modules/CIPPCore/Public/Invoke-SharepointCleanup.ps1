function Invoke-SharepointCleanup {
    [CmdletBinding()]
    param([string]$fileTypesCsv, [string]$siteUrlsCsv, [uint]$lastModifiedDays, $tenantId, [uint]$minimumFileSizeMB = 100)

    if ($null -eq $tenantId) {
        Write-LogMessage -sev Error -API "SharePointCleanup" -message "Error no tenant specified."
        return
    }

    if ($lastModifiedDays -eq 0) {
        Write-LogMessage -sev Error -API "SharePointCleanup" -message "Last modified days cannot be 0."
        return
    }

    $fileTypes = $fileTypesCsv.Split(',').Trim()
    $siteList = $siteUrlsCsv.Split(',').Trim()

    Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Parsed $($siteList.Count) site(s): $($siteList -join ' | ')"

    if ($fileTypes.Length -lt 1) {
        Write-LogMessage -sev Error -API "SharePointCleanup" -message "Error no filetypes specified."
        return
    }
    if ($siteList.Length -lt 1) {
        Write-LogMessage -sev Error -API "SharePointCleanup" -message "Error no sites specified."
        return
    }

    # Step 1: Get the APP ID & SPO Base URI for specified Tenant from config
    $Table = Get-CIPPTable -tablename 'SharePointCleanup'
    $TenantConfig = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$tenantId'"

    if ($null -eq $TenantConfig) {
        Write-LogMessage -sev Error -API 'SharePointCleanup' -message "No SharePoint cleanup configuration found for tenant: $tenantId"
        return
    }

    $AppID = $TenantConfig.RowKey
    $spoBaseURI = $TenantConfig.spoBaseUri
    $spoAdminUri = $TenantConfig.spoAdminUri

    $spoCertPw = ""

    Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Loaded config for tenant $tenantId - AppID: $AppID, Base URI: $spoBaseURI"

    # Step 2: Get the App Certificate from KeyVault (stored as a secret containing the base64-encoded PFX)
    try {
        $certBase64 = Get-CippKeyVaultSecret -Name "SpoCleanupCert-$tenantId" -AsPlainText
    } catch {
        Write-LogMessage -sev Error -API 'SharePointCleanup' -message "Failed to retrieve app certificate from KeyVault for tenant: $tenantId - $($_.Exception.Message)"
        return
    }

    # try {
    #      $spoCertPw = Get-CippKeyVaultSecret -Name "SpoCertPw" -AsPlainText
    # } catch {
    #     Write-LogMessage -sev Error -API 'SharePointCleanup' -message "Failed to retrieve certificate password from KeyVault for tenant: $tenantId - $($_.Exception.Message)"
    #     return
    # }

    if ([string]::IsNullOrWhiteSpace($certBase64)) {
        Write-LogMessage -sev Error -API 'SharePointCleanup' -message "App certificate retrieved from KeyVault is empty for tenant: $tenantId"
        return
    }

    # try {
    #     $certBytes = [Convert]::FromBase64String($certBase64)
    #     $AppCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)
    # } catch {
    #     Write-LogMessage -sev Error -API 'SharePointCleanup' -message "Failed to convert certificate from base64 for tenant: $tenantId - $($_.Exception.Message)"
    #     return
    # }

    # Step 3: Iterate sites, connecting to each
    $totalFilesFound = 0
    $totalFilesDeleted = 0
    foreach ($site in $siteList) {
        Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Processing site $($siteList.IndexOf($site) + 1)/$($siteList.Count): $site"
        try {
            $connected = Connect-ToSite -SiteUrl $site -AppID $AppID -CertificateBase64Encoded $certBase64 -TenantId $tenantId
            if (-not $connected) {
                Write-LogMessage -sev Warning -API 'SharePointCleanup' -message "Skipping site: $site - connection failed"
                continue
            }

            # Step 4: Iterate file types, retrieving target files (pre-filtered by age server-side)
            $allTargetFiles = foreach ($ext in $fileTypes) {
                Get-TargetFiles -fileExt $ext -lastModifiedDays $lastModifiedDays -minimumFileSizeBytes ($minimumFileSizeMB * 1048576) -siteUrl $site
            }

            if ($null -eq $allTargetFiles -or $allTargetFiles.Count -eq 0) {
                Write-LogMessage -sev Info -API 'SharePointCleanup' -message "No matching files found on site: $site"
                Disconnect-PnPOnline
                continue
            }

            Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Found $($allTargetFiles.Count) file(s) older than $lastModifiedDays days on site: $site"

            # Step 5: While connected, delete filtered file list
            $siteDeleted = Remove-FilesInList -deleteFiles $allTargetFiles -site $site -spoBaseURI $spoBaseURI -tenantId $tenantId

            $totalFilesFound += $allTargetFiles.Count
            $totalFilesDeleted += $siteDeleted

            Disconnect-PnPOnline
        } catch {
            Write-LogMessage -sev Error -API 'SharePointCleanup' -message "Unhandled error processing site ${site}: $($_.Exception.Message)"
            try { Disconnect-PnPOnline } catch {}
        }
    }

    Write-LogMessage -sev Info -API 'SharePointCleanup' -message "SharePoint cleanup complete for tenant $tenantId - $totalFilesDeleted/$totalFilesFound eligible file(s) processed across $($siteList.Count) site(s)"
}

function Connect-ToSite {
    <#
    .SYNOPSIS
        Connects to a SharePoint site.
    .PARAMETER SiteUrl
        The URL of the SharePoint site to connect to.
    .PARAMETER AppID
        The Azure AD App Registration Client ID.
    .PARAMETER Certificate
        The X509Certificate2 for the App Registration.
    .PARAMETER TenantId
        The tenant ID to connect to.
    .OUTPUTS
        Boolean - True if connection successful, False otherwise.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,

        [Parameter(Mandatory = $true)]
        [string]$AppID,

        [Parameter(Mandatory = $true)]
        [string]$CertificateBase64Encoded,

        [Parameter(Mandatory = $false)]
        [string]$CertificatePassword,

        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )

    try {
        $connectParams = @{
            Url                      = $SiteUrl
            ClientId                 = $AppID
            CertificateBase64Encoded = $CertificateBase64Encoded
            Tenant                   = $TenantId
        }
        if (-not [string]::IsNullOrWhiteSpace($CertificatePassword)) {
            $connectParams['CertificatePassword'] = (ConvertTo-SecureString -String $CertificatePassword -AsPlainText -Force)
        }
        Connect-PnPOnline @connectParams
        Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Connected to: $SiteUrl"
        return $true
    }
    catch {
        Write-LogMessage -sev Error -API 'SharePointCleanup' -message "Failed to connect to $SiteUrl : $($_.Exception.Message)"
        return $false
    }
}

function Get-TargetFiles {
    <#
    .SYNOPSIS
        Searches a site for files matching the given extension using SharePoint Search API.
    .DESCRIPTION
        Uses Invoke-PnPSearchQuery to find files, bypassing the list view threshold
        that affects CAML queries on large libraries (>5000 items).
    .OUTPUTS
        Array of file objects.
    #>
    param($fileExt, [int]$lastModifiedDays, [long]$minimumFileSizeBytes = 104857600, [string]$siteUrl)

    $cutoffDate = [datetime]::UtcNow.AddDays(-$lastModifiedDays).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $minimumFileSizeKB = [math]::Floor($minimumFileSizeBytes / 1024)
    $kqlQuery = "path:""$siteUrl"" AND IsDocument:true AND filetype:$fileExt AND size>$minimumFileSizeKB AND write<""$cutoffDate"""

    Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Search query: $kqlQuery"

    $targetFiles = @()
    $startRow = 0
    $pageSize = 500

    do {
        try {
            $searchResults = Invoke-PnPSearchQuery -Query $kqlQuery -StartRow $startRow -MaxResults $pageSize -SelectProperties 'FileName','Path','Size','Write','ComplianceTag','SPWebUrl' -SortList @{Write = 'Ascending'}
        } catch {
            Write-LogMessage -sev Error -API 'SharePointCleanup' -message "Search query failed at row $startRow`: $($_.Exception.Message)"
            break
        }

        if ($searchResults.ResultRows.Count -eq 0) { break }

        foreach ($row in $searchResults.ResultRows) {
            # Convert the full Path URL to a server-relative path
            $fullPath = $row['Path']
            $uri = [System.Uri]$fullPath
            $serverRelativePath = [Uri]::UnescapeDataString($uri.AbsolutePath)

            $targetFiles += [PSCustomObject]@{
                FileName      = $row['FileName']
                FilePath      = $serverRelativePath
                FileSize      = $row['Size']
                Modified      = $row['Write']
                Library       = ''
                ComplianceTag = $row['ComplianceTag']
                Id            = $null
            }
        }

        $startRow += $pageSize
    } while ($startRow -lt $searchResults.TotalRows)

    $fileCount = @($targetFiles).Count
    $top3 = @($targetFiles) | Sort-Object Modified -Descending | Select-Object -First 3
    $top3Summary = ($top3 | ForEach-Object { "$($_.FileName) (Modified: $($_.Modified))" }) -join ', '
    $cutoffUsed = [datetime]::UtcNow.AddDays(-$lastModifiedDays).ToString('yyyy-MM-dd HH:mm:ss')
    Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Found $fileCount .$fileExt file(s) older than $lastModifiedDays days (cutoff: $cutoffUsed). Most recent 3: $top3Summary"

    return $targetFiles
}

function Get-FilteredFilesByAge {
    param($fileList, $days)

    $filtered = $fileList | Where-Object { $_.Modified -lt [datetime]::Now.AddDays(($days * -1)) }
    return $filtered
}

# Should still be connected to site we retrieved files from at this call.
# Returns the count of files successfully deleted.
function Remove-FilesInList {
    param($deleteFiles, $site, $spoBaseURI, $tenantId)
    # Remove the base URI since we're doing a site-path search.
    $siteMatchString = $site.Replace($spoBaseURI, '')

    $siteFiles = $deleteFiles | Where-Object { $_.FilePath.startswith($siteMatchString) }
    Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Got $($siteFiles.count) delete file(s) for site: $site"
    if ($siteFiles.Count -gt 0) {
        return (Remove-FilesFound -targetFileList $siteFiles -site $site -tenantId $tenantId)
    }
    else {
        Write-LogMessage -sev Info -API 'SharePointCleanup' -message "No files matched site path filter for $site (match string: $siteMatchString)"
        return 0
    }
}

function Remove-FilesFound {
    param($targetFileList, $site, $tenantId)

    $count = 0
    $deleted = 0
    $HistoryTable = Get-CIPPTable -tablename 'SharePointCleanupHistory'

    foreach ($file in $targetFileList) {
        # Throttle delay to avoid SharePoint request limits
        Start-Sleep -Milliseconds 650
        Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Processing $count of $($targetFileList.count): $($file.FilePath)"
        # Get the folder and file name from the file path
        $folder = $file.FilePath.Replace("/$($file.FileName)", '')

        try {
            # Make sure file exists at the path we supplied
            if ($pnpFile = Find-PnPFile -Folder $folder -Match $file.FileName) {
                Start-Sleep -Milliseconds 650
                #Remove-PnPFile -ServerRelativeUrl $file.FilePath -Force
                Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Deleted $($file.FilePath)"
                $deleted += 1

                # Log to history table
                try {
                    $HistoryEntity = [PSCustomObject]@{
                        PartitionKey  = $tenantId
                        RowKey        = "$([guid]::new)"
                        SiteUrl       = [string]$site
                        FileName      = [string]$file.FileName
                        FilePath      = [string]$file.FilePath
                        FileSize      = "$($file.FileSize)"
                        FileModified  = "$($file.Modified)"
                        DeletedDate   = (Get-Date).ToUniversalTime().ToString('o')
                        Library       = [string]$file.Library
                        FileExtension = "$([System.IO.Path]::GetExtension($file.FileName))"
                    }
                    Add-CIPPAzDataTableEntity @HistoryTable -Entity $HistoryEntity
                } catch {
                    Write-LogMessage -sev Warning -API 'SharePointCleanup' -message "Failed to log deletion history for $($file.FilePath): $($_.Exception.Message)"
                }
            } else {
                Write-LogMessage -sev Warning -API 'SharePointCleanup' -message "File not found: $($file.FilePath)"
            }
        } catch {
            Write-LogMessage -sev Error -API 'SharePointCleanup' -message "Error processing file $($file.FilePath): $($_.Exception.Message)"
        }
        $count += 1
    }
    Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Deletion pass complete: $deleted/$($targetFileList.count) file(s) processed for site $site"
    return $deleted
}
