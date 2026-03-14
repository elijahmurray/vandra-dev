# git-cleanup

Clean up merged branches, unused worktrees, port slots, and databases from the repository.

## Instructions

This command helps maintain a clean git environment by removing:
- Worktrees for branches that have been merged
- Port slots for removed worktrees
- Local branches that have been merged into main
- Remote branches that have been merged
- Remote tracking branches that no longer exist
- Branch-specific databases that are no longer needed

### 0. Setup and Preparation
```bash
#!/bin/bash
set -euo pipefail
trap 'echo "Cleanup failed at line $LINENO"' ERR

DRY_RUN="${1:-no}"
INTERACTIVE="${2:-yes}"

if [[ "$DRY_RUN" == "dry-run" ]] || [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "DRY RUN MODE - No changes will be made"
    DRY_RUN="yes"
fi

if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "You have uncommitted changes. Please commit or stash them first."
    exit 1
fi

echo "Preparing git cleanup..."

git fetch --all --prune

MAIN_BRANCH=""
if [ -z "$MAIN_BRANCH" ]; then
    MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
fi
if [ -z "$MAIN_BRANCH" ]; then
    for branch in main master; do
        if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
            MAIN_BRANCH="$branch"
            break
        fi
    done
fi
if [ -z "$MAIN_BRANCH" ]; then
    MAIN_BRANCH="main"
fi

echo "Using main branch: $MAIN_BRANCH"
git checkout "$MAIN_BRANCH" 2>/dev/null || git checkout main 2>/dev/null || git checkout master 2>/dev/null

echo "Updating $MAIN_BRANCH branch from origin..."
git pull origin "$MAIN_BRANCH" --ff-only || git reset --hard "origin/$MAIN_BRANCH"

PROTECTED_BRANCHES="main master develop staging production release"
```

### 1. Enhanced Merge Detection Function
```bash
is_branch_merged() {
    local branch="$1"
    local base_branch="${2:-$MAIN_BRANCH}"
    local branch_name=$(basename "$branch")

    if echo "$PROTECTED_BRANCHES" | grep -qw "$branch_name"; then
        return 1
    fi

    # Method 1: Traditional merge check
    if [[ "$branch" != origin/* ]]; then
        if git branch --merged "$base_branch" 2>/dev/null | grep -q "^[* ]*$branch_name$"; then
            return 0
        fi
    fi

    # Method 2: Remote branch check
    if [[ "$branch" == origin/* ]]; then
        if [ -z "$(git rev-list "$base_branch".."$branch" 2>/dev/null)" ]; then
            return 0
        fi
        local ahead_count=$(git rev-list --count "$base_branch".."$branch" 2>/dev/null || echo "1")
        if [ "$ahead_count" = "0" ]; then
            return 0
        fi
    else
        if git show-ref --verify --quiet "refs/remotes/origin/$branch_name"; then
            if [ -z "$(git rev-list "$base_branch"..origin/"$branch_name" 2>/dev/null)" ]; then
                return 0
            fi
        fi
        if [ -z "$(git cherry "$base_branch" "$branch" 2>/dev/null | grep '^+')" ]; then
            return 0
        fi
    fi

    # Method 3: PR merge commit detection
    if git log "$base_branch" --grep="$branch_name" --oneline -100 2>/dev/null | grep -qE "(Merge pull request|Merge branch|#[0-9]+).*$branch_name"; then
        return 0
    fi

    # Method 4: Squash/rebase detection
    if [[ "$branch" != origin/* ]]; then
        local branch_commits=$(git rev-list --count "$base_branch".."$branch" 2>/dev/null || echo "0")
        if [ "$branch_commits" -gt 0 ] && [ "$branch_commits" -lt 20 ]; then
            local branch_messages=$(git log --format="%s" "$base_branch".."$branch" 2>/dev/null)
            if [ -n "$branch_messages" ]; then
                local found_in_main=0
                local total_commits=0
                while IFS= read -r commit_msg; do
                    [ -z "$commit_msg" ] && continue
                    ((total_commits++))
                    if git log "$base_branch" --grep="$commit_msg" --oneline -1 2>/dev/null | grep -q "."; then
                        ((found_in_main++))
                    fi
                done <<< "$branch_messages"
                if [ "$total_commits" -gt 0 ] && [ $((found_in_main * 100 / total_commits)) -gt 60 ]; then
                    return 0
                fi
            fi
        fi
    fi

    return 1
}

safe_delete() {
    local item_type="$1"
    local item_name="$2"
    local delete_command="$3"

    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "[DRY RUN] Would delete $item_type: $item_name"
        return 0
    fi

    if [[ "$INTERACTIVE" == "yes" ]]; then
        read -p "Delete $item_type '$item_name'? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "  Skipped $item_type: $item_name"
            return 1
        fi
    fi

    echo "  Deleting $item_type: $item_name"
    eval "$delete_command"
}
```

