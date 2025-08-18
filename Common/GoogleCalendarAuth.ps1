function Get-AccessToken {
    param(
        [string]$ClientId,
        [string]$ClientSecret
    )
	
    $tokenPath = "$env:HOME\calendar_token.json"
	
    if (Test-Path $tokenPath) {
        try {
            $tokenData = Get-Content $tokenPath | ConvertFrom-Json
			
            $tokenAge = (Get-Date) - [datetime]$tokenData.created
            if ($tokenAge.TotalSeconds -lt $tokenData.expires_in) {
                Write-Host "Using existing access token" -ForegroundColor Green
                return $tokenData.access_token
            }
			
            if ($tokenData.refresh_token) {
                Write-Host "Refreshing access token..." -ForegroundColor Yellow
                return Update-AccessToken -RefreshToken $tokenData.refresh_token -ClientId $ClientId -ClientSecret $ClientSecret
            }
        }
        catch {
            Write-Warning "Error reading saved token: $($_.Exception.Message)"
        }
    }
	
    Write-Host "Getting new access token..." -ForegroundColor Yellow
    return Get-NewAccessToken -ClientId $ClientId -ClientSecret $ClientSecret
}

function Get-NewAccessToken {
    param(
        [string]$ClientId,
        [string]$ClientSecret
    )
	
    if ([string]::IsNullOrEmpty($ClientId) -or [string]::IsNullOrEmpty($ClientSecret)) {
        Write-Error "CLIENT_ID and CLIENT_SECRET must be configured in the script."
        Write-Host @"
To set up Google Calendar API access:
1. Go to https://console.cloud.google.com/ (use ANY Google account - personal or Workspace)
2. Create a new project (free - just a container for credentials)
3. Enable Google Calendar API:
   - Go to 'APIs & Services' > 'Library' (or use direct link below)
   - Direct link: https://console.cloud.google.com/apis/library/calendar-json.googleapis.com
   - Make sure you have the correct project selected (check project picker at top)
   - Click 'Enable' on the Google Calendar API page
4. Configure OAuth consent screen:
   - Go to 'APIs & Services' > 'OAuth consent screen'
   - Choose 'External' (unless you have Workspace and want Internal only)
   - Fill in required fields (App name, User support email, Developer email)
5. Create OAuth credentials:
   - Go to 'APIs & Services' > 'Credentials'
   - Click 'Create Credentials' > 'OAuth 2.0 Client ID'
   - Choose 'Desktop application' as the application type
   - Download the JSON file and extract client_id and client_secret values
6. Set environment variables with your credentials:
   - GOOGLE_CALENDAR_CLIENT_ID = your client_id value
   - GOOGLE_CALENDAR_CLIENT_SECRET = your client_secret value
   - GOOGLE_CALENDAR_PRIMARY_ID = your primary calendar email
   
   PowerShell examples:
   $env:GOOGLE_CALENDAR_CLIENT_ID = "your-client-id-here"
   $env:GOOGLE_CALENDAR_CLIENT_SECRET = "your-client-secret-here"
   $env:GOOGLE_CALENDAR_PRIMARY_ID = "your.email@domain.com"
   
   Or add them to your PowerShell profile for persistence.

Note: These credentials will work with ANY Google Calendar you have access to:
- Personal Gmail calendars
- Google Workspace calendars  
- Shared calendars
The API doesn't distinguish between account types.
"@ -ForegroundColor Cyan
        throw "Authentication configuration required"
    }
	
    $REDIRECT_URI = "http://localhost:8080"
    $SCOPE = "https://www.googleapis.com/auth/calendar"
	
    $authUrl = "https://accounts.google.com/o/oauth2/auth?" + 
    "client_id=$ClientId&" +
    "redirect_uri=$([System.Web.HttpUtility]::UrlEncode($REDIRECT_URI))&" +
    "scope=$([System.Web.HttpUtility]::UrlEncode($SCOPE))&" +
    "response_type=code&" +
    "access_type=offline&" +
    "prompt=consent"
	
    Write-Host "Opening browser for authentication..." -ForegroundColor Cyan
    Start-Process $authUrl
	
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:8080/")
    $listener.Start()
	
    Write-Host "Waiting for authorization callback..." -ForegroundColor Yellow
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response
	
    $responseString = "<html><body><h1>Authorization received!</h1><p>You can close this window.</p></body></html>"
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.OutputStream.Close()
    $listener.Stop()
	
    $authCode = $request.QueryString["code"]
    if (-not $authCode) {
        Write-Error "No authorization code received"
        throw "Authorization failed"
    }
	
    $tokenUrl = "https://oauth2.googleapis.com/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        code          = $authCode
        grant_type    = "authorization_code"
        redirect_uri  = $REDIRECT_URI
    }
	
    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
	
    $tokenData = @{
        access_token  = $response.access_token
        refresh_token = $response.refresh_token
        expires_in    = $response.expires_in
        created       = (Get-Date).ToString()
    }
	
    $tokenData | ConvertTo-Json | Set-Content "$env:HOME\calendar_token.json"
    Write-Host "Access token saved successfully!" -ForegroundColor Green
	
    return $response.access_token
}

function Update-AccessToken {
    param(
        [string]$RefreshToken,
        [string]$ClientId,
        [string]$ClientSecret
    )
	
    $tokenUrl = "https://oauth2.googleapis.com/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        refresh_token = $RefreshToken
        grant_type    = "refresh_token"
    }
	
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
		
        $tokenData = @{
            access_token  = $response.access_token
            refresh_token = $RefreshToken
            expires_in    = $response.expires_in
            created       = (Get-Date).ToString()
        }
		
        $tokenData | ConvertTo-Json | Set-Content "$env:HOME\calendar_token.json"
        Write-Host "Access token refreshed successfully!" -ForegroundColor Green
		
        return $response.access_token
    }
    catch {
        Write-Warning "Failed to refresh token: $($_.Exception.Message)"
        Write-Host "Getting new token..." -ForegroundColor Yellow
        return Get-NewAccessToken -ClientId $ClientId -ClientSecret $ClientSecret
    }
}

