#Hints on int values below
function New-AutotaskTicket {
    param(
        $atCompanyId,
        $title,
        $description,
        $estHr = 0.1,
        $issueType,
        $subIssueType,
        $ticketType="5",
        $priority="2"
    )

    try{
        Get-AutotaskToken -configuration $Configuration.Autotask | Out-Null

        if($description -match "</table>"){
            $description = Convert-HtmlTableToPlainText $description
        }

        $ticket = New-AutotaskBody -Resource Tickets -NoContent
        $ticket.Id                      = "0"                   #Always 0 for a new ticket
        $ticket.ticketType              = "1"
        $ticket.companyId               = "$($atCompanyId)"
        $ticket.priority                = $priority
        $ticket.ticketCategory          = "3"
        $ticket.ticketType              = "5"
        $ticket.serviceLevelAgreementID = "1"
        $ticket.issueType               = $issueType
        $ticket.subIssueType            = $subIssueType
        $ticket.title                   = $title
        $ticket.description             = $description
        $ticket.source                  = "8"
        $ticket.status                  = "1"
        $ticket.queueID                 = "29682833"
        $ticket.estimatedHours          = $estHr
        $ticket.billingCodeID           = "29682801"            #Worktype = remote

        $t = New-AutotaskAPIResource -Resource Tickets -Body $ticket
        Write-LogMessage -API 'Webhook Alerts' -tenant $TenantFilter -message "Created autotask ticket: $t" -sev info
    }
    catch {
        Write-LogMessage -API 'Autotask' -tenant 'none' -message "Error creating ticket. $($_.Exception.Message)" -Sev Error
    }
}

function Convert-HtmlTableToPlainText {
    param($htmltbl)
    # Parse the HTML content
    $HTML = New-Object -Com "HTMLFile"

    try {
        # This works in PowerShell with Office installed
        $html.IHTMLDocument2_write($htmltbl)
    }
    catch {
        # This works when Office is not installed
        $src = [System.Text.Encoding]::Unicode.GetBytes($htmltbl)
        $html.write($src)
    }

    $tables = @($html.getElementsByTagName("TABLE"))

    $table = $tables[0]
    $titles = @()
    $rows = @($table.Rows)
    $objArray = @()

    foreach ($row in $rows) {
        $cells = @($row.Cells)

        if ($cells[0].tagName -eq "TH") {
            $titles = @($cells | ForEach-Object { ("" + $_.InnerText).Trim() })
            continue
        }

        if (-not $titles) {
            $titles = @(1..($cells.Count + 2) | ForEach-Object { "P$_" })
        }

        $resultObject = [Ordered] @{ }
        for ($counter = 0; $counter -lt $cells.Count; $counter++) {
            $title = $titles[$counter]
            if (-not $title) { continue }
            $resultObject[$title] = ("" + $cells[$counter].InnerText).Trim()
        }

        $objArray += [PSCustomObject] $resultObject
    }


    return ($objArray|ConvertTo-Csv -NoTypeInformation)
}

