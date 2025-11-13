#Requires -Version 5.1

<#
.SYNOPSIS
    Suggests meeting rooms for in-office meetings over the next two weeks.

.DESCRIPTION
    This cmdlet scans your calendar from the current day through the end of next week (two-week window).
    Workflow:
      1. Detect working-location entries to find which days you have marked as being in the office.
      2. Gather every meeting you are invited to on those in-office days.
      3. Resolve the preferred rooms (Zurich → Singapore → Palo Alto) and check availability via FreeBusy.
      4. Present a plan showing which meetings already have rooms and which ones should book a room (no changes applied).

.PARAMETER StartDate
    Date to begin the scanning window. Defaults to "today" and accepts natural-language values via ConvertTo-Date.

.PARAMETER WeeksToScan
    Number of calendar weeks (starting with the week that contains StartDate) to include. Default 2 = remainder of this week + all of next week.

.PARAMETER DebugMode
    Enables verbose diagnostics (and ensures non-interactive flow).

.PARAMETER AutoBook
    Skip interactive selection and automatically book every meeting that is ready (used with -AllowApply).

.PARAMETER MaxAutoBookAttendees
    Maximum attendee count to auto-book rooms for (default: 20). Meetings above this count will only get suggestions unless overridden.

.PARAMETER AllowLargeMeetingAutoBook
    Override switch that permits auto-booking even when attendee count exceeds MaxAutoBookAttendees.

.PARAMETER CalendarId
    Calendar identifier to scan. Defaults to GOOGLE_CALENDAR_PRIMARY_ID.

.PARAMETER AllowApply
    Placeholder guard for future mutation support. Has no effect today other than reminding you no changes occur.

.EXAMPLE
    Add-MeetingRoom
#>

. "$PSScriptRoot\..\Common\GoogleCalendarAuth.ps1"
. "$PSScriptRoot\..\Common\DateParser.ps1"
. "$PSScriptRoot\..\Common\Config.ps1"

$PreferredMeetingRoomOrder = @("Zurich", "Singapore", "Palo Alto")

