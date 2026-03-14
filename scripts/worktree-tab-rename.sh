#!/usr/bin/env bash
set -euo pipefail

# worktree-tab-rename.sh — Rename terminal tab/window title
#
# Usage:
#   worktree-tab-rename.sh "Title String"
#   worktree-tab-rename.sh [--format FORMAT] [--type TYPE] [--name NAME] [--ports PORTS]
#
# Format placeholders: {type}, {name}, {ports}
# Default format: "{type}: {name} ({ports})"

DEFAULT_FORMAT="{type}: {name} ({ports})"

set_title() {
  local title="$1"

  # Set tab + window title
  printf '\033]0;%s\007' "$title"
  # Set tab title only
  printf '\033]1;%s\007' "$title"
  # Set window title only
  printf '\033]2;%s\007' "$title"

  # iTerm2 badge support
  if [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
    printf '\033]1337;SetBadgeFormat=%s\007' "$(printf '%s' "$title" | base64)"
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

# Simple mode: single argument used as title directly
if [ $# -eq 1 ] && [[ "$1" != --* ]]; then
  set_title "$1"
  exit 0
fi

# Flag mode
format="$DEFAULT_FORMAT"
type_val=""
name_val=""
ports_val=""

while [ $# -gt 0 ]; do
  case "$1" in
    --format)
      format="${2:?--format requires a value}"
      shift 2
      ;;
    --type)
      type_val="${2:?--type requires a value}"
      shift 2
      ;;
    --name)
      name_val="${2:?--name requires a value}"
      shift 2
      ;;
    --ports)
      ports_val="${2:?--ports requires a value}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: worktree-tab-rename.sh [--format FORMAT] [--type TYPE] [--name NAME] [--ports PORTS]" >&2
      exit 1
      ;;
  esac
done

# Build title from format string
title="$format"
title="${title//\{type\}/$type_val}"
title="${title//\{name\}/$name_val}"
title="${title//\{ports\}/$ports_val}"

# Clean up empty placeholders — remove empty parens, trailing colons, extra spaces
title="$(echo "$title" | sed -e 's/ ()//g' -e 's/: *$//g' -e 's/  */ /g' -e 's/^ *//;s/ *$//')"

set_title "$title"
