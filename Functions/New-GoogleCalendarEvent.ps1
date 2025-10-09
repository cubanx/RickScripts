function New-GoogleCalendarEvent {
    param(
        [string]$AccessToken,
        [string]$CalendarId,
        [datetime]$EventDate,
        [datetime]$EventEndDate,
        [string]$StartTime,
        [string]$EndTime,
        [string]$EventTitle,
        [bool]$IsAllDay = $false
    )

    $PRIMARY_CALENDAR = $env:GOOGLE_CALENDAR_PRIMARY_ID
    $isOOO = $EventTitle -match "OOO"
    $isPrimaryCalendar = $CalendarId -eq $PRIMARY_CALENDAR

    if ($IsAllDay) {
        if ($isPrimaryCalendar -and $isOOO) {
            $startDateTime = Get-Date -Date $EventDate.Date -Hour 0 -Minute 0 -Second 0
            $endDateTime = Get-Date -Date $EventEndDate.AddDays(1).Date -Hour 0 -Minute 0 -Second 0

            $calendarEvent = @{
                summary               = $EventTitle
                start                 = @{
                    dateTime = $startDateTime.ToString("yyyy-MM-ddTHH:mm:ss")
                    timeZone = "America/New_York"
                }
                end                   = @{
                    dateTime = $endDateTime.ToString("yyyy-MM-ddTHH:mm:ss")
                    timeZone = "America/New_York"
                }
                status                = "confirmed"
                transparency          = "opaque"
                visibility            = "default"
                eventType             = "outOfOffice"
                outOfOfficeProperties = @{
                    autoDeclineMode = "declineAllConflictingInvitations"
                    declineMessage  = "Declined because I am out of office"
                }
            }
        }
        else {
            $calendarEvent = @{
                summary      = $EventTitle
                start        = @{
                    date = $EventDate.ToString("yyyy-MM-dd")
                }
                end          = @{
                    date = $EventEndDate.AddDays(1).ToString("yyyy-MM-dd")
                }
                status       = "confirmed"
                transparency = "transparent"
                visibility   = "default"
            }
        }
    }
    else {
        $startDateTime = Get-Date -Date $EventDate.Date -Hour $StartTime.Split(':')[0] -Minute $StartTime.Split(':')[1]
        $endDateTime = Get-Date -Date $EventEndDate.Date -Hour $EndTime.Split(':')[0] -Minute $EndTime.Split(':')[1]

        $calendarEvent = @{
            summary      = $EventTitle
            start        = @{
                dateTime = $startDateTime.ToString("yyyy-MM-ddTHH:mm:ss")
                timeZone = "America/New_York"
            }
            end          = @{
                dateTime = $endDateTime.ToString("yyyy-MM-ddTHH:mm:ss")
                timeZone = "America/New_York"
            }
            status       = "confirmed"
            transparency = "opaque"
            visibility   = "default"
        }
        if ($isPrimaryCalendar -and $isOOO) {
            $calendarEvent.eventType = "outOfOffice"
            $calendarEvent.outOfOfficeProperties = @{
                autoDeclineMode = "declineAllConflictingInvitations"
                declineMessage  = "Declined because I am out of office"
            }
        }
    }

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }

    $uri = "https://www.googleapis.com/calendar/v3/calendars/$([System.Web.HttpUtility]::UrlEncode($CalendarId))/events"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body ($calendarEvent | ConvertTo-Json -Depth 3)
        return $response
    }
    catch {
        Write-Error "Failed to create event on calendar '$CalendarId': $($_.Exception.Message)"
        if ($_.ErrorDetails.Message) {
            Write-Host "Error details: $($_.ErrorDetails.Message)" -ForegroundColor Red
        }
        return $null
    }
}