function Add-MeetingRoom {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [string]$StartDate = "today",

        [ValidateRange(1, 6)]
        [int]$WeeksToScan = 2,

        [ValidateRange(0, 200)]
        [int]$MaxAutoBookAttendees = 20,

        [switch]$AllowLargeMeetingAutoBook,

        [switch]$AllowApply,

        [switch]$AutoBook,

        [switch]$DebugMode,

        [string]$CalendarId = $env:GOOGLE_CALENDAR_PRIMARY_ID
    )

    if (-not $CalendarId) {
        Write-Error "GOOGLE_CALENDAR_PRIMARY_ID must be set (or pass -CalendarId)."
        return
    }

    Add-Type -AssemblyName System.Web

    $debugEnabled = $DebugMode.IsPresent -or $PSBoundParameters.ContainsKey('Debug')
    $customDebugPreferenceApplied = $false
    $previousDebugPreference = $DebugPreference
    if ($DebugMode.IsPresent -and -not $PSBoundParameters.ContainsKey('Debug')) {
        $DebugPreference = 'Continue'
        $customDebugPreferenceApplied = $true
    }

    try {
        try {
            $resolvedStartDate = ConvertTo-Date -DateInput $StartDate
        }
        catch {
            Write-Error $_.Exception.Message
            return
        }

        $clientId = $env:GOOGLE_CALENDAR_CLIENT_ID
        $clientSecret = $env:GOOGLE_CALENDAR_CLIENT_SECRET

        if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($clientSecret)) {
            Write-Error "GOOGLE_CALENDAR_CLIENT_ID and GOOGLE_CALENDAR_CLIENT_SECRET must be set."
            return
        }

        $accessToken = Get-AccessToken -ClientId $clientId -ClientSecret $clientSecret
        if (-not $accessToken) {
            return
        }

        $firstDayOfWeek = [System.DayOfWeek]::Monday
        $windowAnchor = Get-StartOfWeekDate -Date $resolvedStartDate.Date -FirstDayOfWeek $firstDayOfWeek
        $windowStart = Get-Date -Date $resolvedStartDate.Date -Hour 0 -Minute 0 -Second 0
        $windowEndDate = $windowAnchor.AddDays(($WeeksToScan * 7) - 1)
        $windowEnd = Get-Date -Date $windowEndDate -Hour 23 -Minute 59 -Second 59
        Write-Host ("Scanning meetings from {0} through {1}" -f $windowStart.ToString("yyyy-MM-dd"), $windowEnd.ToString("yyyy-MM-dd")) -ForegroundColor Cyan

        $timeMin = $windowStart.ToUniversalTime().ToString("o")
        $timeMax = $windowEnd.ToUniversalTime().ToString("o")

        $instances = Get-RecurringEventInstances -AccessToken $accessToken `
            -CalendarId $CalendarId `
            -SearchQuery $null `
            -TimeMin $timeMin `
            -TimeMax $timeMax

        $instanceCount = if ($instances) { $instances.Count } else { 0 }
        Write-Debug ("Fetched {0} events from calendar window." -f $instanceCount)

        $inOfficeDates = Get-InOfficeDates -Events $instances
        if (-not $inOfficeDates -or $inOfficeDates.Count -eq 0) {
            Write-Warning "No in-office working location entries found in this window. Nothing to do."
            return
        }

        Write-Debug ("In-office days detected: {0}" -f (($inOfficeDates.Keys | Sort-Object) -join ", "))

        $meetingCandidates = Get-InOfficeMeetings -Events $instances -InOfficeDates $inOfficeDates -UserEmail $CalendarId
        if (-not $meetingCandidates -or $meetingCandidates.Count -eq 0) {
            Write-Warning "No meetings found on in-office days that include you as a participant."
            return
        }

        $meetingRooms = Get-PreferredMeetingRooms -PreferredOrder $PreferredMeetingRoomOrder -Cmdlet $PSCmdlet -AccessToken $accessToken -DebugMode:$debugEnabled

        Write-Host "Meeting room priority:" -ForegroundColor Cyan
        $index = 1
        foreach ($room in $meetingRooms) {
            Write-Host ("  {0}. {1} ({2})" -f $index, $room.Name, $room.CalendarId) -ForegroundColor DarkYellow
            $index++
        }

        $bookingPlan = Get-MeetingRoomBookingPlan -Occurrences $meetingCandidates -MeetingRooms $meetingRooms -AccessToken $accessToken -MaxAutoBookAttendees $MaxAutoBookAttendees -AllowLargeMeetingAutoBook:$AllowLargeMeetingAutoBook

        if (-not $bookingPlan -or $bookingPlan.Count -eq 0) {
            Write-Warning "No actionable meetings found."
            return
        }

        Show-MeetingRoomBookingPlan -Plan $bookingPlan -WindowStart $windowStart -WindowEnd $windowEnd

        if ($AllowApply) {
            $bookingsToApply = $bookingPlan | Where-Object { $_.Status -eq "Planned" }
            if (-not $bookingsToApply -or $bookingsToApply.Count -eq 0) {
                Write-Host "No meetings require booking updates." -ForegroundColor Yellow
            }
            else {
                $selectedBookings = if ($AutoBook) {
                    $bookingsToApply
                }
                else {
                    Select-BookingsForApply -Bookings $bookingsToApply
                }

                if (-not $selectedBookings -or $selectedBookings.Count -eq 0) {
                    Write-Host "No meetings selected for booking." -ForegroundColor Yellow
                }
                else {
                    Invoke-MeetingRoomBookings -Bookings $selectedBookings -CalendarId $CalendarId -AccessToken $accessToken -Cmdlet $PSCmdlet
                }
            }
        }

        if ($debugEnabled) {
            return $bookingPlan
        }
        else {
            return
        }
    }
    finally {
        if ($customDebugPreferenceApplied) {
            $DebugPreference = $previousDebugPreference
        }
    }
}

