# issue-complete.md

Clean up after merging an issue's PR (worktree removal, branch deletion).

## Variables
- BRANCH_NAME: The name of the feature branch (optional, will detect current if not provided)

## Instructions

This command handles post-merge cleanup:

### 1. Verify Merge Status
```bash
# Check current location
CURRENT_DIR=$(pwd)
CURRENT_BRANCH=$(git branch --show-current)

# Determine the feature branch
if [ -z "$BRANCH_NAME" ]; then
    if [[ "$CURRENT_DIR" == *"/trees/"* ]]; then
        # We're in a worktree
        FEATURE_BRANCH="$CURRENT_BRANCH"
        echo "📍 In worktree for branch: $FEATURE_BRANCH"
    else
        # We're in main repo, need branch name
        echo "❌ Please provide the feature branch name"
        exit 1
    fi
else
    FEATURE_BRANCH="$BRANCH_NAME"
fi

# Verify the branch has been merged
cd $(git rev-parse --show-toplevel)  # Go to main repo
git checkout main
git pull origin main 2>/dev/null || echo "No remote configured"

if ! git branch --merged main | grep -q "$FEATURE_BRANCH"; then
    echo "❌ Branch $FEATURE_BRANCH has not been merged into main yet"
    echo "Please merge the PR/branch first before completing the issue"
    exit 1
fi

echo "✅ Branch $FEATURE_BRANCH has been merged into main"
```

### 2. Release Port Slot
If the project uses port management (`.worktree.json` exists), release the port slot:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/worktree-ports.sh release "${BRANCH_NAME}"
```

### 3. Clean Up Worktree (if exists)
```bash
# Check if worktree exists
WORKTREE_PATH=$(git worktree list | grep "$FEATURE_BRANCH" | awk '{print $1}')

if [ -n "$WORKTREE_PATH" ]; then
    echo "🧹 Removing worktree at: $WORKTREE_PATH"
    git worktree remove "$WORKTREE_PATH" --force
    echo "✅ Worktree removed"
fi
```

### 4. Clean Up Branch Database
```bash
echo "🗄️  Checking for branch-specific database..."

if command -v psql &> /dev/null; then
    # Try to detect main database name
    MAIN_DB_NAME=""

    # Check common env files for database name
    for env_file in ".env" "backend/.env" "frontend/.env.local"; do
        if [ -f "$env_file" ]; then
            # Look for DATABASE_URL or DB_NAME patterns
            DB_FROM_URL=$(grep -E "^DATABASE_URL=" "$env_file" 2>/dev/null | head -1 | sed -E 's|.*://[^/]*/([^?]*)\??.*|\1|')
            DB_FROM_NAME=$(grep -E "^DB_NAME=" "$env_file" 2>/dev/null | head -1 | cut -d'=' -f2)

            if [ -n "$DB_FROM_URL" ]; then
                MAIN_DB_NAME="$DB_FROM_URL"
                break
            elif [ -n "$DB_FROM_NAME" ]; then
                MAIN_DB_NAME="$DB_FROM_NAME"
                break
            fi
        fi
    done

    if [ -n "$MAIN_DB_NAME" ]; then
        # Check for branch-specific database
        BRANCH_DB_NAME="${MAIN_DB_NAME}_${FEATURE_BRANCH}"

        if PGPASSWORD=postgres psql -U postgres -h localhost -p 5432 -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$BRANCH_DB_NAME"; then
            echo "🗑️  Found branch database: $BRANCH_DB_NAME"
            read -p "Drop database $BRANCH_DB_NAME? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if PGPASSWORD=postgres dropdb -U postgres -h localhost -p 5432 "$BRANCH_DB_NAME" 2>/dev/null; then
                    echo "✅ Dropped database $BRANCH_DB_NAME"
                else
                    echo "❌ Failed to drop database $BRANCH_DB_NAME"
                fi
            else
                echo "⏭️  Skipped database cleanup"
            fi
        else
            echo "ℹ️  No branch-specific database found"
        fi
    else
        echo "⚠️  Could not detect main database name - skipping database cleanup"
    fi
else
    echo "⚠️  PostgreSQL client not found - skipping database cleanup"
fi
```

### 5. Delete Feature Branch
```bash
# Delete the local branch
git branch -d "$FEATURE_BRANCH" 2>/dev/null || git branch -D "$FEATURE_BRANCH"
echo "✅ Deleted local branch: $FEATURE_BRANCH"

# Delete remote branch if it exists
git push origin --delete "$FEATURE_BRANCH" 2>/dev/null || echo "No remote branch to delete"
```

### 6. Final Summary
```bash
echo ""
echo "🎉 Issue cleanup completed!"
echo ""
echo "✅ Port slot released (if applicable)"
echo "✅ Worktree removed (if existed)"
echo "✅ Branch database cleaned (if existed)"
echo "✅ Feature branch deleted"
echo ""
echo "📍 You are now on: $(git branch --show-current)"
echo "🚀 Ready for the next issue!"
echo ""
echo "💡 Claude session can be safely closed - all work is complete!"
```

## Next Steps

After completing an issue, you have several options:

1. **Start a New Issue**:
   - Find or create a new issue to work on
   - Run `/cmd-issue-start` with the new issue details

2. **Review Other Work**:
   - Check other PRs that need review: `/cmd-pr-review`
   - Look at existing worktrees: `git worktree list`

3. **Update Project Status**:
   - Push changes if using remote: `git push origin main`
   - Update project board or issue tracker
   - Close the completed issue

4. **Take a Break**:
   - You've completed a full development cycle!
   - All artifacts are properly documented and cleaned up
   - The codebase is ready for the next feature

## Purpose
This command cleans up after a merged issue:
- Ensures the feature is properly merged
- Releases port slots used by the worktree
- Removes the worktree (if it exists)
- Cleans up branch-specific database
- Deletes local and remote feature branches
- Provides a clean slate for the next issue

## Usage Examples
```bash
# From within a worktree
/cmd-issue-complete

# From main repo with branch name
/cmd-issue-complete feature/add-authentication

# After merging a PR
/cmd-issue-complete feature/google-calendar-crud
```
