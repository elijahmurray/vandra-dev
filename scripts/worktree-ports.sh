#!/usr/bin/env bash
set -euo pipefail

# worktree-ports.sh — Port slot management for git worktrees
#
# Subcommands:
#   assign <branch>   — find lowest unused slot, assign it, print slot number
#   release <branch>  — remove branch from slots file
#   get <branch>      — print slot number for branch (or empty if not found)
#   summary <slot>    — read .worktree.json, print port summary like "3001/8001"
#   rewrite <file> <var> <base_port> <slot> — update port in env file
#   list              — show all slots with branch names and ports

MAX_SLOT=99

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "Error: could not find project root (.git directory)" >&2
  return 1
}

PROJECT_ROOT="$(find_project_root)"
SLOTS_FILE="$PROJECT_ROOT/trees/.worktree-slots.json"

# JSON helper — use jq if available, fall back to python3
json_read() {
  local file="$1"
  if command -v jq &>/dev/null; then
    cat "$file"
  else
    python3 -c "import json, sys; print(json.dumps(json.load(open(sys.argv[1])), indent=2))" "$file"
  fi
}

json_get_slot_for_branch() {
  local file="$1" branch="$2"
  if command -v jq &>/dev/null; then
    jq -r --arg b "$branch" 'to_entries[] | select(.value == $b) | .key' "$file" | head -1
  else
    python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
branch = sys.argv[2]
for k, v in data.items():
    if v == branch:
        print(k)
        break
" "$file" "$branch"
  fi
}

json_get_branch_for_slot() {
  local file="$1" slot="$2"
  if command -v jq &>/dev/null; then
    jq -r --arg s "$slot" '.[$s] // empty' "$file"
  else
    python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
val = data.get(sys.argv[2], '')
if val:
    print(val)
" "$file" "$slot"
  fi
}

json_get_all_slots() {
  local file="$1"
  if command -v jq &>/dev/null; then
    jq -r 'keys[] | tonumber' "$file" | sort -n
  else
    python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
for k in sorted(data.keys(), key=int):
    print(k)
" "$file"
  fi
}

json_set_slot() {
  local file="$1" slot="$2" branch="$3"
  if command -v jq &>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    jq --arg s "$slot" --arg b "$branch" '.[$s] = $b' "$file" > "$tmp" && mv "$tmp" "$file"
  else
    python3 -c "
import json, sys
f = sys.argv[1]
data = json.load(open(f))
data[sys.argv[2]] = sys.argv[3]
json.dump(data, open(f, 'w'), indent=2)
print()
" "$file" "$slot" "$branch"
  fi
}

json_remove_slot() {
  local file="$1" slot="$2"
  if command -v jq &>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    jq --arg s "$slot" 'del(.[$s])' "$file" > "$tmp" && mv "$tmp" "$file"
  else
    python3 -c "
import json, sys
f = sys.argv[1]
data = json.load(open(f))
data.pop(sys.argv[2], None)
json.dump(data, open(f, 'w'), indent=2)
" "$file" "$slot"
  fi
}

json_list_entries() {
  local file="$1"
  if command -v jq &>/dev/null; then
    jq -r 'to_entries | sort_by(.key | tonumber) | .[] | "\(.key)\t\(.value)"' "$file"
  else
    python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
for k in sorted(data.keys(), key=int):
    print(f'{k}\t{data[k]}')
" "$file"
  fi
}

json_read_worktree_config() {
  local file="$1" slot="$2"
  if command -v jq &>/dev/null; then
    jq -r --argjson s "$slot" '[.services[] | .basePort + $s] | map(tostring) | join("/")' "$file"
  else
    python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
slot = int(sys.argv[2])
ports = [str(s['basePort'] + slot) for s in data.get('services', [])]
print('/'.join(ports))
" "$file" "$slot"
  fi
}

