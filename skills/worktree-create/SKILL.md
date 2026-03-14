---
description: Create a git worktree for parallel feature development with port isolation and terminal tab renaming
---

When the user wants to create a worktree, branch, or isolated environment for a feature/bugfix/spike:

## Before creating the worktree

Branch names must include a Linear ticket ID. Before running the worktree command, ensure you have a ticket:

1. **If the user already mentioned a ticket ID** (e.g., "RAI-270", "work on RAI-270") — use it directly.
2. **If a ticket was just created** in the current conversation via the pm-linear skill — use that ticket ID.
3. **If no ticket is obvious** — ask the user:
   > "I don't see a Linear ticket for this. Want me to search Linear for an existing one, or can you give me the ticket ID?"

   Give them options:
   - Provide a ticket ID directly
   - Search Linear for a matching ticket
   - Create a new ticket first (via the pm-linear skill)

## Branch naming format

Once you have the ticket ID, construct the branch name as:

```
{type}/{TICKET-ID}-{description}
```

Examples:
- `feature/RAI-270-sourcing-agent`
- `bugfix/RAI-301-auth-redirect`
- `spike/RAI-155-ai-architecture`

The `{description}` part comes from the ticket title or user's description, kebab-cased.

## Create the worktree

Run the `/vandra-dev:cmd-worktree-create` command with the constructed branch name.
