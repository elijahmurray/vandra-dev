# git-cleanup

Clean up merged branches, worktrees, port slots, and databases.

## Instructions

This command has been unified into `worktree-cleanup`. Run the cleanup script directly:

### Single ticket
```bash
"$CLAUDE_PLUGIN_ROOT/scripts/worktree-cleanup.sh" "<ticket-id>"
```

### All merged branches
```bash
"$CLAUDE_PLUGIN_ROOT/scripts/worktree-cleanup.sh" --all
```

### Dry run (preview)
```bash
"$CLAUDE_PLUGIN_ROOT/scripts/worktree-cleanup.sh" --all --dry-run
```

The script automatically handles: pull main, remove worktrees, release port slots, drop branch databases, delete local + remote branches, git prune + gc.