<# TICKET STATUS:
label               value isActive
-----               ----- --------
New                 1         True
Complete            5         True
Waiting Customer    7         True
In Progress         8         True
Waiting Materials   9         True
Waiting Vendor      12        True
Change Order        15        True
On Hold             17        True
Outsourced          20        True
Accounting          21        True
#>
<# TICKET TYPES:
label    : Service Request
value    : 1
isActive : True
label    : Incident
value    : 2
isActive : True
label    : Problem
value    : 3
isActive : True
label    : Change Request
value    : 4
isActive : True
label    : Alert
value    : 5
isActive : True
#>
<# TICKET PRIORITY:
label    : High
value    : 1
isActive : True
label    : Normal
value    : 2
isActive : True
label    : Critical
value    : 4
isActive : True
#>
<# TICKET SOURCE:
label            value isActive
-----            ----- --------
Insourced        -2        True
Client Portal    -1        True
Phone            2         True
Email            4         True
In Person/Onsite 6         True
Monitoring Alert 8         True
Verbal           11        True
#>
<# TICKET CATEGORY:
label                   value isActive
-----                   ----- --------
AEM Alert               2         True
Standard                3         True
Datto Alert             4         True
RMA                     5         True
Datto Networking Alert  6         True
#>
<# TICKET QUEUES:
label                  value    isActive
-----                  -----    --------
Client Portal          5            True
Post Sale              6            True
Monitoring Alert       8            True
Level I Support        29682833     True
Level II Support       29682969     True
Recurring Tickets      29683354     True
Renewals               29683479     True
Managed Service Config 29683480     True
Internal               29683481     True
Waiting Customer       29683482     True
Outsourced             29683483     True
Accounting             29683484     True
Taskfire Email Handler 29683485     True
#>
<# TICKET ISSUE TYPES:
label                        value isActive
-----                        ----- --------
Server                       7         True
Computer                     10        True
Network                      11        True
User                         16        True
Sales                        19        True
Management                   20        True
Phones / Mobile Devices      25        True
Block Time                   26        True
Backup / Restore             27        True
Security                     28        True
Service Management           29        True
Printer / Scanner            30        True
Other                        31        True
#>
<# TICKET SUB-ISSUE TYPES
label                                value isActive
-----                                ----- --------
Applications - Other                 104       True
Firewall/Router                      112       True
WAP                                  116       True
AntiVirus                            132       True
Backup                               133       True
Desktop                              134       True
E-Mail                               135       True
Firewall                             136       True
Internet                             137       True
Network                              139       True
Other                                140       True
Phone                                141       True
Point of Sale                        142       True
Printer                              143       True
Router                               144       True
Server                               145       True
Software                             146       True
Virus Removal                        147       True
Website                              148       True
Wireless                             149       True
Workstation                          150       True
Hardware                             152       True
Operating System                     153       True
Backup                               169       True
Connectivity                         170       True
Disk Space                           171       True
Firewall                             172       True
Hardware                             173       True
Internet                             174       True
Intranet/LAN                         175       True
Network                              176       True
Phone                                177       True
Point of Sale                        178       True
Printer                              179       True
Router                               180       True
Server                               181       True
Software                             182       True
Workstation                          183       True
Cabling                              184       True
Configuration                        185       True
ISP                                  189       True
VPN                                  198       True
Switch                               199       True
E-mail                               200       True
Firewall                             201       True
Hardware                             202       True
Internet                             203       True
Intranet/LAN                         204       True
Network                              205       True
Phone                                206       True
Point of Sale                        207       True
Printer                              208       True
Router                               209       True
Server                               210       True
Software                             211       True
Workstation                          212       True
Application                          215       True
Hardware                             217       True
Change                               223       True
SharePoint Online                    225       True
Exchange Online                      226       True
Skype for Business                   227       True
OneDrive for Business Sync           228       True
OneDrive for Business Config         229       True
Dynamics CRM                         231       True
Mozy                                 233       True
DNS                                  235       True
Domain Renewal                       236       True
Application                          237       True
Report                               238       True
Integration                          239       True
Automation                           240       True
Fulcra Solution                      241       True
Order Fulfillment                    242       True
Delivery                             243       True
Onsite Support                       244       True
Configuration                        245       True
Surveillance - Camera                247       True
Surveillance - NVR/DVR               248       True
Client Meeting                       252       True
CCTV                                 254       True
CCTV                                 255       True
Accounting                           256       True
HR                                   257       True
A/P                                  258       True
A/R                                  259       True
Monitoring                           260       True
Antivirus                            261       True
AntiVirus                            262       True
Backup                               263       True
CCTV                                 264       True
E-Mail                               265       True
Firewall                             266       True
Internet                             267       True
Network                              268       True
Onsite Maintenance                   269       True
Other                                270       True
Patch Management                     271       True
Phone                                272       True
Point of Sale                        273       True
Printer                              274       True
Router                               275       True
Server                               276       True
Software                             277       True
Website                              278       True
Wireless                             279       True
Workstation                          280       True
Security                             281       True
User                                 285       True
Computer                             286       True
Operating System                     287       True
Updates                              288       True
Desk Phone                           289       True
Mobile Device                        290       True
Support                              291       True
Patch Management                     292       True
Authentication / MFA                 293       True
Email Security                       294       True
Device Management                    295       True
Audit / Test                         296       True
Restore                              297       True
Reporting                            298       True
Configuration                        299       True
Tape Management                      300       True
Onboarding                           301       True
Offboarding                          302       True
Offboarding                          303       True
Applications - Office                305       True
Transfer                             306       True
Updates                              307       True
Connectivity                         308       True
Onboarding                           309       True
Offboarding                          310       True
Password                             311       True
Authentication                       312       True
Licensing                            313       True
Access                               314       True
Training / Question                  315       True
Remediation - Computer Malware Event 316       True
Malware Software Issue               317       True
Remediation - User Compromise        318       True
Updates                              319       True
Updates                              320       True
Authentication                       321       True
Email                                322       True
Email Security                       323       True
Endpoint - Security                  324       True
Endpoint - Config                    325       True
Backup                               326       True
Other                                327       True
Network - Cloud Management           328       True
Driver - 3rd Party                   329       True
Driver - Windows                     330       True
Scanner                              331       True
Printer                              332       True
Other                                333       True
PSA                                  334       True
RMM                                  335       True
Backup                               336       True
#>
