#!/bin/bash

new_merge_request() {
    local issue_number=""
    local title=""
    local template_path=".gitlab/merge_request_templates/Default.md"
    local description=""
    local how_to_test=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--issue)
                issue_number="$2"
                shift 2
                ;;
            -t|--title)
                title="$2"
                shift 2
                ;;
            --template)
                template_path="$2"
                shift 2
                ;;
            -d|--description)
                description="$2"
                shift 2
                ;;
            --how-to-test)
                how_to_test="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: new_merge_request [OPTIONS]"
                echo "Options:"
                echo "  -i, --issue ISSUE_NUMBER    Issue number to link"
                echo "  -t, --title TITLE           MR title (auto-generated if not provided)"
                echo "  --template PATH             Template file path (default: .gitlab/merge_request_templates/Default.md)"
                echo "  -d, --description DESC      Override description"
                echo "  --how-to-test TEXT          Override testing instructions"
                echo "  -h, --help                  Show this help message"
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
    done
    
    if [[ -z "$issue_number" ]]; then
        read -p "Enter issue number: " issue_number
    fi
    
    if [[ ! -f "$template_path" ]]; then
        echo "Error: Template file not found: $template_path" >&2
        return 1
    fi
    
    template_content=$(cat "$template_path")
    
    final_description="$template_content"
    final_description=$(echo "$final_description" | sed 's/%{issue_id}//g')
    final_description=$(echo "$final_description" | sed '/### Environment/,/## Checklist/{ /### Environment/d; /## Checklist/!d; }')
    final_description=$(echo "$final_description" | sed '/- \[ \] Does it run on all platforms/d')
    final_description=$(echo "$final_description" | sed '/- \[ \] Have all static strings been translated/d')
    final_description=$(echo "$final_description" | sed 's/(except screens)//g')
    final_description=$(echo "$final_description" | sed '/source_branch/d')
    final_description=$(echo "$final_description" | sed "s/%{issue_id}/#$issue_number/g")
    
    if [[ -n "$description" ]]; then
        final_description=$(echo "$final_description" | sed "s/Enter a brief description of the changes introduced by this merge request./$description/")
    fi
    
    if [[ -n "$how_to_test" ]]; then
        final_description=$(echo "$final_description" | sed "s/Enter a brief description of how to test the changes introduced by this merge request./$how_to_test/")
    fi
    
    if [[ -z "$title" ]]; then
        issue_json=$(glab issue view "$issue_number" --output=json)
        title=$(echo "$issue_json" | jq -r '.title')
    fi
    
    formatted_title="[#${issue_number}] $title"
    
    echo "Creating merge request: $formatted_title"
    
    glab mr create \
        --yes \
        --related-issue "$issue_number" \
        --copy-issue-labels \
        --draft \
        --remove-source-branch \
        --assignee rick.diaz \
        --title "$formatted_title" \
        --description "$final_description"
}

alias nmr='new_merge_request'