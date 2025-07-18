#!/bin/bash

# RickScripts - Bash Version
# Personal development utilities and Git workflow helpers

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all function files
for script in "$SCRIPT_DIR"/*.sh; do
    # Skip sourcing this main script and completion script to avoid recursion
    local basename=$(basename "$script")
    if [[ "$basename" != "rick-scripts.sh" && "$basename" != "rick-scripts-completion.sh" ]]; then
        source "$script"
    fi
done

# Load bash completion if available
if [[ -f "$SCRIPT_DIR/rick-scripts-completion.sh" ]]; then
    source "$SCRIPT_DIR/rick-scripts-completion.sh"
fi

# Export global variables for package filters (World50 applications)
export mem="--filter=@world50/member-app"
export gl="--filter=@world50/group-leader-app"
export pro="--filter=@world50/prospector-app"
export auth="--filter=@world50/authentication-app"
export petl="--filter=@world50/prospector-etl"

echo "RickScripts (Bash) loaded successfully!"
echo "Available functions:"
echo "  clear_node_modules (cnm)           - Remove node_modules and reinstall with pnpm"
echo "  get_git_stash (ggs)                - Interactive stash selection and pop"
echo "  move_issue_state (mis)             - Move GitLab issues between workflow states"
echo "  new_merge_request (nmr)            - Create GitLab MR with template"
echo "  open_project_folder (opf)          - Open directory in VS Code using fzf"
echo "  remove_history_duplicates (rhd)    - Remove duplicate entries from bash history"
echo "  remove_history_item (rhi)          - Remove specific items from bash history"
echo "  remove_local_branches_that_are_merged (rlb) - Clean up merged branches"
echo "  switch_branch (sb)                 - Interactive branch switching"
echo "  switch_merge_request (smr)         - Interactive MR checkout"
echo ""
echo "Global variables available:"
echo "  \$mem, \$gl, \$pro, \$auth, \$petl - Package filters for World50 applications"