function Get-RecurringEventInstances {
    param(
        [string]$AccessToken,
        [string]$CalendarId,
        [string]$SearchQuery,
        [string]$TimeMin,
        [string]$TimeMax,
        [int]$MaxPages = 5
    )

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
    }

    $encodedCalendarId = [System.Web.HttpUtility]::UrlEncode($CalendarId)
    $baseUri = "https://www.googleapis.com/calendar/v3/calendars/$encodedCalendarId/events"

    $queryParams = @{
        maxResults   = 250
        orderBy      = "startTime"
        singleEvents = "true"
        showDeleted  = "false"
    }

    if ($SearchQuery) { $queryParams.q = $SearchQuery }
    if ($TimeMin) { $queryParams.timeMin = $TimeMin }
    if ($TimeMax) { $queryParams.timeMax = $TimeMax }

    $items = @()
    $pageToken = $null
    $pageCount = 0

    do {
        $pageCount++
        if ($pageToken) {
            $queryParams.pageToken = $pageToken
        }
        elseif ($queryParams.ContainsKey('pageToken')) {
            $queryParams.Remove('pageToken')
        }

        $queryString = ($queryParams.GetEnumerator() | ForEach-Object {
                "{0}={1}" -f [System.Web.HttpUtility]::UrlEncode($_.Key), [System.Web.HttpUtility]::UrlEncode([string]$_.Value)
            }) -join "&"

        $uri = "$($baseUri)?$queryString"

        try {
            $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        }
        catch {
            Write-Error "Failed to query Google Calendar events: $($_.Exception.Message)"
            break
        }

        if ($response.items) {
            $items += $response.items
        }

        $pageToken = $response.nextPageToken
    }
    while ($pageToken -and $pageCount -lt $MaxPages)

    if ($pageToken) {
        Write-Warning "Reached page limit ($MaxPages). Consider narrowing your search."
    }

    return $items
}

function Get-EventDateTime {
    param(
        [Parameter(Mandatory = $true)]
        $Event,

        [switch]$AsUtc
    )

    if (-not $Event) {
        return $null
    }

    if ($Event.start.dateTime) {
        $offset = [datetimeoffset]$Event.start.dateTime
        if ($AsUtc) {
            return $offset.UtcDateTime
        }

        return $offset.LocalDateTime
    }

    if ($Event.start.date) {
        $date = [datetime]::Parse($Event.start.date)
        if ($AsUtc) {
            return $date.ToUniversalTime()
        }

        return $date
    }

    return $null
}

function Get-InOfficeDates {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Events
    )

    $dates = @{}

    foreach ($event in $Events) {
        if ($event.eventType -ne "workingLocation") {
            continue
        }

        $locationType = $event.workingLocationProperties.type
        if ($locationType -ne "officeLocation") {
            continue
        }

        $startDate = if ($event.start.date) { [datetime]::Parse($event.start.date) } else { Get-EventDateTime -Event $event }
        if (-not $startDate) {
            continue
        }

        $key = $startDate.ToString("yyyy-MM-dd")
        if (-not $dates.ContainsKey($key)) {
            $dates[$key] = @{
                Date        = $startDate.Date
                Description = if ($event.summary) { $event.summary } else { "Office" }
            }
        }
    }

    return $dates
}

function Get-InOfficeMeetings {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Events,

        [Parameter(Mandatory = $true)]
        [hashtable]$InOfficeDates,

        [Parameter(Mandatory = $true)]
        [string]$UserEmail
    )

    $meetings = @()

    foreach ($event in $Events) {
        if ($event.status -eq "cancelled") { continue }
        if ($event.eventType -eq "workingLocation") { continue }
        if (-not $event.start.dateTime) { continue }
        if (-not (Test-UserIsAttendee -Event $event -UserEmail $UserEmail)) { continue }
        if (Test-UserDeclinedOrTentative -Event $event -UserEmail $UserEmail) { continue }

        $startLocal = Get-EventDateTime -Event $event
        if (-not $startLocal) { continue }

        $dateKey = $startLocal.ToString("yyyy-MM-dd")
        if (-not $InOfficeDates.ContainsKey($dateKey)) { continue }

        $meetings += $event
    }

    return $meetings | Sort-Object { Get-EventDateTime -Event $_ }
}

