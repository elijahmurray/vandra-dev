# tab-rename

Rename the current terminal tab based on the worktree branch and ports.

## Instructions

Run the tab rename script to set the terminal tab title based on the current worktree context:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/worktree-tab-set.sh
```

This auto-detects the branch name, type, and port slot, then renames the tab accordingly (e.g., "Feature: RAI 552 Value Creation Agent (3001/8001)").

Works in iTerm2. Does not work in Warp (Warp doesn't support programmatic tab renaming).
