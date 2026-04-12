#!/usr/bin/env bash
set -euo pipefail

# safe-branch-cleanup.sh — Audit-first worktree & branch cleanup.
#
# Background: `git branch --merged` reports empty branches (tip == main HEAD,
# zero commits) as merged, but those branches may have live uncommitted work
# in their worktree. Using that signal to auto-delete destroys work.
#
# This script never deletes without a multi-check safety gate AND an explicit
# --yes flag. Running with no args performs an audit only.
#
# Modes:
#   (no args) | --audit                      audit, human-readable table
#   --json                                   audit, JSON output
#   --delete <branch|path> --yes             delete a single item if SAFE
#   --delete-safe --yes                      delete every SAFE-classified item
#   --delete-remote <branch> --yes           delete a remote branch (separate)
#
# Safety checks a branch/worktree must pass to be classified SAFE:
#   1. Not PROTECTED (main/master/develop/staging/production/release)
#   2. Worktree (if any) has clean working directory
#   3. Worktree (if any) has no .git/worktrees/<name>/locked file
#   4. Worktree (if any) directory mtime older than SAFE_CLEANUP_ACTIVE_HOURS
#   5. Has at least one commit reachable from main AND main has moved ahead,
#      OR all unique commits have equivalents in main (cherry-pick / squash)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTS_SCRIPT="$SCRIPT_DIR/worktree-ports.sh"
ACTIVE_HOURS="${SAFE_CLEANUP_ACTIVE_HOURS:-24}"
PROTECTED="main master develop staging production release"

find_project_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ]; then echo "$dir"; return 0; fi
        dir="$(dirname "$dir")"
    done
    dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/.git" ]; then echo "$dir"; return 0; fi
        dir="$(dirname "$dir")"
    done
    echo "Error: not in a git repository" >&2
    return 1
}

PROJECT_ROOT="$(find_project_root)"
cd "$PROJECT_ROOT"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

MODE="audit"
TARGET=""
CONFIRMED=false
OUTPUT="table"

while [ $# -gt 0 ]; do
    case "$1" in
        --audit) MODE="audit" ;;
        --json) OUTPUT="json" ;;
        --delete) MODE="delete"; shift; TARGET="${1:-}" ;;
        --delete-safe) MODE="delete-safe" ;;
        --delete-remote) MODE="delete-remote"; shift; TARGET="${1:-}" ;;
        --yes) CONFIRMED=true ;;
        -h|--help)
            awk '/^# safe-branch-cleanup/,/^# {5}OR all unique/' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
    shift || true
done

# ---------------------------------------------------------------------------
# Detect main branch
# ---------------------------------------------------------------------------

detect_main_branch() {
    local mb
    mb=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
    if [ -z "$mb" ]; then
        for b in main master; do
            if git show-ref --verify --quiet "refs/remotes/origin/$b"; then mb="$b"; break; fi
        done
    fi
    echo "${mb:-main}"
}

MAIN_BRANCH="$(detect_main_branch)"

# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------
# classify <branch> [worktree-path]
#
# Echoes one word: PROTECTED | LOCKED | DIRTY | ACTIVE | AHEAD | EMPTY | SAFE
#
# Order matters: cheapest / most protective checks first. PROTECTED and LOCKED
# win over everything; DIRTY wins over ACTIVE wins over commit analysis.

classify() {
    local branch="$1"
    local wt_path="${2:-}"
    local bname
    bname="$(basename "$branch")"

    if echo "$PROTECTED" | grep -qw "$bname"; then
        echo "PROTECTED"; return
    fi

    if [ -n "$wt_path" ]; then
        local wt_git_name
        wt_git_name="$(basename "$wt_path")"
        if [ -f "$PROJECT_ROOT/.git/worktrees/$wt_git_name/locked" ]; then
            echo "LOCKED"; return
        fi
    fi

    if [ -n "$wt_path" ] && [ -d "$wt_path" ]; then
        if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
            echo "DIRTY"; return
        fi
    fi

    if [ -n "$wt_path" ] && [ -d "$wt_path" ]; then
        local wt_mtime
        wt_mtime="$(stat -f %m "$wt_path" 2>/dev/null || stat -c %Y "$wt_path" 2>/dev/null || echo 0)"
        local cutoff=$(( $(date +%s) - ACTIVE_HOURS * 3600 ))
        if [ "$wt_mtime" -gt "$cutoff" ]; then
            echo "ACTIVE"; return
        fi
    fi

    local ahead behind
    ahead="$(git rev-list --count "${MAIN_BRANCH}..${branch}" 2>/dev/null || echo 0)"
    behind="$(git rev-list --count "${branch}..${MAIN_BRANCH}" 2>/dev/null || echo 0)"

    if [ "$ahead" -gt 0 ]; then
        if [ -z "$(git cherry "$MAIN_BRANCH" "$branch" 2>/dev/null | grep '^+' || true)" ]; then
            echo "SAFE"; return
        fi
        echo "AHEAD"; return
    fi

    if [ "$behind" -eq 0 ]; then
        echo "EMPTY"; return
    fi

    echo "SAFE"
}