### 2. Find and Clean Merged Worktrees
```bash
echo ""
echo "Checking for worktrees to clean up..."

WORKTREES=$(git worktree list --porcelain 2>/dev/null | grep "^worktree" | cut -d' ' -f2)
WORKTREE_COUNT=0
PORTS_SCRIPT="${CLAUDE_PLUGIN_ROOT}/scripts/worktree-ports.sh"

for WORKTREE in $WORKTREES; do
    if [[ "$WORKTREE" == "$(git rev-parse --show-toplevel)" ]]; then
        continue
    fi

    if [[ "$WORKTREE" == *"/trees/"* ]] || [[ -d "$WORKTREE" ]]; then
        BRANCH=$(cd "$WORKTREE" 2>/dev/null && git branch --show-current || echo "")

        if [ -z "$BRANCH" ]; then
            echo "Could not determine branch for worktree: $WORKTREE"
            continue
        fi

        if is_branch_merged "$BRANCH"; then
            echo "Found merged worktree: $WORKTREE (branch: $BRANCH)"

            # Release port slot before removing worktree
            if [ -f "$PORTS_SCRIPT" ] && [ -f ".worktree.json" ]; then
                "$PORTS_SCRIPT" release "$BRANCH" 2>/dev/null || true
                echo "  Released port slot for $BRANCH"
            fi

            if safe_delete "worktree" "$WORKTREE" "git worktree remove '$WORKTREE' --force"; then
                ((WORKTREE_COUNT++))
            fi
        else
            echo "Keeping worktree: $WORKTREE (branch: $BRANCH - not merged)"
        fi
    fi
done

if [ $WORKTREE_COUNT -eq 0 ]; then
    echo "No merged worktrees to clean up"
else
    echo "Cleaned up $WORKTREE_COUNT worktree(s)"
fi
```

### 3. Clean Merged Local Branches
```bash
echo ""
echo "Checking for merged local branches..."

LOCAL_BRANCHES=$(git branch | sed 's/^[* +]*//' | grep -vE "^($MAIN_BRANCH)$" || true)
BRANCH_COUNT=0

if [ -n "$LOCAL_BRANCHES" ]; then
    while IFS= read -r BRANCH; do
        BRANCH=$(echo "$BRANCH" | xargs)
        [ -z "$BRANCH" ] && continue

        if is_branch_merged "$BRANCH"; then
            echo "Found merged branch: $BRANCH"
            if safe_delete "local branch" "$BRANCH" "git branch -D '$BRANCH' 2>/dev/null"; then
                ((BRANCH_COUNT++))
            fi
        else
            echo "Keeping branch: $BRANCH (not merged)"
        fi
    done <<< "$LOCAL_BRANCHES"
fi

if [ $BRANCH_COUNT -eq 0 ]; then
    echo "No merged local branches to clean up"
else
    echo "Cleaned up $BRANCH_COUNT local branch(es)"
fi
```

### 4. Clean Merged Remote Branches
```bash
echo ""
echo "Checking for merged remote branches..."

REMOTE_BRANCHES=$(git branch -r | sed 's/^[[:space:]*+]*//' | grep -v HEAD | grep -vE "^origin/($MAIN_BRANCH|master|main)$" || true)
REMOTE_COUNT=0

if [ -n "$REMOTE_BRANCHES" ]; then
    while IFS= read -r BRANCH; do
        BRANCH=$(echo "$BRANCH" | xargs)
        [ -z "$BRANCH" ] && continue
        BRANCH_NAME=${BRANCH#origin/}

        if echo "$PROTECTED_BRANCHES" | grep -qw "$BRANCH_NAME"; then
            continue
        fi

        if is_branch_merged "$BRANCH"; then
            echo "Found merged remote branch: $BRANCH"
            if safe_delete "remote branch" "$BRANCH" "git push origin --delete '$BRANCH_NAME' 2>/dev/null"; then
                ((REMOTE_COUNT++))
            fi
        fi
    done <<< "$REMOTE_BRANCHES"
fi

if [ $REMOTE_COUNT -eq 0 ]; then
    echo "No merged remote branches to clean up"
else
    echo "Cleaned up $REMOTE_COUNT remote branch(es)"
fi
```

