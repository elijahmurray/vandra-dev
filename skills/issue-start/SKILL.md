---
description: Start working on a ticket or issue with TDD approach
---

When the user wants to start working on an issue, ticket, or task:

1. **Ensure there's a Linear ticket** — if the user hasn't mentioned one, ask:
   > "What's the Linear ticket for this? I can search Linear or you can give me the ID."
2. **Create a worktree** using the ticket ID in the branch name: `{type}/{TICKET-ID}-{description}`
3. Run the `/vandra-dev:cmd-issue-start` command for the TDD workflow.