function Test-UserIsAttendee {
    param(
        [Parameter(Mandatory = $true)]
        $Event,

        [Parameter(Mandatory = $true)]
        [string]$UserEmail
    )

    if (-not $Event.attendees) {
        return $false
    }

    foreach ($attendee in $Event.attendees) {
        if ($attendee.self -eq $true) {
            return $true
        }

        if ($attendee.email -and $attendee.email.Equals($UserEmail, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Test-UserDeclinedOrTentative {
    param(
        [Parameter(Mandatory = $true)]
        $Event,

        [Parameter(Mandatory = $true)]
        [string]$UserEmail
    )

    if (-not $Event.attendees) {
        return $false
    }

    $skipStatuses = @("declined", "tentative")

    foreach ($attendee in $Event.attendees) {
        if ($attendee.email -and $attendee.email.Equals($UserEmail, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $skipStatuses -contains $attendee.responseStatus
        }

        if ($attendee.self -eq $true) {
            return $skipStatuses -contains $attendee.responseStatus
        }
    }

    return $false
}

function Get-PreferredMeetingRooms {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$PreferredOrder,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [switch]$DebugMode
    )

    $configPath = Join-Path $env:HOME ".RickScripts/config.json"
    $config = Get-RickScriptsConfig

    if (-not ($config.PSObject.Properties.Name -contains "meetingRooms")) {
        $config | Add-Member -NotePropertyName meetingRooms -NotePropertyValue @{} -Force
    }

    $storedRooms = $config.meetingRooms
    if ($storedRooms -isnot [hashtable]) {
        $converted = @{}
        foreach ($prop in $storedRooms.PSObject.Properties) {
            $converted[$prop.Name] = $prop.Value
        }
        $storedRooms = $converted
        $config.meetingRooms = $storedRooms
    }
    $updated = $false
    $resolvedRooms = @()

    $calendarList = $null

    foreach ($roomName in $PreferredOrder) {
        $roomDefinition = $null
        if ($storedRooms.ContainsKey($roomName)) {
            $roomDefinition = $storedRooms[$roomName]
        }

        if (-not $roomDefinition -or [string]::IsNullOrWhiteSpace($roomDefinition.calendarId)) {
            if (-not $calendarList) {
                $calendarList = Get-CalendarList -AccessToken $AccessToken
            }

            $resolvedCalendar = Resolve-MeetingRoomCalendar -RoomName $roomName -CalendarList $calendarList -DebugMode:$DebugMode

            if (-not $resolvedCalendar) {
                $prompt = "Enter the Google Calendar ID for the '$roomName' meeting room"
                $roomId = Read-Host $prompt
                if ([string]::IsNullOrWhiteSpace($roomId)) {
                    throw "A valid calendar ID is required for meeting room '$roomName'."
                }

                $resolvedCalendar = [pscustomobject]@{
                    id          = $roomId.Trim()
                    displayName = $roomName
                }
            }

            $roomDefinition = @{
                calendarId  = $resolvedCalendar.id
                displayName = $resolvedCalendar.displayName
                updated     = (Get-Date).ToString("o")
                source      = "auto"
            }

            $storedRooms[$roomName] = $roomDefinition
            $updated = $true
        }

        $resolvedRooms += [pscustomobject]@{
            Name       = $roomName
            CalendarId = $roomDefinition.calendarId
        }
    }

    if ($updated) {
        if ($Cmdlet.ShouldProcess($configPath, "Save meeting room identifiers")) {
            Set-RickScriptsConfig -Config $config
            Write-Host "Meeting room identifiers saved to $configPath" -ForegroundColor Green
        }
        else {
            Write-Warning "Skipped saving meeting room identifiers because -WhatIf was specified."
        }
    }

    return $resolvedRooms
}

function Get-MeetingRoomBookingPlan {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Occurrences,

        [Parameter(Mandatory = $true)]
        [array]$MeetingRooms,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [int]$MaxAutoBookAttendees = 20,

        [switch]$AllowLargeMeetingAutoBook
    )

    $occurrenceInfos = $Occurrences | ForEach-Object {
        $startLocal = Get-EventDateTime -Event $_
        $endLocal = Get-EventEndDateTime -Event $_
        $attendeeCount = if ($_.attendees) { ($_.attendees | Where-Object { $_.resource -ne $true }).Count } else { 0 }
        $attendeesOmitted = $false
        if ($_.PSObject.Properties.Match("attendeesOmitted")) {
            $attendeesOmitted = [bool]$_.attendeesOmitted
        }
        $guestsCanSeeOthers = $true
        if ($_.PSObject.Properties.Match("guestsCanSeeOtherGuests")) {
            $guestsCanSeeOthers = [bool]$_.guestsCanSeeOtherGuests
        }

        $summaryText = if ($_.summary) { $_.summary } else { "[No title]" }

        [pscustomobject]@{
            Event                   = $_
            Summary                 = $summaryText
            StartLocal              = $startLocal
            EndLocal                = $endLocal
            StartUtc                = Get-EventDateTime -Event $_ -AsUtc
            EndUtc                  = Get-EventEndDateTime -Event $_ -AsUtc
            ExistingRoom            = Get-ExistingMeetingRoom -Event $_ -MeetingRooms $MeetingRooms
            AttendeeCount           = $attendeeCount
            AttendeesOmitted        = $attendeesOmitted
            GuestsCanSeeOtherGuests = $guestsCanSeeOthers
        }
    }

    $timeMin = ($occurrenceInfos | Sort-Object StartUtc | Select-Object -First 1).StartUtc
    $timeMax = ($occurrenceInfos | Sort-Object EndUtc -Descending | Select-Object -First 1).EndUtc

    $calendarIds = $MeetingRooms.CalendarId | Select-Object -Unique
    $busyMap = Get-FreeBusyCalendarBusyMap -AccessToken $AccessToken -CalendarIds $calendarIds -TimeMin $timeMin -TimeMax $timeMax

    $plan = @()

    foreach ($occurrence in $occurrenceInfos) {
        $status = "Pending"
        $roomSelection = $null
        $note = ""

        $attendeeLimitExceeded = $MaxAutoBookAttendees -gt 0 -and $occurrence.AttendeeCount -gt $MaxAutoBookAttendees
        $hasHiddenAttendees = $occurrence.AttendeesOmitted -or ($occurrence.GuestsCanSeeOtherGuests -eq $false -and $occurrence.AttendeeCount -le 2)
        $isLargeMeeting = (-not $AllowLargeMeetingAutoBook) -and ($attendeeLimitExceeded -or $hasHiddenAttendees)

        if ($occurrence.ExistingRoom) {
            $status = "AlreadyBooked"
            $roomSelection = $occurrence.ExistingRoom
            $note = "Room already on event"
        }
        else {
            foreach ($room in $MeetingRooms) {
                $busyEntries = $busyMap[$room.CalendarId]
                $isFree = Test-RoomIsFree -BusyEntries $busyEntries -StartUtc $occurrence.StartUtc -EndUtc $occurrence.EndUtc

                if ($isFree) {
                    $roomSelection = $room
                    $status = if ($isLargeMeeting) { "Suggested" } else { "Planned" }
                    if ($isLargeMeeting) {
                        if ($occurrence.AttendeesOmitted) {
                            $note = "Attendee list truncated (attendeesOmitted=true)"
                        }
                        elseif ($occurrence.GuestsCanSeeOtherGuests -eq $false -and $occurrence.AttendeeCount -le 2) {
                            $note = "Organizer hid guest list (assuming large meeting)"
                        }
                        elseif ($attendeeLimitExceeded) {
                            $note = "Over attendee limit (>$MaxAutoBookAttendees)"
                        }
                    }
                    break
                }
            }

            if (-not $roomSelection) {
                $status = "Unavailable"
                $note = "No rooms free"
            }
        }

        $plan += [pscustomobject]@{
            Summary        = $occurrence.Summary
            StartLocal     = $occurrence.StartLocal
            EndLocal       = $occurrence.EndLocal
            RoomName       = if ($roomSelection) { $roomSelection.Name } else { $null }
            RoomCalendarId = if ($roomSelection) { $roomSelection.CalendarId } else { $null }
            Status         = $status
            Note           = $note
            AttendeeCount  = $occurrence.AttendeeCount
            Event          = $occurrence.Event
        }
    }

    return $plan
}

function Show-MeetingRoomBookingPlan {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Plan,

        [datetime]$WindowStart,
        [datetime]$WindowEnd
    )

    Write-Host ""
    Write-Host "Meeting room booking preview (no changes applied):" -ForegroundColor Cyan
    if ($WindowStart -and $WindowEnd) {
        Write-Host ("Window: {0} → {1}" -f $WindowStart.ToString("yyyy-MM-dd"), $WindowEnd.ToString("yyyy-MM-dd")) -ForegroundColor Cyan
    }

    if (-not $Plan -or $Plan.Count -eq 0) {
        Write-Host "No meetings to display." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $dateStrings = $Plan | ForEach-Object {
        if ($_.StartLocal) { $_.StartLocal.ToString("yyyy-MM-dd (ddd) HH:mm") } else { "Unknown" }
    }
    $dateWidth = ($dateStrings | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    if (-not $dateWidth -or $dateWidth -lt 22) { $dateWidth = 22 }

    $roomNameWidth = ($Plan | ForEach-Object { $_.RoomName } | Where-Object { $_ } | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    if (-not $roomNameWidth -or $roomNameWidth -lt 8) { $roomNameWidth = 8 }

    $groups = $Plan | Group-Object { if ($_.Summary) { $_.Summary } else { "[No title]" } }

    foreach ($group in $groups) {
        Write-Host ""
        Write-Host $group.Name -ForegroundColor Cyan

        foreach ($item in ($group.Group | Sort-Object StartLocal)) {
            $dateText = if ($item.StartLocal) { $item.StartLocal.ToString("yyyy-MM-dd (ddd) HH:mm") } else { "Unknown" }
            $roomText = if ($item.RoomName) { $item.RoomName } else { "No room" }
            $paddedRoom = $roomText.PadRight($roomNameWidth)
            $paddedDate = $dateText.PadRight($dateWidth)

            switch ($item.Status) {
                "AlreadyBooked" {
                    $emoji = "✅"
                    $action = "Booked:   $paddedRoom"
                    $color = "Green"
                }
                "Planned" {
                    $emoji = "🆕"
                    $action = "Booking:  $paddedRoom"
                    $color = "Red"
                }
                "Suggested" {
                    $emoji = "💡"
                    $action = "Suggest:  $paddedRoom"
                    $color = "Cyan"
                }
                "Unavailable" {
                    $emoji = "⚠️"
                    $action = "No rooms free"
                    $color = "Yellow"
                }
                default {
                    $emoji = "ℹ️"
                    $action = $item.Status
                    $color = "Gray"
                }
            }

            $attendeeText = if ($item.AttendeeCount -ge 0) { "Attendees: {0}" -f $item.AttendeeCount } else { "" }

            Write-Host (" {0} {1} | {2} | {3}" -f $emoji, $paddedDate, $action, $attendeeText) -ForegroundColor $color
        }
    }

    Write-Host ""
}

function Select-BookingsForApply {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Bookings
    )

    if (-not $Bookings -or $Bookings.Count -eq 0) {
        return @()
    }

    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Warning "fzf is required for interactive selection. Install it or use -AutoBook to skip selection."
        return @()
    }

    $sorted = $Bookings | Sort-Object -Property @{Expression = { $_.StartLocal }; Descending = $true }, @{Expression = { $_.Summary }; Descending = $false }

    $menuItems = $sorted | ForEach-Object {
        $dateText = if ($_.StartLocal) { $_.StartLocal.ToString("yyyy-MM-dd HH:mm") } else { "Unknown" }
        $label = "{0} | {1} | {2}" -f $dateText, $_.Summary, $_.RoomName

        [pscustomobject]@{
            Label = $label
            Data  = $_
        }
    }

    $selection = ($menuItems.Label | fzf -m --prompt "Meetings to book > ")
    if (-not $selection) {
        return @()
    }

    $selectedLabels = $selection -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if (-not $selectedLabels -or $selectedLabels.Count -eq 0) {
        return @()
    }

    return ($menuItems | Where-Object { $selectedLabels -contains $_.Label }).Data
}

function Get-StartOfWeekDate {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date,

        [System.DayOfWeek]$FirstDayOfWeek = [System.DayOfWeek]::Monday
    )

    $diff = ([int]$Date.DayOfWeek) - ([int]$FirstDayOfWeek)
    if ($diff -lt 0) {
        $diff += 7
    }

    return $Date.AddDays(-$diff)
}

function Get-EventEndDateTime {
    param(
        [Parameter(Mandatory = $true)]
        $Event,

        [switch]$AsUtc
    )

    if (-not $Event) {
        return $null
    }

    if ($Event.end.dateTime) {
        $offset = [datetimeoffset]$Event.end.dateTime
        if ($AsUtc) {
            return $offset.UtcDateTime
        }

        return $offset.LocalDateTime
    }

    if ($Event.end.date) {
        $date = [datetime]::Parse($Event.end.date)
        if ($AsUtc) {
            return $date.ToUniversalTime()
        }

        return $date
    }

    return $null
}

function Get-ExistingMeetingRoom {
    param(
        [Parameter(Mandatory = $true)]
        $Event,

        [Parameter(Mandatory = $true)]
        [array]$MeetingRooms
    )

    if (-not $Event.attendees) {
        return $null
    }

    $roomLookup = @{}
    foreach ($room in $MeetingRooms) {
        $roomLookup[$room.CalendarId] = $room
    }

    foreach ($attendee in $Event.attendees) {
        if (-not $attendee.resource) {
            continue
        }

        $email = $attendee.email
        if ([string]::IsNullOrWhiteSpace($email)) {
            continue
        }

        if ($roomLookup.ContainsKey($email)) {
            return $roomLookup[$email]
        }
    }

    return $null
}

function Get-FreeBusyCalendarBusyMap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [string[]]$CalendarIds,

        [Parameter(Mandatory = $true)]
        [datetime]$TimeMin,

        [Parameter(Mandatory = $true)]
        [datetime]$TimeMax
    )

    if (-not $CalendarIds -or $CalendarIds.Count -eq 0) {
        return @{}
    }

    $body = @{
        timeMin = $TimeMin.ToString("o")
        timeMax = $TimeMax.ToString("o")
        items   = $CalendarIds | ForEach-Object { @{ id = $_ } }
    }

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }

    try {
        $response = Invoke-RestMethod -Uri "https://www.googleapis.com/calendar/v3/freeBusy" -Method Post -Headers $headers -Body ($body | ConvertTo-Json -Depth 3)
    }
    catch {
        Write-Warning "Unable to fetch room availability: $($_.Exception.Message)"
        return @{}
    }

    $map = @{}

    foreach ($calendarId in $CalendarIds) {
        if ($response.calendars.$calendarId) {
            $map[$calendarId] = $response.calendars.$calendarId.busy
        }
        else {
            $map[$calendarId] = @()
        }
    }

    return $map
}