### 5. Clean Branch Databases
```bash
echo ""
echo "Checking for branch databases to clean up..."

detect_main_database() {
    for env_file in ".env" ".env.local" ".env.development" "backend/.env" "app/.env" "api/.env"; do
        if [ -f "$env_file" ]; then
            local db_url=$(grep -E "^DATABASE_URL=" "$env_file" 2>/dev/null | head -1)
            if [ -n "$db_url" ]; then
                local db_name=$(echo "$db_url" | sed -E 's|.*://[^/]*/([^?#"\s]*).*|\1|' | sed 's|"||g' | xargs)
                if [ -n "$db_name" ] && [ "$db_name" != "DATABASE_URL" ]; then
                    echo "$db_name"
                    return 0
                fi
            fi

            local db_name=$(grep -E "^(DB_NAME|DATABASE_NAME|POSTGRES_DB)=" "$env_file" 2>/dev/null | head -1 | cut -d'=' -f2 | sed 's|"||g' | xargs)
            if [ -n "$db_name" ]; then
                echo "$db_name"
                return 0
            fi
        fi
    done
    return 1
}

if command -v psql &> /dev/null; then
    MAIN_DB_NAME=$(detect_main_database || true)
    DB_COUNT=0

    if [ -n "$MAIN_DB_NAME" ]; then
        echo "Detected main database: $MAIN_DB_NAME"

        BRANCH_DBS=$(PGPASSWORD="${PGPASSWORD:-postgres}" psql -U "${PGUSER:-postgres}" -h "${PGHOST:-localhost}" -p "${PGPORT:-5432}" -lqt 2>/dev/null |
                     cut -d \| -f 1 | xargs | tr ' ' '\n' |
                     grep -E "^${MAIN_DB_NAME}_" | xargs)

        if [ -n "$BRANCH_DBS" ]; then
            for DB in $BRANCH_DBS; do
                BRANCH_FROM_DB=$(echo "$DB" | sed "s/^${MAIN_DB_NAME}_//")

                if ! git branch -a 2>/dev/null | grep -qE "(^|/)${BRANCH_FROM_DB}$"; then
                    echo "Database $DB (branch: $BRANCH_FROM_DB no longer exists)"

                    DELETE_CMD="PGPASSWORD='${PGPASSWORD:-postgres}' dropdb -U '${PGUSER:-postgres}' -h '${PGHOST:-localhost}' -p '${PGPORT:-5432}' '$DB' 2>/dev/null"

                    if safe_delete "database" "$DB" "$DELETE_CMD"; then
                        ((DB_COUNT++))
                    fi
                else
                    echo "Keeping database $DB (branch still exists)"
                fi
            done
        else
            echo "No branch databases found"
        fi

        if [ $DB_COUNT -gt 0 ]; then
            echo "Cleaned up $DB_COUNT database(s)"
        fi
    else
        echo "Could not detect main database - skipping database cleanup"
    fi
else
    echo "PostgreSQL client not found - skipping database cleanup"
fi
```

### 6. Prune and GC
```bash
echo ""
echo "Pruning remote tracking branches..."
git remote prune origin
echo "Pruned remote tracking references"

echo ""
echo "Running git garbage collection..."
git gc --auto
```

### 7. Summary
```bash
echo ""
echo "Git cleanup completed!"

if [[ "$DRY_RUN" == "yes" ]]; then
    echo ""
    echo "This was a DRY RUN - no changes were made"
    echo "Run without 'dry-run' to perform actual cleanup"
fi

echo ""
echo "Remaining worktrees:"
git worktree list | sed 's/^/  /'

echo ""
echo "Remaining local branches:"
git branch | sed 's/^/  /'

echo ""
echo "Recovery: git reflog | grep <branch-name>"
```

## Usage Examples
```bash
# Preview what would be cleaned
/vandra-dev:cmd-git-cleanup dry-run

# Run cleanup with confirmations
/vandra-dev:cmd-git-cleanup

# Run cleanup without confirmations
/vandra-dev:cmd-git-cleanup no no
```

## Options
- **First argument**: `dry-run` or `--dry-run` to preview without making changes
- **Second argument**: `no` to skip interactive confirmations

## Important Notes
- Fetches and updates main branch before checking merge status
- Detects PR merges (squash, rebase, merge commit)
- Protects important branches (main, master, develop, staging, production)
- Releases port slots before removing worktrees
- Safely handles database cleanup with multiple detection methods
