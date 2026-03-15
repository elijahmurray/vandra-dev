#!/usr/bin/env bash
set -euo pipefail

# worktree-cleanup.sh — Unified worktree cleanup
#
# Single ticket:  worktree-cleanup.sh RAI-551
# Bulk cleanup:   worktree-cleanup.sh --all
# Dry run:        worktree-cleanup.sh --all --dry-run

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Find project root (prefer .git directory over .git file)
# ---------------------------------------------------------------------------
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
    echo "Error: not in a git repository" >&2; return 1
}

PROJECT_ROOT="$(find_project_root)"
cd "$PROJECT_ROOT"

PORTS_SCRIPT="$SCRIPT_DIR/worktree-ports.sh"
SLOTS_FILE="$PROJECT_ROOT/trees/.worktree-slots.json"
PROTECTED_BRANCHES="main master develop staging production release"

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
MODE=""
TARGET=""
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --all)    MODE="all" ;;
        --dry-run) DRY_RUN=true ;;
        *)        MODE="single"; TARGET="$arg" ;;
    esac
done

if [ -z "$MODE" ]; then
    echo "Usage:"
    echo "  worktree-cleanup.sh <ticket-id>   Clean up a single ticket (e.g. RAI-551)"
    echo "  worktree-cleanup.sh --all          Clean up all merged branches"
    echo "  Add --dry-run to preview without changes"
    exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

detect_main_branch() {
    local mb=""
    mb=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
    if [ -z "$mb" ]; then
        for b in main master; do
            if git show-ref --verify --quiet "refs/remotes/origin/$b"; then mb="$b"; break; fi
        done
    fi
    echo "${mb:-main}"
}

detect_main_database() {
    for env_file in ".env" "backend/.env" ".env.local" ".env.development" "app/.env" "api/.env"; do
        if [ -f "$env_file" ]; then
            local db_url=$(grep -E "^DATABASE_URL=" "$env_file" 2>/dev/null | head -1 || true)
            if [ -n "$db_url" ]; then
                local db_name=$(echo "$db_url" | sed -E 's|.*://[^/]*/([^?#"[:space:]]*).*|\1|' | sed 's|"||g' | xargs)
                if [ -n "$db_name" ] && [ "$db_name" != "DATABASE_URL" ]; then
                    echo "$db_name"; return 0
                fi
            fi
            local db_name=$(grep -E "^(DB_NAME|DATABASE_NAME|POSTGRES_DB)=" "$env_file" 2>/dev/null | head -1 | cut -d'=' -f2 | sed 's|"||g' | xargs || true)
            if [ -n "$db_name" ]; then echo "$db_name"; return 0; fi
        fi
    done
    return 1
}

is_branch_merged() {
    local branch="$1" base="$2"
    local bname=$(basename "$branch")

    if echo "$PROTECTED_BRANCHES" | grep -qw "$bname"; then return 1; fi

    # Traditional merge
    if git branch --merged "$base" 2>/dev/null | grep -q "^[* ]*${bname}$"; then return 0; fi

    # Cherry-pick / squash detection
    if [ -z "$(git cherry "$base" "$branch" 2>/dev/null | grep '^+')" ]; then return 0; fi

    # Remote equivalent merged
    if git show-ref --verify --quiet "refs/remotes/origin/$bname"; then
        if [ -z "$(git rev-list "$base"..origin/"$bname" 2>/dev/null)" ]; then return 0; fi
    fi

    # PR merge commit grep
    if git log "$base" --grep="$bname" --oneline -100 2>/dev/null | grep -qE "(Merge pull request|Merge branch|#[0-9]+)"; then
        return 0
    fi

    return 1
}