describe_branch() {
    local branch="$1"
    local ahead behind
    ahead="$(git rev-list --count "${MAIN_BRANCH}..${branch}" 2>/dev/null || echo 0)"
    behind="$(git rev-list --count "${branch}..${MAIN_BRANCH}" 2>/dev/null || echo 0)"
    echo "+${ahead}/-${behind}"
}

describe_age() {
    local wt_path="$1"
    [ -z "$wt_path" ] || [ ! -d "$wt_path" ] && { echo "-"; return; }
    local wt_mtime now age_sec
    wt_mtime="$(stat -f %m "$wt_path" 2>/dev/null || stat -c %Y "$wt_path" 2>/dev/null || echo 0)"
    now="$(date +%s)"
    age_sec=$(( now - wt_mtime ))
    if [ "$age_sec" -lt 3600 ]; then
        echo "$(( age_sec / 60 ))m"
    elif [ "$age_sec" -lt 86400 ]; then
        echo "$(( age_sec / 3600 ))h"
    else
        echo "$(( age_sec / 86400 ))d"
    fi
}

# ---------------------------------------------------------------------------
# Enumeration
# ---------------------------------------------------------------------------
# Build a list of records: "<branch>|<worktree-path>|<status>|<ahead/behind>|<age>"
# Worktree path is empty for branches without a worktree.