function Test-RoomIsFree {
    param(
        [Parameter()]
        [array]$BusyEntries,

        [Parameter(Mandatory = $true)]
        [datetime]$StartUtc,

        [Parameter(Mandatory = $true)]
        [datetime]$EndUtc
    )

    if (-not $BusyEntries -or $BusyEntries.Count -eq 0) {
        return $true
    }

    foreach ($entry in $BusyEntries) {
        $busyStart = [datetime]::Parse($entry.start)
        $busyEnd = [datetime]::Parse($entry.end)

        $overlaps = ($busyStart -lt $EndUtc) -and ($busyEnd -gt $StartUtc)
        if ($overlaps) {
            return $false
        }
    }

    return $true
}

function Invoke-MeetingRoomBookings {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Bookings,

        [Parameter(Mandatory = $true)]
        [string]$CalendarId,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    if (-not $Bookings -or $Bookings.Count -eq 0) {
        return
    }

    $encodedCalendarId = [System.Web.HttpUtility]::UrlEncode($CalendarId)
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }

    foreach ($booking in $Bookings) {
        $event = $booking.Event
        if (-not $event -or -not $booking.RoomCalendarId) {
            continue
        }

        $eventId = $event.id
        if ([string]::IsNullOrWhiteSpace($eventId)) {
            continue
        }

        $encodedEventId = [System.Web.HttpUtility]::UrlEncode($eventId)
        $uri = "https://www.googleapis.com/calendar/v3/calendars/$encodedCalendarId/events/$encodedEventId"

        $attendeeBodies = @()
        if ($event.attendees) {
            foreach ($attendee in $event.attendees) {
                if ($attendee.email -eq $booking.RoomCalendarId) {
                    # Should not happen, but skip duplicates
                    continue
                }
                $attendeeBody = ConvertTo-AttendeeBody -Attendee $attendee
                if ($attendeeBody) {
                    $attendeeBodies += $attendeeBody
                }
            }
        }

        $attendeeBodies += @{
            email          = $booking.RoomCalendarId
            resource       = $true
            responseStatus = "needsAction"
        }

        $body = @{
            attendees = $attendeeBodies
        }

        $targetDescription = "{0} on {1}" -f $booking.Summary, ($booking.StartLocal.ToString("yyyy-MM-dd HH:mm"))

        if ($Cmdlet.ShouldProcess($targetDescription, "Add room {0}" -f $booking.RoomName)) {
            try {
                Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body ($body | ConvertTo-Json -Depth 4) | Out-Null
                Write-Host ("✓ Added {0} to {1}" -f $booking.RoomName, $targetDescription) -ForegroundColor Green
            }
            catch {
                Write-Warning ("Failed to add {0} to {1}: {2}" -f $booking.RoomName, $targetDescription, $_.Exception.Message)
                if ($_.ErrorDetails.Message) {
                    Write-Verbose $_.ErrorDetails.Message
                }
            }
        }
    }
}