# Clean up a single worktree by ticket ID or branch name
cleanup_single() {
    local target="$1"
    local main_branch="$2"

    echo "Looking for worktree matching: $target"

    # Find the worktree directory
    local wt_dir=""
    if [ -d "trees/" ]; then
        wt_dir=$(ls -d trees/*"$target"* 2>/dev/null | head -1 || true)
        # Try case-insensitive
        if [ -z "$wt_dir" ]; then
            wt_dir=$(find trees/ -maxdepth 1 -type d -iname "*${target}*" 2>/dev/null | head -1 || true)
        fi
    fi

    # Find the branch name from git worktree list
    local branch=""
    local wt_path=""
    if [ -n "$wt_dir" ]; then
        wt_path="$PROJECT_ROOT/$wt_dir"
        branch=$(cd "$wt_path" 2>/dev/null && git branch --show-current 2>/dev/null || true)
    fi

    # Fallback: search git worktree list
    if [ -z "$branch" ]; then
        local wt_line=$(git worktree list 2>/dev/null | grep -i "$target" | head -1 || true)
        if [ -n "$wt_line" ]; then
            wt_path=$(echo "$wt_line" | awk '{print $1}')
            branch=$(echo "$wt_line" | sed -E 's/.*\[(.+)\]$/\1/' || true)
            wt_dir=$(echo "$wt_path" | sed "s|^$PROJECT_ROOT/||")
        fi
    fi

    # Fallback: search local branches
    if [ -z "$branch" ]; then
        branch=$(git branch | sed 's/^[* +]*//' | grep -i "$target" | head -1 || true)
    fi

    if [ -z "$branch" ] && [ -z "$wt_dir" ]; then
        echo "Could not find worktree or branch matching: $target"
        exit 1
    fi

    echo "Found: branch=$branch worktree=$wt_dir"

    # Step 1: Pull main
    echo ""
    echo "Pulling latest main..."
    git fetch origin "$main_branch" --quiet 2>/dev/null || true
    # Only pull if we're on main
    local current=$(git branch --show-current 2>/dev/null || true)
    if [ "$current" = "$main_branch" ]; then
        git pull origin "$main_branch" --ff-only 2>/dev/null || true
    fi

    # Step 2: Remove worktree
    if [ -n "$wt_path" ] && [ -d "$wt_path" ]; then
        echo "Removing worktree: $wt_dir"
        if [ "$DRY_RUN" = true ]; then
            echo "  [dry-run] Would remove $wt_path"
        else
            git worktree remove "$wt_path" --force 2>/dev/null || {
                echo "  Force remove failed, cleaning up manually..."
                rm -rf "$wt_path"
                git worktree prune
            }
            echo "  Worktree removed"
        fi
    fi

    # Step 3: Release port slot
    if [ -n "$branch" ] && [ -f "$PORTS_SCRIPT" ] && [ -f "$SLOTS_FILE" ]; then
        echo "Releasing port slot for: $branch"
        if [ "$DRY_RUN" = true ]; then
            echo "  [dry-run] Would release slot for $branch"
        else
            "$PORTS_SCRIPT" release "$branch" 2>/dev/null || true
            # Also try with just the worktree directory name
            if [ -n "$wt_dir" ]; then
                local dir_name=$(basename "$wt_dir")
                "$PORTS_SCRIPT" release "$dir_name" 2>/dev/null || true
            fi
            echo "  Port slot released"
        fi
    fi

    # Step 4: Drop branch database
    if command -v dropdb &>/dev/null; then
        local main_db=$(detect_main_database || true)
        if [ -n "$main_db" ] && [ -n "$wt_dir" ]; then
            local dir_name=$(basename "$wt_dir")
            local branch_db="${main_db}_${dir_name}"
            local pg_user="${PGUSER:-$USER}"
            local pg_host="${PGHOST:-localhost}"
            local pg_port="${PGPORT:-5432}"

            if psql -h "$pg_host" -p "$pg_port" -U "$pg_user" -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$branch_db"; then
                echo "Dropping database: $branch_db"
                if [ "$DRY_RUN" = true ]; then
                    echo "  [dry-run] Would drop $branch_db"
                else
                    dropdb -h "$pg_host" -p "$pg_port" -U "$pg_user" --if-exists "$branch_db" 2>/dev/null && echo "  Database dropped" || echo "  Failed to drop database"
                fi
            else
                echo "No branch database found ($branch_db)"
            fi
        fi
    fi

    # Step 5: Delete branch
    if [ -n "$branch" ]; then
        echo "Deleting branch: $branch"
        if [ "$DRY_RUN" = true ]; then
            echo "  [dry-run] Would delete $branch"
        else
            git branch -d "$branch" 2>/dev/null || git branch -D "$branch" 2>/dev/null || echo "  Branch already deleted or not found locally"
            git push origin --delete "$branch" 2>/dev/null || true
            echo "  Branch deleted"
        fi
    fi

    # Summary
    echo ""
    echo "Cleanup complete for: $target"
    [ -n "$wt_dir" ] && echo "  Worktree: $wt_dir (removed)"
    [ -n "$branch" ] && echo "  Branch: $branch (deleted)"
    echo ""
}

# Clean up all merged branches/worktrees
cleanup_all() {
    local main_branch="$1"

    echo "Fetching latest..."
    git fetch --all --prune --quiet

    # Ensure we're on main
    git checkout "$main_branch" 2>/dev/null || true
    git pull origin "$main_branch" --ff-only 2>/dev/null || true

    local total=0

    # Worktrees
    echo ""
    echo "Checking worktrees..."
    local worktrees=$(git worktree list --porcelain 2>/dev/null | grep "^worktree" | cut -d' ' -f2)
    for wt in $worktrees; do
        [ "$wt" = "$PROJECT_ROOT" ] && continue
        [[ "$wt" == *"/trees/"* ]] || continue

        local br=$(cd "$wt" 2>/dev/null && git branch --show-current 2>/dev/null || true)
        [ -z "$br" ] && continue

        if is_branch_merged "$br" "$main_branch"; then
            echo "  Merged: $br"

            if [ "$DRY_RUN" = true ]; then
                echo "    [dry-run] Would remove worktree + branch + slot"
            else
                # Release port slot
                [ -f "$PORTS_SCRIPT" ] && "$PORTS_SCRIPT" release "$br" 2>/dev/null || true

                # Remove worktree
                git worktree remove "$wt" --force 2>/dev/null || { rm -rf "$wt"; git worktree prune; }

                # Delete branch
                git branch -d "$br" 2>/dev/null || git branch -D "$br" 2>/dev/null || true
                git push origin --delete "$br" 2>/dev/null || true

                echo "    Cleaned up"
            fi
            total=$((total + 1))
        else
            echo "  Keeping: $br (not merged)"
        fi
    done

    # Local branches without worktrees
    echo ""
    echo "Checking local branches..."
    local branches=$(git branch | sed 's/^[* +]*//' | grep -vE "^($main_branch)$" || true)
    if [ -n "$branches" ]; then
        while IFS= read -r br; do
            br=$(echo "$br" | xargs)
            [ -z "$br" ] && continue

            if is_branch_merged "$br" "$main_branch"; then
                echo "  Merged: $br"
                if [ "$DRY_RUN" = true ]; then
                    echo "    [dry-run] Would delete"
                else
                    git branch -D "$br" 2>/dev/null || true
                    git push origin --delete "$br" 2>/dev/null || true
                    echo "    Deleted"
                fi
                total=$((total + 1))
            fi
        done <<< "$branches"
    fi

    # Databases
    if command -v psql &>/dev/null; then
        local main_db=$(detect_main_database || true)
        if [ -n "$main_db" ]; then
            echo ""
            echo "Checking databases..."
            local pg_user="${PGUSER:-$USER}"
            local pg_host="${PGHOST:-localhost}"
            local pg_port="${PGPORT:-5432}"

            local branch_dbs=$(psql -h "$pg_host" -p "$pg_port" -U "$pg_user" -lqt 2>/dev/null | cut -d \| -f 1 | xargs | tr ' ' '\n' | grep -E "^${main_db}_" || true)
            for db in $branch_dbs; do
                local db_branch=$(echo "$db" | sed "s/^${main_db}_//")
                if ! git branch -a 2>/dev/null | grep -qE "(^|/).*${db_branch}"; then
                    echo "  Orphaned: $db"
                    if [ "$DRY_RUN" = true ]; then
                        echo "    [dry-run] Would drop"
                    else
                        dropdb -h "$pg_host" -p "$pg_port" -U "$pg_user" --if-exists "$db" 2>/dev/null && echo "    Dropped" || echo "    Failed to drop"
                    fi
                fi
            done
        fi
    fi

    # Prune
    git worktree prune 2>/dev/null || true
    git gc --auto --quiet 2>/dev/null || true

    echo ""
    echo "Cleanup complete. $total item(s) processed."
    echo ""
    echo "Remaining worktrees:"
    git worktree list | sed 's/^/  /'
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

MAIN_BRANCH=$(detect_main_branch)

if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN — no changes will be made"
    echo ""
fi

case "$MODE" in
    single) cleanup_single "$TARGET" "$MAIN_BRANCH" ;;
    all)    cleanup_all "$MAIN_BRANCH" ;;
esac
