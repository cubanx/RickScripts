#!/bin/bash

# new-calendar-event.sh
# Creates Out of Office events on both primary and Sealand calendars using Google Calendar API

set -euo pipefail

# Calendar IDs
PRIMARY_CALENDAR="${GOOGLE_CALENDAR_PRIMARY_ID}"
SEALAND_CALENDAR="world50.com_e3s035n2h2rugrg2a0ohnp1fsc@group.calendar.google.com"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $0 -d DATE [-e END_DATE] [-s START_TIME] [-t END_TIME] [-T TITLE]

Creates Out of Office events on both primary and Sealand calendars.

OPTIONS:
    -d DATE         Event date (required)
                    Formats: 'today', 'tomorrow', 'monday', '2025-07-28', '07/28/2025'
    -e END_DATE     End date for multi-day events (optional)
    -s START_TIME   Start time in 24-hour format, e.g., '11:00' (optional)
    -t END_TIME     End time in 24-hour format, e.g., '17:00' (optional)
    -T TITLE        Event title (default: 'Out of Office')
    -h              Show this help

EXAMPLES:
    $0 -d "monday" -s "11:00" -t "17:00"
    $0 -d "2025-07-28" -s "09:00" -t "17:00" -T "OOO - Personal"
    $0 -d "friday" -T "All Day OOO"
    $0 -d "monday" -e "wednesday" -T "Multi-day OOO"

SETUP:
Set these environment variables:
    GOOGLE_CALENDAR_CLIENT_ID     - Your Google OAuth client ID
    GOOGLE_CALENDAR_CLIENT_SECRET - Your Google OAuth client secret
    GOOGLE_CALENDAR_PRIMARY_ID    - Your primary calendar email

EOF
}

# Parse date input to ISO format
parse_date() {
    local date_input="$1"
    local today
    today=$(date +%Y-%m-%d)
    
    case "${date_input,,}" in
        "today")
            echo "$today"
            ;;
        "tomorrow")
            date -d "$today + 1 day" +%Y-%m-%d 2>/dev/null || date -j -v+1d -f %Y-%m-%d "$today" +%Y-%m-%d
            ;;
        "monday"|"tuesday"|"wednesday"|"thursday"|"friday"|"saturday"|"sunday")
            # Find next occurrence of the specified day
            if command -v date >/dev/null 2>&1; then
                # GNU date (Linux)
                if date --version >/dev/null 2>&1; then
                    date -d "next ${date_input}" +%Y-%m-%d 2>/dev/null || date -d "${date_input}" +%Y-%m-%d
                else
                    # BSD date (macOS)
                    local target_day
                    case "${date_input,,}" in
                        "monday") target_day=1 ;;
                        "tuesday") target_day=2 ;;
                        "wednesday") target_day=3 ;;
                        "thursday") target_day=4 ;;
                        "friday") target_day=5 ;;
                        "saturday") target_day=6 ;;
                        "sunday") target_day=0 ;;
                    esac
                    local current_day
                    current_day=$(date +%w)
                    local days_ahead=$(( (target_day - current_day + 7) % 7 ))
                    [[ $days_ahead -eq 0 ]] && days_ahead=7
                    date -j -v+"${days_ahead}"d +%Y-%m-%d
                fi
            else
                echo "Error: date command not available" >&2
                exit 1
            fi
            ;;
        *)
            # Try to parse as date
            if date -d "$date_input" +%Y-%m-%d 2>/dev/null; then
                date -d "$date_input" +%Y-%m-%d
            elif date -j -f %Y-%m-%d "$date_input" +%Y-%m-%d 2>/dev/null; then
                echo "$date_input"
            elif date -j -f %m/%d/%Y "$date_input" +%Y-%m-%d 2>/dev/null; then
                date -j -f %m/%d/%Y "$date_input" +%Y-%m-%d
            else
                echo "Error: Unable to parse date: $date_input" >&2
                echo "Use formats like 'today', 'monday', '2025-07-28', or '07/28/2025'" >&2
                exit 1
            fi
            ;;
    esac
}

