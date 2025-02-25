$is_endpoint = @{
    auth= "/get-token/"
    campaigns="/campaigns/"
    companies= "/company/"
    incidents = "/incident/"
}

$JWT=""
$Companies = @()
$apiHost = ""

function New-IronScalestickets {
    param($IronScalesIncidents)

    if($IronScalesIncidents.length -eq 0){
        Write-LogMessage -API "IronScales" -tenant "none" -message "No incidents received." -sev Info
        return
    }

    $MappingTable = Get-CIPPTable -TableName CippMapping

    $ATMappings = Get-ExtensionMapping -Extension 'Autotask'
    $ISMappings = Get-ExtensionMapping -Extension 'IronScales'

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10

    foreach ($ConfigItem in $Configuration.psobject.properties.name) {
        switch ($ConfigItem) {
            "Autotask" {
                If ($Configuration.Autotask.enabled) {
                    Write-LogMessage -API 'IronScales' -tenant 'none' -message 'Autotask is enabled. Sending IronScales tickets.' -Sev Info
                    Get-AutotaskToken -configuration $Configuration.Autotask

                    foreach($company in $IronScalesIncidents) {
                        $ISCompany = $ISMappings | Where-Object { $_.IntegrationId -eq $company.Id }
                        $AtCompany = $ATMappings | Where-Object { $_.RowKey -eq $ISCompany.RowKey }

                        if($null -eq $AtCompany){
                            Write-LogMessage -API 'IronScales' -tenant 'none' -message "IronScales company $($company.customername) is not mapped." -Sev Info
                            continue
                        }
                        else {
                            Write-LogMessage -API 'IronScales' -tenant 'none' -message "Creating Autotask ticket for IronScales company $($company.customername)" -Sev Info
                            $tTitle = "[IronScales] New Incident(s) for $($company.CustomerName)"

                            if(Get-ExistingTicket $tTitle){
                                Write-LogMessage -API 'IronScales' -tenant 'none' -message "An existing Autotask ticket was found for $($company.customername)" -Sev Info
                                continue
                            }

                            $body = Get-BodyForTicket $company
                            $estHr = 0.1*$company.Incidents.Count
                            New-AutotaskTicket -atCompany $ATCompany.IntegrationId `
                                -title $tTitle `
                                -description ($body|Join-String) `
                                -estHr $estHr `
                                -issueType "29" `
                                -priority "1" `
                                -subIssueType "323"

                        }
                    }
                }
            }
        }
    }
}

function Get-ExistingTicket {
    param($TicketTitle)
    $query = (Get-TicketQueryFilter $TicketTitle|ConvertTo-Json -Depth 10)

    $ticket = Get-AutotaskAPIResource -Resource Tickets -SearchQuery $query

    return ($null -ne $ticket)
}

function Get-TicketQueryFilter {
    param($TicketTitle)

    $field1 = "title"
    $value1 = $TicketTitle
    $field2 = "status"
    $value2 = "1"
    $item1 = [PSCustomObject]@{
        op = "contains"
        field = $field1
        value = $value1
    }
    $item2 = [PSCustomObject]@{
        op = "eq"
        field = $field2
        value = $value2
    }
    $andquery = [PSCustomObject]@{
        filter = @(
            [PSCustomObject]@{
                op = "and"
                items = @(
                    $item1,
                    $item2
                )
            }
        )
    }
    return $andquery
}

function Get-IronScalesIncidents {
    param($configuration)

    $SCRIPT:apiHost = $configuration.ApiHost
    $SCRIPT:JWT = Get-IronScalesToken -configuration $configuration

    if($SCRIPT:Companies.Length -eq 0){
        Get-Companies
    }

    #Write-Host "Got [$($SCRIPT:Companies.Length)] companies."

    $all_unclassified = @()
    foreach($company in $SCRIPT:Companies){
        try{
            Write-LogMessage -API "IronScales" -tenant "none" -message "Getting unclassified incidents for $($company.name):$($company.Id)" -sev Debug
            $incidents = Get-Incidents $company.Id

            if($incidents.Length -gt 0){
                $companyIncidents = [PSCustomObject]@{
                    Id = $company.Id
                    CustomerName = $company.name
                    Incidents = $incidents
                }

                $all_unclassified += $companyIncidents
            }
        }
        catch {
            Write-LogMessage -API "IronScales" -tenant "none" -message "Error getting IronScales incidents: $($_.Exception.Message)" -sev Error
        }
    }

    Write-LogMessage -API "IronScales" -tenant "none" -message "Got $($all_unclassified.Length) companies with unclassified incidents." -sev Debug


    New-IronScalestickets $all_unclassified
}

function Get-Companies {
    if([String]::IsNullOrEmpty($SCRIPT:JWT)) {
        Write-Error "Cannot get companies; Call Get-ISJWT first"
        return
    }

    $reqargs = @{
        Uri = "$($SCRIPT:apiHost+$is_endpoint.Companies+"list/")"
        Headers = @{
            Authorization = "Bearer $($SCRIPT:JWT)"
        }
    }

    $resp = Invoke-RestMethod @reqargs
    $SCRIPT:Companies = $resp.companies
}

function Get-Incidents {
    param(
        [Parameter(Mandatory = $true)]$companyId,
        [Parameter(HelpMessage="Options are: all|classified|unclassified|challenged")]$state = "unclassified"
    )


    if([String]::IsNullOrEmpty($SCRIPT:JWT)) {
        Write-Error "Cannot get incidents; Call Get-ISJWT first"
        return
    }

    $reqargs = @{
        Uri = "$($SCRIPT:apiHost+$is_endpoint.incidents+"$($companyId)"+"/list/?period=1&state=$($state)")"
        Headers = @{
            Authorization = "Bearer $($SCRIPT:JWT)"
        }
    }

    $resp = Invoke-RestMethod @reqargs
    return $resp.incidents
}

function Get-CompanyUnclassifiedIncidents {
    param([Parameter(Mandatory = $true)]$companyId)
    if([String]::IsNullOrEmpty($SCRIPT:JWT)) {
        Write-Error "Cannot get incidents; Call Get-ISJWT first"
        return
    }

    $reqargs = @{
        Uri = "$($SCRIPT:apiHost+$is_endpoint.incidents+"$($companyId)"+"/open/")"
        Headers = @{
            Authorization = "Bearer $($SCRIPT:JWT)"
        }
    }

    $resp = Invoke-RestMethod @reqargs
    return $resp.incidents
}

function Get-BodyForTicket {
    param($company)

    $body = @()
    foreach($incident in $company.Incidents){
        $body += "$($company.CustomerName)`nEmail Subject: $($incident.emailSubject)`nEmail Recipient: $($incident.recipientEmail)`nAffected Mailboxes: $($incident.affectedMailboxesCount)`n"
    }
    $body += "`n`nTo classify the incident(s) go to https://members.ironscales.com/irontraps/incidents/unclassified"
    return ($body -replace '[\u201c-\u201d]','')
}
