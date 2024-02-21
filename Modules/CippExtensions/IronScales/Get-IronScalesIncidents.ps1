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
    $MappingFile = (Get-CIPPAzDataTableEntity @MappingTable)    
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10

    foreach ($ConfigItem in $Configuration.psobject.properties.name) {
        switch ($ConfigItem) {
            "Autotask" {
                If ($Configuration.Autotask.enabled) {
                    Get-AutotaskToken -configuration $Configuration.Autotask

                    $FulcraATCompany = Get-AutotaskAPIResource -resource Companies -SimpleSearch "companyname beginswith Fulcra" 
                    $managed_issues_body = @()

                    $tTitle = "[IronScales] New Incident(s) for"
                    $openUnMgdTkt = Get-ExistingTicket $tTitle
                            

                    foreach($company in $IronScalesIncidents) {
                        $AtCompany = $MappingFile | Where-Object { $_.AutotaskPSAName -eq $company.customername }
                        if($AtCompany.IsManaged) {
                            $managed_issues_body += Get-BodyForTicket $company
                        }
                        elseif($openUnMgdTkt){
                            continue
                        }
                        else {
                            $ATCompany = Get-AutotaskAPIResource -resource Companies -SimpleSearch "companyname beginswith $($company.Customername.Substring(0,4))" 
                            $tTitle = "[IronScales] New Incident(s) for $($company.CustomerName)"

                            

                            $body = Get-BodyForTicket $company
                            $estHr = 0.1*$company.Incidents.Count
                            New-AutotaskTicket -atCompany $ATCompany `
                                -title $tTitle `
                                -description ($body|Join-String) -estHr $estHr
                        }
                    }
                    if($managed_issues_body.Count -ne 0){
                        $mTitle = "[IronScales-Managed] New Incident(s)"

                        if(Get-ExistingTicket $tTitle)
                        {
                            continue
                        }

                        New-AutotaskTicket -atCompany $FulcraATCompany `
                            -title $mTitle `
                            -description ($managed_issues_body|Join-String)
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
        #Write-Host "Getting unclassified incidents for $($company.name):$($company.Id)"
        $incidents = Get-Incidents $company.Id
        #Write-Host "Got $($incidents.Length) for $($company.name)"

        if($incidents.Length -gt 0){
            $companyIncidents = [PSCustomObject]@{
                CustomerName = $company.name
                Incidents = $incidents
            }

            $all_unclassified += $companyIncidents
        }
    }

    Write-LogMessage -API "IronScales_Tickets" -tenant "none" -message "Got $($all_unclassified.Length) companies with unclassified incidents." -sev Info
    
    
    New-IronScalestickets $all_unclassified
}

function Get-Companies {
    if([String]::IsNullOrEmpty($SCRIPT:JWT)) {
        Write-Error "Cannot get companies; Call Get-ISJWT first"
        return
    }

    #Write-Host "Getting Companies"
    #Write-Host $SCRIPT:JWT

    $reqargs = @{
        Uri = "$($SCRIPT:apiHost+$is_endpoint.Companies+"list/")"
        Headers = @{
            Authorization = "Bearer $($SCRIPT:JWT)"
        }
    }

    $resp = Invoke-RestMethod @reqargs
    #Write-Host $resp
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
    return $body
}
