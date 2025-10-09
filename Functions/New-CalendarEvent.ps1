#Requires -Version 5.1

<#
.SYNOPSIS
    Creates Out of Office events on both primary and Sealand calendars using Google Calendar API.

.DESCRIPTION
    This script authenticates with Google Calendar API and creates OOO events on both
    your primary calendar and the Sealand calendar simultaneously.

.PARAMETER Date
    Date for the OOO event. Accepts:
    - "today", "tomorrow", "monday", "tuesday", etc.
    - Date in format "2025-07-28" or "07/28/2025"

.PARAMETER EndDate
    End date for multi-day events. Uses same format as Date parameter. If not provided, creates single-day event.

.PARAMETER StartTime
    Start time in 24-hour format (e.g., "11:00"). If not provided, creates an all-day event.

.PARAMETER EndTime
    End time in 24-hour format (e.g., "17:00"). If not provided, creates an all-day event.

.PARAMETER Title
    Title for the OOO event (default: "Out of Office")

.EXAMPLE
    New-CalendarEvent -Date "monday" -StartTime "11:00" -EndTime "17:00"
    
.EXAMPLE
    New-CalendarEvent -Date "2025-07-28" -StartTime "09:00" -EndTime "17:00" -Title "OOO - Personal"
    
.EXAMPLE
    New-CalendarEvent -Date "friday" -Title "All Day OOO"
    
.EXAMPLE
    New-CalendarEvent -Date "monday" -EndDate "wednesday" -Title "Multi-day OOO"
#>

. "$PSScriptRoot\..\Common\GoogleCalendarAuth.ps1"
. "$PSScriptRoot\..\Common\DateParser.ps1"

function New-CalendarEvent {
    [CmdletBinding(DefaultParameterSetName = 'AllDay')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'AllDay')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Timed')]
        [string]$Date,
		
        [Parameter(Mandatory = $false, ParameterSetName = 'AllDay')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Timed')]
        [string]$EndDate,
		
        [Parameter(Mandatory = $true, ParameterSetName = 'Timed')]
        [string]$StartTime,
		
        [Parameter(Mandatory = $true, ParameterSetName = 'Timed')]
        [string]$EndTime,
		
        [Parameter(Mandatory = $false, ParameterSetName = 'AllDay')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Timed')]
        [string]$Title = "Ricardo OOO"
    )

    $PRIMARY_CALENDAR = $env:GOOGLE_CALENDAR_PRIMARY_ID
    $SEALAND_CALENDAR = "world50.com_e3s035n2h2rugrg2a0ohnp1fsc@group.calendar.google.com"

    $CLIENT_ID = $env:GOOGLE_CALENDAR_CLIENT_ID
    $CLIENT_SECRET = $env:GOOGLE_CALENDAR_CLIENT_SECRET

    if ([string]::IsNullOrEmpty($PRIMARY_CALENDAR)) {
        Write-Error "GOOGLE_CALENDAR_PRIMARY_ID environment variable must be set to your primary calendar email"
        return
    }

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
		
        if ($IsAllDay) {
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
            if ($_.Exception.Response) {
                $errorDetails = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorDetails)
                $errorBody = $reader.ReadToEnd()
                Write-Host "Error details: $errorBody" -ForegroundColor Red
            }
            return $null
        }
    }

    Add-Type -AssemblyName System.Web

    try {
        Write-Host "OOO Calendar Manager" -ForegroundColor Cyan
        Write-Host "===================" -ForegroundColor Cyan
		
        $eventDate = ConvertTo-Date -DateInput $Date
        $eventEndDate = if ($EndDate) { ConvertTo-Date -DateInput $EndDate } else { $eventDate }
        $isAllDay = $PSCmdlet.ParameterSetName -eq 'AllDay'
        $isMultiDay = $eventEndDate -gt $eventDate
		
        Write-Host "Event Date: $($eventDate.ToString('dddd, MMMM dd, yyyy'))" -ForegroundColor Green
        if ($isMultiDay) {
            Write-Host "End Date: $($eventEndDate.ToString('dddd, MMMM dd, yyyy'))" -ForegroundColor Green
        }
        if ($isAllDay) {
            Write-Host "Time: All Day" -ForegroundColor Green
        }
        else {
            Write-Host "Time: $StartTime - $EndTime" -ForegroundColor Green
        }
        Write-Host "Title: $Title" -ForegroundColor Green
        Write-Host ""
		
        $accessToken = Get-AccessToken -ClientId $CLIENT_ID -ClientSecret $CLIENT_SECRET
		
        if (-not $accessToken) {
            Write-Error "Failed to get access token"
            return
        }
		
        Write-Host "Creating OOO event on primary calendar..." -ForegroundColor Yellow
        $primaryEvent = New-GoogleCalendarEvent -AccessToken $accessToken -CalendarId $PRIMARY_CALENDAR -EventDate $eventDate -EventEndDate $eventEndDate -StartTime $StartTime -EndTime $EndTime -EventTitle $Title -IsAllDay $isAllDay
		
        if ($primaryEvent) {
            Write-Host "✓ Primary calendar event created successfully!" -ForegroundColor Green
            Write-Host "  Event ID: $($primaryEvent.id)" -ForegroundColor Gray
        }
		
        Write-Host "Creating OOO event on Sealand calendar..." -ForegroundColor Yellow
        $sealandEvent = New-GoogleCalendarEvent -AccessToken $accessToken -CalendarId $SEALAND_CALENDAR -EventDate $eventDate -EventEndDate $eventEndDate -StartTime $StartTime -EndTime $EndTime -EventTitle $Title -IsAllDay $isAllDay
		
        if ($sealandEvent) {
            Write-Host "✓ Sealand calendar event created successfully!" -ForegroundColor Green
            Write-Host "  Event ID: $($sealandEvent.id)" -ForegroundColor Gray
        }
		
        if ($primaryEvent -and $sealandEvent) {
            Write-Host ""
            Write-Host "🎉 OOO events created successfully on both calendars!" -ForegroundColor Green
        }
        elseif ($primaryEvent -or $sealandEvent) {
            Write-Host ""
            Write-Host "⚠️  OOO event created on only one calendar. Please check the errors above." -ForegroundColor Yellow
        }
        else {
            Write-Host ""
            Write-Host "❌ Failed to create OOO events. Please check the errors above." -ForegroundColor Red
        }
    }
    catch {
        Write-Error "An unexpected error occurred: $($_.Exception.Message)"
    }
}

