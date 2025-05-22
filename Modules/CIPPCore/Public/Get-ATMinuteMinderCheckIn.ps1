class HoursData {
    [string]$Name
    [string]$Email
    [decimal]$regularHours
    [decimal]$billableHours
    [datetime]$hoursDate
    [int]$resourceId

    [decimal]TotalHours(){
        [decimal]$sum = 0.0
        $sum += $this.regularHours
        $sum += $this.billableHours
        return $sum
    }

    [void]SetName([string]$name){
        $this.Name = $name
    }
    [void]SetEmail([string]$email){
        $this.Email = $email
    }

    HoursData([decimal]$regHrs, [decimal]$billHrs, [DateTime]$hrsDate,[int]$resId){
        $this.regularHours = $regHrs
        $this.billableHours = $billHrs
        $this.resourceId = $resId
        $this.hoursDate = $hrsDate
    }
}

function Get-ATMinuteMinderCheckIn {
    [CmdletBinding()]
    param([string]$peopleCSV,[string]$additionalRecipCSV)

    $people = $peopleCSV.Split(',').Trim()

    $addtnlRecip = @()
    if(-not [string]::IsNullOrEmpty($additionalRecipCSV))
    {
        $addtnlRecip = $additionalRecipCSV.Split(',').Trim()
        Write-LogMessage -sev Info -API "MinuteMinder" -message "Additional email recipients: $($additionalRecipCSV), $($addtnlRecip)"
    }


    $CtxExtensionCfg = Get-CIPPTable -TableName Extensionsconfig
    $CfgExtensionTbl = (Get-CIPPAzDataTableEntity @CtxExtensionCfg).config | ConvertFrom-Json -Depth 10
    Get-AutotaskToken -configuration $CfgExtensionTbl.Autotask

    $everyonesHours = @()

    foreach($person in $people){
        $hoursData = Get-HoursData $person
        $everyonesHours += $hoursData
    }

    Write-LogMessage -sev info -API 'MinuteMinder' -Message "Got hours for $($people.Count) people, a total number of $($everyonesHours.length) entries."

    try{
        $htmlbody = "<p>Please see the below for recent timesheet data:<br/><table>"
        $htmlbody += "<tr><th>Name</th><th>Date</th><th>Total Hours</th><th>Billable Hours</th><th>Regular Hours</th></tr>"
        foreach($hours in $everyonesHours){
            $htmlbody += "<tr><td>$($hours.Name)</td>"
            $htmlbody += "<td>$($hours.hoursDate.ToString("yyyy-MM-dd"))</td>"
            $htmlbody += "<td>$($hours.TotalHours())</td>"
            $htmlbody += "<td>$($hours.billableHours)</td>"
            $htmlbody += "<td>$($hours.regularHours)</td></tr>"
        }
        $htmlbody += "</table></p>"

        $CIPPAlert = @{
            Type                    = 'email'
            Title                   = "CIPP Minute Minder"
            HTMLContent             = $htmlBody
            AdditionalRecipients    = @($addtnlRecip)
        }
        Send-CIPPAlert @CIPPAlert
    }
    catch {
        Write-LogMessage -sev Error -API "MinuteMinder" -Message "Error sending MinuteMinder email: $($_.Exception.Message)"
    }
}

function Get-HoursData {
    param($resourceID)
    $queryDate = [DateTime]::Now

    if(@("Saturday", "Sunday").Contains($queryDate.DayOfWeek.ToString())) {
        Write-Host "No weekend nagging!"
        return
    }

    $person = Get-AutotaskAPIResource -Resource Resources -SimpleSearch "ID eq $($resourceID)"

    [HoursData[]]$hoursList = @()

    while($true -or $hoursList.length -lt 10){
        $dayHours = Get-HoursForDay -date $queryDate -resourceID $resourceID
        $dayHours.SetName("$($person.firstname) $($person.Lastname)")
        $dayHours.SetEmail("$($person.email)")
        $hoursList += $dayHours

        if($dayHours.TotalHours() -ge 8){
            break
        }

        if($queryDate.DayOfWeek -eq 'Monday'){
            $queryDate = $queryDate.AddDays(-3)
        }
        else {
            $queryDate = $queryDate.AddDays(-1)
        }
    }

    return $hoursList
}

function Get-HoursForDay {
    param([DateTime]$date,$resourceID)

    #$startDateTime = (Get-Date).AddDays(-5).ToString('MM-dd-yyyy')

    $filter = @"
        {'filter':[
            {'op':'eq','field':'resourceID','value':$($resourceID)},
            {'op':'eq','field':'dateWorked','value':'$($date.ToString('MM-dd-yyyy')) 12:00:00 AM'},
        ]}
"@

    $timeEntries = Get-AutotaskAPIResource -Resource TimeEntries -SearchQuery $filter

    $billableHours = ($timeEntries | Where-Object {$_.timeEntryType -ne 10} | Measure-Object -Property hoursWorked -Sum).Sum
    $regularHours  = ($timeEntries | Where-Object {$_.timeEntryType -eq 10} | Measure-Object -Property hoursWorked -Sum).Sum

    ## This witchcraft is equivalent to if($null -ne $billablehours){}else{0.0}
    return [HoursData]::new(($null, $regularHours, 0.0 -ne $null)[0], ($null, $billableHours, 0.0 -ne $null)[0],$date,$resourceID)
}