# Get or refresh access token
get_access_token() {
    local token_file="$HOME/.calendar_token.json"
    
    # Check environment variables
    if [[ -z "${GOOGLE_CALENDAR_CLIENT_ID:-}" ]] || [[ -z "${GOOGLE_CALENDAR_CLIENT_SECRET:-}" ]] || [[ -z "${GOOGLE_CALENDAR_PRIMARY_ID:-}" ]]; then
        echo -e "${RED}Error: GOOGLE_CALENDAR_CLIENT_ID, GOOGLE_CALENDAR_CLIENT_SECRET, and GOOGLE_CALENDAR_PRIMARY_ID must be set${NC}" >&2
        cat << EOF
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
   export GOOGLE_CALENDAR_CLIENT_ID="your-client-id-here"
   export GOOGLE_CALENDAR_CLIENT_SECRET="your-client-secret-here"
   export GOOGLE_CALENDAR_PRIMARY_ID="your.email@domain.com"

Note: These credentials will work with ANY Google Calendar you have access to:
- Personal Gmail calendars
- Google Workspace calendars  
- Shared calendars
The API doesn't distinguish between account types.
EOF
        exit 1
    fi
    
    # Check if we have a saved token
    if [[ -f "$token_file" ]]; then
        local token_data
        if token_data=$(cat "$token_file" 2>/dev/null) && [[ -n "$token_data" ]]; then
            local created expires_in access_token
            created=$(echo "$token_data" | jq -r '.created // empty' 2>/dev/null || echo "")
            expires_in=$(echo "$token_data" | jq -r '.expires_in // empty' 2>/dev/null || echo "")
            access_token=$(echo "$token_data" | jq -r '.access_token // empty' 2>/dev/null || echo "")
            
            if [[ -n "$created" ]] && [[ -n "$expires_in" ]] && [[ -n "$access_token" ]]; then
                local token_age
                token_age=$(( $(date +%s) - $(date -d "$created" +%s 2>/dev/null || date -j -f "%a %b %d %H:%M:%S %Z %Y" "$created" +%s 2>/dev/null || echo 0) ))
                
                if [[ $token_age -lt $expires_in ]]; then
                    echo -e "${GREEN}Using existing access token${NC}" >&2
                    echo "$access_token"
                    return
                fi
            fi
        fi
    fi
    
    echo -e "${YELLOW}Getting new access token...${NC}" >&2
    get_new_access_token
}

# Get new access token through OAuth flow
get_new_access_token() {
    local redirect_uri="http://localhost:8080"
    local scope="https://www.googleapis.com/auth/calendar"
    
    # Create authorization URL
    local auth_url="https://accounts.google.com/o/oauth2/auth"
    auth_url+="?client_id=${GOOGLE_CALENDAR_CLIENT_ID}"
    auth_url+="&redirect_uri=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$redirect_uri'))" 2>/dev/null || echo "$redirect_uri")"
    auth_url+="&scope=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$scope'))" 2>/dev/null || echo "$scope")"
    auth_url+="&response_type=code"
    auth_url+="&access_type=offline"
    auth_url+="&prompt=consent"
    
    echo -e "${CYAN}Opening browser for authentication...${NC}" >&2
    if command -v open >/dev/null; then
        open "$auth_url"  # macOS
    elif command -v xdg-open >/dev/null; then
        xdg-open "$auth_url"  # Linux
    else
        echo "Please open this URL in your browser:" >&2
        echo "$auth_url" >&2
    fi
    
    echo -e "${YELLOW}Waiting for authorization callback...${NC}" >&2
    echo "After authorizing, paste the 'code' parameter from the redirect URL:" >&2
    read -r -p "Authorization code: " auth_code
    
    if [[ -z "$auth_code" ]]; then
        echo -e "${RED}No authorization code provided${NC}" >&2
        exit 1
    fi
    
    # Exchange code for tokens
    local response
    response=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
        -d "client_id=${GOOGLE_CALENDAR_CLIENT_ID}" \
        -d "client_secret=${GOOGLE_CALENDAR_CLIENT_SECRET}" \
        -d "code=${auth_code}" \
        -d "grant_type=authorization_code" \
        -d "redirect_uri=${redirect_uri}")
    
    local access_token refresh_token expires_in
    access_token=$(echo "$response" | jq -r '.access_token // empty' 2>/dev/null || echo "")
    refresh_token=$(echo "$response" | jq -r '.refresh_token // empty' 2>/dev/null || echo "")
    expires_in=$(echo "$response" | jq -r '.expires_in // empty' 2>/dev/null || echo "")
    
    if [[ -z "$access_token" ]]; then
        echo -e "${RED}Failed to get access token${NC}" >&2
        echo "Response: $response" >&2
        exit 1
    fi
    
    # Save token
    local token_data
    token_data=$(jq -n \
        --arg access_token "$access_token" \
        --arg refresh_token "$refresh_token" \
        --arg expires_in "$expires_in" \
        --arg created "$(date)" \
        '{
            access_token: $access_token,
            refresh_token: $refresh_token,
            expires_in: ($expires_in | tonumber),
            created: $created
        }')
    
    echo "$token_data" > "$HOME/.calendar_token.json"
    echo -e "${GREEN}Access token saved successfully!${NC}" >&2
    echo "$access_token"
}