function ConvertTo-AttendeeBody {
    param(
        [Parameter(Mandatory = $true)]
        $Attendee
    )

    if (-not $Attendee.email) {
        return $null
    }

    $body = @{
        email = $Attendee.email
    }

    foreach ($prop in @("displayName", "optional", "resource", "responseStatus", "comment")) {
        if ($Attendee.PSObject.Properties.Match($prop)) {
            $body[$prop] = $Attendee.$prop
        }
    }

    return $body
}

function Get-CalendarList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [int]$MaxPages = 10
    )

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
    }

    $uri = "https://www.googleapis.com/calendar/v3/users/me/calendarList"
    $pageToken = $null
    $pageCount = 0
    $calendars = @()

    do {
        $pageCount++
        $query = @{
            maxResults = 250
        }
        if ($pageToken) {
            $query.pageToken = $pageToken
        }

        $queryString = ($query.GetEnumerator() | ForEach-Object {
                "{0}={1}" -f [System.Web.HttpUtility]::UrlEncode($_.Key), [System.Web.HttpUtility]::UrlEncode([string]$_.Value)
            }) -join "&"

        $requestUri = "$($uri)?$queryString"

        try {
            $response = Invoke-RestMethod -Uri $requestUri -Headers $headers -Method Get
        }
        catch {
            Write-Warning "Unable to load calendar list: $($_.Exception.Message)"
            break
        }

        if ($response.items) {
            $calendars += $response.items
        }

        $pageToken = $response.nextPageToken
    }
    while ($pageToken -and $pageCount -lt $MaxPages)

    return $calendars
}

