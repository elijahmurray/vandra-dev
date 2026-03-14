#!/usr/bin/env bash
set -euo pipefail

# worktree-tab-set.sh — Auto-detect worktree context and rename terminal tab
# Run from within a worktree to rename the current tab based on branch/ports.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find project root
find_project_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

PROJECT_ROOT="$(find_project_root)" || { echo "Not in a git repo" >&2; exit 1; }

# Get current branch
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [ -z "$BRANCH" ]; then
    echo "Could not detect branch" >&2
    exit 1
fi

# Parse type and name from branch (e.g. feature/RAI-552-value-creation-agent)
BRANCH_TYPE=$(echo "$BRANCH" | cut -d'/' -f1)
BRANCH_NAME=$(echo "$BRANCH" | cut -d'/' -f2-)

# Capitalize type
DISPLAY_TYPE=$(echo "$BRANCH_TYPE" | sed 's/^./\U&/')

# Title case the name (replace hyphens with spaces, capitalize words)
DISPLAY_NAME=$(echo "$BRANCH_NAME" | sed 's/-/ /g' | sed 's/\b./\U&/g')

# Get port summary if .worktree.json exists
PORT_DISPLAY="N/A"
PORTS_SCRIPT="$SCRIPT_DIR/worktree-ports.sh"
if [ -f "$PORTS_SCRIPT" ]; then
    SLOT=$("$PORTS_SCRIPT" get "$BRANCH" 2>/dev/null || echo "")
    if [ -n "$SLOT" ]; then
        PORT_DISPLAY=$("$PORTS_SCRIPT" summary "$SLOT" 2>/dev/null || echo "N/A")
    fi
fi

# Read tab format from .worktree.json or use default
TAB_FORMAT="{type}: {name} ({ports})"
WORKTREE_CONFIG="$PROJECT_ROOT/.worktree.json"
# Check parent too (worktrees are in trees/ subdir)
if [ ! -f "$WORKTREE_CONFIG" ]; then
    WORKTREE_CONFIG="$(dirname "$(dirname "$PROJECT_ROOT")")/.worktree.json"
fi
if [ -f "$WORKTREE_CONFIG" ] && command -v jq >/dev/null 2>&1; then
    custom_format=$(jq -r '.tabFormat // empty' "$WORKTREE_CONFIG" 2>/dev/null)
    if [ -n "$custom_format" ]; then
        TAB_FORMAT="$custom_format"
    fi
fi

# Build and set title
"$SCRIPT_DIR/worktree-tab-rename.sh" --format "$TAB_FORMAT" --type "$DISPLAY_TYPE" --name "$DISPLAY_NAME" --ports "$PORT_DISPLAY"

# Build title string for display
TITLE="$TAB_FORMAT"
TITLE="${TITLE//\{type\}/$DISPLAY_TYPE}"
TITLE="${TITLE//\{name\}/$DISPLAY_NAME}"
TITLE="${TITLE//\{ports\}/$PORT_DISPLAY}"

echo "Tab renamed: $TITLE"