# Create calendar event
create_calendar_event() {
    local access_token="$1"
    local calendar_id="$2"
    local event_date="$3"
    local event_end_date="$4"
    local start_time="$5"
    local end_time="$6"
    local event_title="$7"
    local is_all_day="$8"
    
    local event_json
    if [[ "$is_all_day" == "true" ]]; then
        local end_date_plus_one
        end_date_plus_one=$(date -d "$event_end_date + 1 day" +%Y-%m-%d 2>/dev/null || date -j -v+1d -f %Y-%m-%d "$event_end_date" +%Y-%m-%d)
        
        event_json=$(jq -n \
            --arg summary "$event_title" \
            --arg start_date "$event_date" \
            --arg end_date "$end_date_plus_one" \
            '{
                summary: $summary,
                start: { date: $start_date },
                end: { date: $end_date },
                status: "confirmed",
                transparency: "transparent",
                visibility: "default"
            }')
    else
        local start_datetime="${event_date}T${start_time}:00"
        local end_datetime="${event_end_date}T${end_time}:00"
        
        event_json=$(jq -n \
            --arg summary "$event_title" \
            --arg start_datetime "$start_datetime" \
            --arg end_datetime "$end_datetime" \
            '{
                summary: $summary,
                start: { dateTime: $start_datetime, timeZone: "America/New_York" },
                end: { dateTime: $end_datetime, timeZone: "America/New_York" },
                status: "confirmed",
                transparency: "opaque",
                visibility: "default"
            }')
    fi
    
    local encoded_calendar_id
    encoded_calendar_id=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$calendar_id'))" 2>/dev/null || echo "$calendar_id")
    local uri="https://www.googleapis.com/calendar/v3/calendars/${encoded_calendar_id}/events"
    
    local response
    response=$(curl -s -X POST "$uri" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$event_json")
    
    local event_id
    event_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null || echo "")
    
    if [[ -n "$event_id" ]]; then
        echo "$event_id"
    else
        echo -e "${RED}Failed to create event on calendar '$calendar_id'${NC}" >&2
        echo "Response: $response" >&2
        return 1
    fi
}