ensure_slots_file() {
  if [ ! -f "$SLOTS_FILE" ]; then
    mkdir -p "$(dirname "$SLOTS_FILE")"
    echo '{"0": "main"}' > "$SLOTS_FILE"
  fi
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_assign() {
  local branch="${1:?Usage: worktree-ports.sh assign <branch>}"
  ensure_slots_file

  # Check if branch already has a slot
  local existing
  existing="$(json_get_slot_for_branch "$SLOTS_FILE" "$branch")"
  if [ -n "$existing" ]; then
    echo "$existing"
    return 0
  fi

  # Find lowest unused slot (fill gaps)
  local used_slots slot=0
  used_slots="$(json_get_all_slots "$SLOTS_FILE")"

  while true; do
    if [ "$slot" -gt "$MAX_SLOT" ]; then
      echo "Error: maximum slot count ($MAX_SLOT) exceeded" >&2
      return 1
    fi
    if ! echo "$used_slots" | grep -qx "$slot"; then
      break
    fi
    slot=$((slot + 1))
  done

  json_set_slot "$SLOTS_FILE" "$slot" "$branch"
  echo "$slot"
}

cmd_release() {
  local branch="${1:?Usage: worktree-ports.sh release <branch>}"
  ensure_slots_file

  local slot
  slot="$(json_get_slot_for_branch "$SLOTS_FILE" "$branch")"
  if [ -n "$slot" ]; then
    json_remove_slot "$SLOTS_FILE" "$slot"
  fi
}

cmd_get() {
  local branch="${1:?Usage: worktree-ports.sh get <branch>}"
  ensure_slots_file

  json_get_slot_for_branch "$SLOTS_FILE" "$branch"
}

cmd_summary() {
  local slot="${1:?Usage: worktree-ports.sh summary <slot>}"
  local config="$PROJECT_ROOT/.worktree.json"

  if [ ! -f "$config" ]; then
    echo "Error: .worktree.json not found in project root ($PROJECT_ROOT)" >&2
    return 1
  fi

  json_read_worktree_config "$config" "$slot"
}

cmd_rewrite() {
  local file="${1:?Usage: worktree-ports.sh rewrite <file> <var> <base_port> <slot>}"
  local var="${2:?}"
  local base_port="${3:?}"
  local slot="${4:?}"

  local new_port=$((base_port + slot))

  if [ ! -f "$file" ]; then
    echo "Error: file not found: $file" >&2
    return 1
  fi

  # Pattern 1: VAR=http://localhost:PORT/path (URL with optional path)
  # Pattern 2: VAR=http://localhost:PORT (URL without path)
  # Pattern 3: VAR=PORT (simple port number)
  #
  # We try URL patterns first (more specific), then fall back to simple port.

  # Replace URL with path: VAR=http(s)://host:BASE_PORT/path → VAR=http(s)://host:NEW_PORT/path
  if grep -qE "^${var}=https?://[^:]+:${base_port}/" "$file"; then
    sed -i'' -e "s|^\(${var}=https\{0,1\}://[^:]*:\)${base_port}\(/\)|\1${new_port}\2|" "$file"
  # Replace URL without path: VAR=http(s)://host:BASE_PORT
  elif grep -qE "^${var}=https?://[^:]+:${base_port}$" "$file"; then
    sed -i'' -e "s|^\(${var}=https\{0,1\}://[^:]*:\)${base_port}$|\1${new_port}|" "$file"
  # Replace simple port: VAR=BASE_PORT
  elif grep -qE "^${var}=${base_port}" "$file"; then
    sed -i'' -e "s|^\(${var}=\)${base_port}|\1${new_port}|" "$file"
  else
    # Variable not found — append it with the new port value
    echo "${var}=${new_port}" >> "$file"
    echo "Note: ${var} not found in $file, appended ${var}=${new_port}" >&2
  fi
}

cmd_list() {
  ensure_slots_file

  local config="$PROJECT_ROOT/.worktree.json"
  local has_config=false
  [ -f "$config" ] && has_config=true

  printf "%-6s %-30s %s\n" "SLOT" "BRANCH" "PORTS"
  printf "%-6s %-30s %s\n" "----" "------" "-----"

  while IFS=$'\t' read -r slot branch; do
    local ports="-"
    if $has_config; then
      ports="$(json_read_worktree_config "$config" "$slot" 2>/dev/null || echo "-")"
    fi
    printf "%-6s %-30s %s\n" "$slot" "$branch" "$ports"
  done < <(json_list_entries "$SLOTS_FILE")
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

cmd="${1:-}"
shift || true

case "$cmd" in
  assign)  cmd_assign "$@" ;;
  release) cmd_release "$@" ;;
  get)     cmd_get "$@" ;;
  summary) cmd_summary "$@" ;;
  rewrite) cmd_rewrite "$@" ;;
  list)    cmd_list ;;
  *)
    echo "Usage: worktree-ports.sh <assign|release|get|summary|rewrite|list> [args...]" >&2
    exit 1
    ;;
esac
