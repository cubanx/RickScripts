#!/bin/bash

_load_jira_env() {
    local jira_env_file="${HOME}/.jira-env"

    if [[ ! -f "$jira_env_file" ]]; then
        return
    fi

    while IFS='=' read -r key value; do
        if [[ -z "$key" || "$key" == \#* ]]; then
            continue
        fi

        case "$key" in
            JIRA_KEYCHAIN_SERVICE)
                if [[ -z "${JIRA_API_TOKEN:-}" && -n "$value" ]]; then
                    export JIRA_API_TOKEN
                    JIRA_API_TOKEN="$(security find-generic-password -a "${USER}" -s "$value" -w 2>/dev/null)"
                fi
                ;;
            JIRA_BASE_URL|JIRA_EMAIL|JIRA_DEFAULT_PROJECT_KEY|JIRA_BOARD_ID)
                if [[ -z "${!key:-}" ]]; then
                    export "$key=$value"
                fi
                ;;
        esac
    done < "$jira_env_file"
}

jira_move_item_to_board() {
    _load_jira_env

    local issue_key=""
    local board_id="${JIRA_BOARD_ID:-1}"
    local base_url="${JIRA_BASE_URL:-}"
    local email="${JIRA_EMAIL:-}"
    local api_token="${JIRA_API_TOKEN:-}"
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --board-id)
                board_id="$2"
                shift 2
                ;;
            --base-url)
                base_url="$2"
                shift 2
                ;;
            --email)
                email="$2"
                shift 2
                ;;
            --api-token)
                api_token="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                cat <<'EOF'
Usage: jira_move_item_to_board ISSUE_KEY [--board-id BOARD_ID] [--dry-run]

Moves an issue from backlog onto a Jira board using the Agile API.

Environment:
  JIRA_BASE_URL     Jira site URL, e.g. https://growth-health.atlassian.net
  JIRA_EMAIL        Atlassian login email
  JIRA_API_TOKEN    Jira API token
  JIRA_BOARD_ID     Optional default board id (defaults to 1)

Examples:
  jira_move_item_to_board FEDEV-560
  jira_move_item_to_board FEDEV-560 --board-id 7
EOF
                return 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ -z "$issue_key" ]]; then
                    issue_key="$1"
                    shift
                else
                    echo "Unexpected argument: $1" >&2
                    return 1
                fi
                ;;
        esac
    done

    if [[ -z "$issue_key" ]]; then
        echo "Missing issue key." >&2
        return 1
    fi

    if [[ -z "$base_url" ]]; then
        echo "Missing JIRA_BASE_URL." >&2
        return 1
    fi

    if [[ -z "$email" ]]; then
        echo "Missing JIRA_EMAIL." >&2
        return 1
    fi

    if [[ -z "$api_token" ]]; then
        echo "Missing JIRA_API_TOKEN." >&2
        return 1
    fi

    local api_url="${base_url%/}/rest/agile/1.0/board/${board_id}/issue"
    local payload
    payload=$(printf '{"issues":["%s"]}' "$issue_key")

    if [[ "$dry_run" == true ]]; then
        echo "POST $api_url"
        echo "$payload"
        return 0
    fi

    local response_file
    response_file="$(mktemp)"
    local http_code
    http_code=$(
        curl -sS \
            -o "$response_file" \
            -w "%{http_code}" \
            -X POST \
            -u "${email}:${api_token}" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            --data "$payload" \
            "$api_url"
    )
    local curl_exit=$?

    if [[ $curl_exit -ne 0 ]]; then
        rm -f "$response_file"
        echo "curl failed while moving $issue_key onto board $board_id." >&2
        return $curl_exit
    fi

    if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
        echo "Jira board move failed with HTTP $http_code." >&2
        cat "$response_file" >&2
        rm -f "$response_file"
        return 1
    fi

    rm -f "$response_file"
    echo "Moved $issue_key onto board $board_id."
}

jmib() {
    jira_move_item_to_board "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    jira_move_item_to_board "$@"
fi
