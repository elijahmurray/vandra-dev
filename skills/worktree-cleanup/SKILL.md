---
description: "Clean up a merged ticket or all merged branches — removes worktree, releases port slot, deletes branch, drops database. Triggers on: 'RAI-551 is merged', 'clean up RAI-557', 'that branch is merged', '551 is done', 'merged in RAI-560', 'clean up all merged branches', 'pull main and clean up'."
---

When the user indicates a ticket is merged or wants cleanup, run the worktree-cleanup script.

## Single ticket cleanup

If the user mentions a specific ticket ID (e.g. "RAI-551 is merged", "clean up 557", "551 is done"):

1. Extract the ticket identifier from their message
2. Run the cleanup script:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/worktree-cleanup.sh" "<ticket-id>"
```

For example: `"$CLAUDE_PLUGIN_ROOT/scripts/worktree-cleanup.sh" "RAI-551"`

The script will automatically:
- Pull latest main
- Find the worktree matching the ticket ID
- Remove the worktree (with fallback to rm + prune)
- Release the port slot from `.worktree-slots.json`
- Drop the branch database
- Delete local and remote branches

## Bulk cleanup

If the user says "clean up all merged branches" or similar:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/worktree-cleanup.sh" --all
```

## Dry run

To preview what would be cleaned without making changes:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/worktree-cleanup.sh" "<ticket-id>" --dry-run
"$CLAUDE_PLUGIN_ROOT/scripts/worktree-cleanup.sh" --all --dry-run
```

## Important

- Do NOT ask for confirmation — the user already indicated intent
- Do NOT run in interactive mode
- Report what was cleaned up after the script finishes
- If the user says "pull main" along with cleanup, the script handles that automatically
