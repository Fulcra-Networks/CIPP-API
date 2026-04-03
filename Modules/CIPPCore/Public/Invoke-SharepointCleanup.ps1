function Invoke-SharepointCleanup {
    [CmdletBinding()]
    param([string]$fileTypesCsv, [string]$siteUrlsCsv, [uint]$lastModifiedDays, $tenantId)

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

            # Step 4: Iterate file types, retrieving target files and combining lists
            $allTargetFiles = foreach ($ext in $fileTypes) {
                Get-TargetFiles -fileExt $ext
            }

            if ($null -eq $allTargetFiles -or $allTargetFiles.Count -eq 0) {
                Write-LogMessage -sev Info -API 'SharePointCleanup' -message "No matching files found on site: $site"
                Disconnect-PnPOnline
                continue
            }

            Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Found $($allTargetFiles.Count) total target file(s) on site: $site"

            # Step 5: Filter files by age
            $filteredFiles = Get-FilteredFilesByAge -fileList $allTargetFiles -days $lastModifiedDays

            if ($null -eq $filteredFiles -or $filteredFiles.Count -eq 0) {
                Write-LogMessage -sev Info -API 'SharePointCleanup' -message "No files older than $lastModifiedDays days on site: $site"
                Disconnect-PnPOnline
                continue
            }

            Write-LogMessage -sev Info -API 'SharePointCleanup' -message "$($filteredFiles.Count) file(s) older than $lastModifiedDays days on site: $site"

            # Step 6: While connected, delete filtered file list
            $siteDeleted = Remove-FilesInList -deleteFiles $filteredFiles -site $site -spoBaseURI $spoBaseURI -tenantId $tenantId

            $totalFilesFound += $filteredFiles.Count
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
        Searches the current site for files matching the given extension.
    .DESCRIPTION
        Recursively searches all document libraries in the connected site
        for files with the specified extension.
    .OUTPUTS
        Array of file objects.
    #>
    param($fileExt) #Filter is *.fileExt

    # Get all document libraries
    try {
        $lists = Get-PnPList | Where-Object { $_.BaseTemplate -eq 101 }
    } catch {
        Write-LogMessage -sev Error -API 'SharePointCleanup' -message "Failed to retrieve document libraries: $($_.Exception.Message)"
        return @()
    }

    $targetFiles = foreach ($list in $lists) {
        try {
            $camlQuery = @"
<View Scope='RecursiveAll'>
    <Query>
        <Where>
            <Eq><FieldRef Name='File_x0020_Type'/><Value Type='Text'>$fileExt</Value></Eq>
        </Where>
    </Query>
    <RowLimit Paged='TRUE'>500</RowLimit>
</View>
"@
            $files = Get-PnPListItem -List $list -Query $camlQuery -PageSize 500
        } catch {
            Write-LogMessage -sev Warning -API 'SharePointCleanup' -message "Failed to enumerate library '$($list.Title)': $($_.Exception.Message)"
            continue
        }

        foreach ($file in $files) {
            [PSCustomObject]@{
                FileName      = $file["FileLeafRef"]
                FilePath      = $file["FileRef"]
                FileSize      = $file["File_x0020_Size"]
                Modified      = $file["Modified"]
                Library       = $list.Title
                ComplianceTag = $file["_ComplianceTag"]
                Id            = $file.Id
            }
        }
    }

    Write-LogMessage -sev Info -API 'SharePointCleanup' -message "Found $(@($targetFiles).Count) .$fileExt file(s)"
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
                    $HistoryEntity = @{
                        PartitionKey  = $tenantId
                        RowKey        = (New-Guid).Guid
                        SiteUrl       = $site
                        FileName      = $file.FileName
                        FilePath      = $file.FilePath
                        FileSize      = $file.FileSize
                        FileModified  = $file.Modified
                        DeletedDate   = (Get-Date).ToUniversalTime().ToString('o')
                        Library       = $file.Library
                        FileExtension = [System.IO.Path]::GetExtension($file.FileName)
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