# Main function
main() {
    local date="" end_date="" start_time="" end_time="" title="Out of Office"
    
    while getopts "d:e:s:t:T:h" opt; do
        case $opt in
            d) date="$OPTARG" ;;
            e) end_date="$OPTARG" ;;
            s) start_time="$OPTARG" ;;
            t) end_time="$OPTARG" ;;
            T) title="$OPTARG" ;;
            h) usage; exit 0 ;;
            *) usage; exit 1 ;;
        esac
    done
    
    if [[ -z "$date" ]]; then
        echo -e "${RED}Error: Date is required${NC}" >&2
        usage
        exit 1
    fi
    
    # Validate parameter combinations
    if [[ -n "$start_time" && -z "$end_time" ]] || [[ -z "$start_time" && -n "$end_time" ]]; then
        echo -e "${RED}Error: If you specify start time, you must also specify end time${NC}" >&2
        exit 1
    fi
    
    # Check dependencies
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${RED}Error: jq is required but not installed${NC}" >&2
        echo "Install with: brew install jq (macOS) or apt-get install jq (Ubuntu)" >&2
        exit 1
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}Error: curl is required but not installed${NC}" >&2
        exit 1
    fi
    
    # Parse dates
    local event_date event_end_date
    event_date=$(parse_date "$date")
    event_end_date="$event_date"
    
    if [[ -n "$end_date" ]]; then
        event_end_date=$(parse_date "$end_date")
    fi
    
    local is_all_day="false"
    if [[ -z "$start_time" ]]; then
        is_all_day="true"
    fi
    
    local is_multi_day="false"
    if [[ "$event_end_date" != "$event_date" ]]; then
        is_multi_day="true"
    fi
    
    # Display event info
    echo -e "${CYAN}OOO Calendar Manager${NC}"
    echo -e "${CYAN}===================${NC}"
    echo -e "${GREEN}Event Date: $(date -d "$event_date" "+%A, %B %d, %Y" 2>/dev/null || date -j -f %Y-%m-%d "$event_date" "+%A, %B %d, %Y")${NC}"
    
    if [[ "$is_multi_day" == "true" ]]; then
        echo -e "${GREEN}End Date: $(date -d "$event_end_date" "+%A, %B %d, %Y" 2>/dev/null || date -j -f %Y-%m-%d "$event_end_date" "+%A, %B %d, %Y")${NC}"
    fi
    
    if [[ "$is_all_day" == "true" ]]; then
        echo -e "${GREEN}Time: All Day${NC}"
    else
        echo -e "${GREEN}Time: $start_time - $end_time${NC}"
    fi
    
    echo -e "${GREEN}Title: $title${NC}"
    echo ""
    
    # Get access token
    local access_token
    access_token=$(get_access_token)
    
    if [[ -z "$access_token" ]]; then
        echo -e "${RED}Failed to get access token${NC}" >&2
        exit 1
    fi
    
    # Create events on both calendars
    echo -e "${YELLOW}Creating OOO event on primary calendar...${NC}"
    local primary_event_id
    if primary_event_id=$(create_calendar_event "$access_token" "$PRIMARY_CALENDAR" "$event_date" "$event_end_date" "$start_time" "$end_time" "$title" "$is_all_day"); then
        echo -e "${GREEN}✓ Primary calendar event created successfully!${NC}"
        echo -e "${GRAY}  Event ID: $primary_event_id${NC}"
    fi
    
    echo -e "${YELLOW}Creating OOO event on Sealand calendar...${NC}"
    local sealand_event_id
    if sealand_event_id=$(create_calendar_event "$access_token" "$SEALAND_CALENDAR" "$event_date" "$event_end_date" "$start_time" "$end_time" "$title" "$is_all_day"); then
        echo -e "${GREEN}✓ Sealand calendar event created successfully!${NC}"
        echo -e "${GRAY}  Event ID: $sealand_event_id${NC}"
    fi
    
    # Summary
    if [[ -n "${primary_event_id:-}" && -n "${sealand_event_id:-}" ]]; then
        echo ""
        echo -e "${GREEN}🎉 OOO events created successfully on both calendars!${NC}"
    elif [[ -n "${primary_event_id:-}" || -n "${sealand_event_id:-}" ]]; then
        echo ""
        echo -e "${YELLOW}⚠️  OOO event created on only one calendar. Please check the errors above.${NC}"
    else
        echo ""
        echo -e "${RED}❌ Failed to create OOO events. Please check the errors above.${NC}"
        exit 1
    fi
}

main "$@"