build_records() {
    # bash 3.2-compatible: no associative arrays. We accumulate into a
    # newline-separated string and track "seen" branches via a \n-delimited list.
    local records=""
    local seen=""
    local line wt_path="" wt_branch=""

    while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "$line" ]; then
            if [ -n "$wt_branch" ] && [ "$wt_path" != "$PROJECT_ROOT" ]; then
                local status ab age
                status="$(classify "$wt_branch" "$wt_path")"
                ab="$(describe_branch "$wt_branch")"
                age="$(describe_age "$wt_path")"
                records="${records}${wt_branch}|${wt_path}|${status}|${ab}|${age}"$'\n'
                seen="${seen}|${wt_branch}|"
            fi
            wt_path=""; wt_branch=""
            continue
        fi
        case "$line" in
            worktree\ *) wt_path="${line#worktree }" ;;
            branch\ refs/heads/*) wt_branch="${line#branch refs/heads/}" ;;
            detached) wt_branch="" ;;
        esac
    done < <(git worktree list --porcelain 2>/dev/null; echo)

    local br status ab
    while IFS= read -r br; do
        [ -z "$br" ] && continue
        case "$seen" in *"|${br}|"*) continue ;; esac
        status="$(classify "$br" "")"
        ab="$(describe_branch "$br")"
        records="${records}${br}||${status}|${ab}|-"$'\n'
    done < <(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)

    printf '%s' "$records"
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

print_table() {
    local records
    records="$(build_records)"

    [ -z "$records" ] && { echo "No branches found."; return; }

    for status in SAFE EMPTY DIRTY LOCKED ACTIVE AHEAD PROTECTED; do
        local matches=""
        matches="$(echo "$records" | awk -F'|' -v s="$status" '$3 == s')"
        [ -z "$matches" ] && continue
        local count
        count="$(echo "$matches" | wc -l | xargs)"
        echo ""
        case "$status" in
            SAFE)      echo "SAFE to delete ($count) — merged, clean, not active:" ;;
            EMPTY)     echo "EMPTY ($count) — zero unique commits, intent unknown (ASK before deleting):" ;;
            DIRTY)     echo "DIRTY ($count) — uncommitted changes in worktree (NEVER auto-delete):" ;;
            LOCKED)    echo "LOCKED ($count) — git-locked worktree:" ;;
            ACTIVE)    echo "ACTIVE ($count) — worktree modified in the last ${ACTIVE_HOURS}h:" ;;
            AHEAD)     echo "AHEAD ($count) — unique commits not in ${MAIN_BRANCH}:" ;;
            PROTECTED) echo "PROTECTED ($count) — skipped:" ;;
        esac
        echo "$matches" | awk -F'|' '{
            wt = ($2 == "") ? "(no worktree)" : $2
            printf "  %-50s  %-8s  age=%s  %s\n", $1, $4, $5, wt
        }'
    done
    echo ""
}

print_json() {
    local records
    records="$(build_records)"

    echo "["
    local first=true
    while IFS='|' read -r br wt status ab age; do
        [ -z "$br" ] && continue
        $first || echo ","
        first=false
        printf '  {"branch":"%s","worktree":"%s","status":"%s","commits":"%s","age":"%s"}' \
            "$br" "$wt" "$status" "$ab" "$age"
    done <<< "$records"
    echo ""
    echo "]"
}

# ---------------------------------------------------------------------------
# Removal (safety-gated)
# ---------------------------------------------------------------------------
# Re-classifies right before acting. Refuses anything not SAFE.
# Never passes --force to `git worktree remove`.

remove_item() {
    local branch="$1"
    local wt_path="${2:-}"

    local status
    status="$(classify "$branch" "$wt_path")"

    if [ "$status" != "SAFE" ]; then
        echo "  REFUSED: $branch is $status, not SAFE — skipping" >&2
        return 1
    fi

    echo "  Removing $branch"

    if [ -n "$wt_path" ] && [ -d "$wt_path" ]; then
        if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
            echo "  REFUSED: $wt_path became dirty between audit and delete — skipping" >&2
            return 1
        fi
        if ! git worktree remove "$wt_path" 2>/dev/null; then
            echo "  git worktree remove failed (not forcing) — skipping" >&2
            return 1
        fi
        echo "    worktree removed: $wt_path"

        if [ -f "$PORTS_SCRIPT" ]; then
            "$PORTS_SCRIPT" release "$branch" 2>/dev/null || true
            "$PORTS_SCRIPT" release "$(basename "$wt_path")" 2>/dev/null || true
        fi
    fi

    if git show-ref --verify --quiet "refs/heads/$branch"; then
        if git branch -d "$branch" 2>/dev/null; then
            echo "    branch deleted: $branch"
        else
            echo "  git branch -d refused (unmerged per git) — skipping force delete" >&2
            return 1
        fi
    fi

    return 0
}

remove_remote() {
    local branch="$1"
    if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        echo "No remote branch origin/$branch found." >&2
        return 1
    fi
    echo "Deleting remote branch: origin/$branch"
    git push origin --delete "$branch"
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

case "$MODE" in
    audit)
        if [ "$OUTPUT" = "json" ]; then
            print_json
        else
            echo "Audit (main=${MAIN_BRANCH}, active-threshold=${ACTIVE_HOURS}h)"
            print_table
            echo "No changes made. Use --delete <name> --yes or --delete-safe --yes to act."
        fi
        ;;

    delete)
        if [ -z "$TARGET" ]; then
            echo "--delete requires a branch name or worktree path." >&2
            exit 1
        fi
        if [ "$CONFIRMED" != true ]; then
            echo "Refusing to delete without --yes. Run audit first, then add --yes." >&2
            exit 1
        fi

        # Resolve TARGET → branch + worktree path
        branch=""; wt_path=""
        # Exact branch match?
        if git show-ref --verify --quiet "refs/heads/$TARGET"; then
            branch="$TARGET"
            wt_path="$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$TARGET" '
                /^worktree / { p=$2 }
                /^branch / && $2==b { print p }' || true)"
        elif [ -d "$TARGET" ]; then
            wt_path="$(cd "$TARGET" && pwd)"
            branch="$(git -C "$wt_path" branch --show-current 2>/dev/null || true)"
        else
            # Fuzzy: grep worktree list
            line="$(git worktree list 2>/dev/null | grep -i "$TARGET" | head -1 || true)"
            if [ -n "$line" ]; then
                wt_path="$(echo "$line" | awk '{print $1}')"
                branch="$(echo "$line" | sed -E 's/.*\[(.+)\]$/\1/')"
            fi
        fi

        if [ -z "$branch" ]; then
            echo "Could not resolve '$TARGET' to a branch." >&2
            exit 1
        fi

        remove_item "$branch" "$wt_path"
        ;;

    delete-safe)
        if [ "$CONFIRMED" != true ]; then
            echo "Refusing to delete without --yes. Re-run with --delete-safe --yes." >&2
            exit 1
        fi
        echo "Deleting all SAFE items..."
        count=0; removed=0
        while IFS='|' read -r br wt status ab age; do
            [ -z "$br" ] && continue
            [ "$status" = "SAFE" ] || continue
            count=$((count + 1))
            if remove_item "$br" "$wt"; then
                removed=$((removed + 1))
            fi
        done <<< "$(build_records)"
        echo ""
        echo "Done. $removed of $count SAFE items removed."
        ;;

    delete-remote)
        if [ -z "$TARGET" ]; then
            echo "--delete-remote requires a branch name." >&2
            exit 1
        fi
        if [ "$CONFIRMED" != true ]; then
            echo "Refusing to delete remote without --yes." >&2
            exit 1
        fi
        remove_remote "$TARGET"
        ;;
esac