function Resolve-MeetingRoomCalendar {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RoomName,

        [Parameter(Mandatory = $true)]
        [array]$CalendarList,

        [switch]$DebugMode
    )

    if (-not $CalendarList -or $CalendarList.Count -eq 0) {
        return $null
    }

    $matches = $CalendarList | Where-Object {
        $displayName = Get-CalendarDisplayName -Calendar $_
        if ([string]::IsNullOrWhiteSpace($displayName)) {
            return $false
        }
        return $displayName.IndexOf($RoomName, [System.StringComparison]::InvariantCultureIgnoreCase) -ge 0
    }

    if (-not $matches -or $matches.Count -eq 0) {
        return $null
    }

    $exactMatch = $matches | Where-Object {
        $displayName = Get-CalendarDisplayName -Calendar $_
        $displayName.Equals($RoomName, [System.StringComparison]::InvariantCultureIgnoreCase)
    }

    if ($exactMatch.Count -eq 1) {
        $match = $exactMatch | Select-Object -First 1
        return [pscustomobject]@{
            id          = $match.id
            displayName = Get-CalendarDisplayName -Calendar $match
        }
    }

    if ($matches.Count -eq 1) {
        $match = $matches | Select-Object -First 1
        return [pscustomobject]@{
            id          = $match.id
            displayName = Get-CalendarDisplayName -Calendar $match
        }
    }

    $menuItems = $matches | ForEach-Object {
        $displayName = Get-CalendarDisplayName -Calendar $_
        $label = "{0} | {1}" -f $displayName, $_.id
        [pscustomobject]@{
            Label = $label
            Data  = $_
        }
    }

    if ($DebugMode) {
        Write-Debug "Debug mode enabled: skipping fzf calendar selection for $RoomName; choosing first candidate."
        $chosen = $matches | Select-Object -First 1
    }
    elseif (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Warning "fzf not available; selecting the first matching calendar for '$RoomName'."
        $chosen = $matches | Select-Object -First 1
    }
    else {
        $selection = $menuItems.Label | fzf --prompt "Select calendar for $RoomName > "
        if (-not $selection) {
            return $null
        }

        $chosen = ($menuItems | Where-Object { $_.Label -eq $selection }).Data
    }
    return [pscustomobject]@{
        id          = $chosen.id
        displayName = Get-CalendarDisplayName -Calendar $chosen
    }
}

function Get-CalendarDisplayName {
    param(
        [Parameter(Mandatory = $true)]
        $Calendar
    )

    if ($Calendar.summaryOverride) {
        return $Calendar.summaryOverride
    }

    if ($Calendar.summary) {
        return $Calendar.summary
    }

    if ($Calendar.description) {
        return $Calendar.description
    }

    return $Calendar.id
}

Set-Alias amr Add-MeetingRoom
if ($AllowApply) {
    Write-Warning "Apply mode is not implemented yet. For safety, no calendar changes will be made until explicit booking logic is added."
}

