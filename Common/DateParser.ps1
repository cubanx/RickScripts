function ConvertTo-Date {
    param([string]$DateInput)
	
    $today = Get-Date
	
    switch ($DateInput.ToLower()) {
        "today" { return $today }
        "tomorrow" { return $today.AddDays(1) }
        "monday" { 
            $daysUntilMonday = (1 - [int]$today.DayOfWeek + 7) % 7
            if ($daysUntilMonday -eq 0 -and $today.DayOfWeek -ne [DayOfWeek]::Monday) { $daysUntilMonday = 7 }
            return $today.AddDays($daysUntilMonday)
        }
        "tuesday" { 
            $daysUntilTuesday = (2 - [int]$today.DayOfWeek + 7) % 7
            if ($daysUntilTuesday -eq 0 -and $today.DayOfWeek -ne [DayOfWeek]::Tuesday) { $daysUntilTuesday = 7 }
            return $today.AddDays($daysUntilTuesday)
        }
        "wednesday" { 
            $daysUntilWednesday = (3 - [int]$today.DayOfWeek + 7) % 7
            if ($daysUntilWednesday -eq 0 -and $today.DayOfWeek -ne [DayOfWeek]::Wednesday) { $daysUntilWednesday = 7 }
            return $today.AddDays($daysUntilWednesday)
        }
        "thursday" { 
            $daysUntilThursday = (4 - [int]$today.DayOfWeek + 7) % 7
            if ($daysUntilThursday -eq 0 -and $today.DayOfWeek -ne [DayOfWeek]::Thursday) { $daysUntilThursday = 7 }
            return $today.AddDays($daysUntilThursday)
        }
        "friday" { 
            $daysUntilFriday = (5 - [int]$today.DayOfWeek + 7) % 7
            if ($daysUntilFriday -eq 0 -and $today.DayOfWeek -ne [DayOfWeek]::Friday) { $daysUntilFriday = 7 }
            return $today.AddDays($daysUntilFriday)
        }
        default {
            try {
                return [datetime]::Parse($DateInput)
            }
            catch {
                Write-Error "Unable to parse date: $DateInput. Use formats like 'today', 'monday', '2025-07-28', or '07/28/2025'"
                throw "Date parsing failed: $DateInput"
            }
        }
    }
}
