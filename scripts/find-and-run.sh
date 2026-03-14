#!/bin/bash

# find-and-run.sh
# Universal script wrapper that finds and executes scripts from any directory
# Usage: find-and-run.sh <script-name> [arguments...]
#
# This script searches up the directory tree to find the project root (containing .git)
# then executes the requested script from multiple possible locations

set -e

# Get the script name and shift to get remaining arguments
SCRIPT_NAME="$1"
shift

# Function to find project root (directory containing .git)
find_project_root() {
    local current_dir="$(pwd)"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/.git" ]] || [[ -f "$current_dir/.git" ]]; then
            echo "$current_dir"
            return
        fi
        current_dir="$(dirname "$current_dir")"
    done
    # If no git root found, return empty
    echo ""
}

# Find project root
PROJECT_ROOT=$(find_project_root)

if [ -z "$PROJECT_ROOT" ]; then
    echo "❌ Error: Not in a git repository" >&2
    exit 1
fi

# Construct full script path - try multiple locations in order of priority

# 1. Check CLAUDE_PLUGIN_ROOT/scripts/ (plugin installation path)
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/$SCRIPT_NAME" ]; then
    SCRIPT_PATH="${CLAUDE_PLUGIN_ROOT}/scripts/$SCRIPT_NAME"
# 2. Try .claude/scripts (submodule path)
elif [ -f "$PROJECT_ROOT/.claude/scripts/$SCRIPT_NAME" ]; then
    SCRIPT_PATH="$PROJECT_ROOT/.claude/scripts/$SCRIPT_NAME"
# 3. Try scripts directory (for the plugin repo itself)
elif [ -f "$PROJECT_ROOT/scripts/$SCRIPT_NAME" ]; then
    SCRIPT_PATH="$PROJECT_ROOT/scripts/$SCRIPT_NAME"
else
    echo "❌ Error: Script not found: $SCRIPT_NAME" >&2
    echo "Searched in:" >&2
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
        echo "  - ${CLAUDE_PLUGIN_ROOT}/scripts/" >&2
    fi
    echo "  - $PROJECT_ROOT/.claude/scripts/" >&2
    echo "  - $PROJECT_ROOT/scripts/" >&2
    exit 1
fi

# Make sure script is executable
chmod +x "$SCRIPT_PATH" 2>/dev/null || true

# Execute the script with all remaining arguments
exec "$SCRIPT_PATH" "$@"
