# issue-complete

Clean up after merging a ticket's PR.

## Instructions

This command has been unified into `worktree-cleanup`. Run the cleanup script directly:

### Single ticket
```bash
"$CLAUDE_PLUGIN_ROOT/scripts/worktree-cleanup.sh" "<ticket-id>"
```

Example: `"$CLAUDE_PLUGIN_ROOT/scripts/worktree-cleanup.sh" "RAI-551"`

### All merged branches
```bash
"$CLAUDE_PLUGIN_ROOT/scripts/worktree-cleanup.sh" --all
```

The script automatically handles: pull main, remove worktree, release port slot, drop branch database, delete local + remote branches.
