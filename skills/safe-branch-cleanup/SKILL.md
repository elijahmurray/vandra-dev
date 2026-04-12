---
description: "Audit-first cleanup of merged branches and worktrees with safety gates. Triggers on: 'clean up merged branches', 'prune old worktrees', 'which branches can I delete', 'clean up the repo', 'branches that have been merged'. Never trusts `git branch --merged` alone and refuses to delete dirty, locked, or recently-active worktrees."
---

Use this skill any time the user asks to clean up **multiple** branches or worktrees, or when the request is ambiguous about which items to remove ("clean up merged stuff", "prune old branches", "which can I delete"). For cleaning up a single named branch or ticket the user has explicitly confirmed is merged, a narrower tool may be more direct — fall back to this skill if there isn't one.

## Why this skill exists

`git branch --merged main` marks any branch whose tip equals main's HEAD as "merged" — including freshly-created branches with zero commits whose worktrees may contain live uncommitted work. Trusting that signal has caused data loss. This skill's script classifies every branch/worktree through a 5-check safety gate and refuses to delete anything in a `DIRTY`, `LOCKED`, `ACTIVE`, `AHEAD`, `EMPTY`, or `PROTECTED` state.

## Always-follow workflow

### Step 1 — Audit
Run the script with no arguments. It never writes anything on its own.

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/safe-branch-cleanup.sh"
```

This prints a table grouped by status:
- `SAFE` — merged, clean, not recently active → fine to delete after confirmation
- `EMPTY` — zero unique commits, tip == main HEAD → intent unknown, **ASK per item**
- `DIRTY` — uncommitted changes in worktree → **NEVER auto-delete**
- `LOCKED` — `.git/worktrees/<name>/locked` exists → skip
- `ACTIVE` — worktree modified in last 24h → skip
- `AHEAD` — has unique commits not in main → still in progress
- `PROTECTED` — main/master/staging/etc. → always skip

### Step 2 — Show the audit to the user
Relay the table as-is. Do not summarize away the `EMPTY` / `DIRTY` sections — those are the categories that cause data loss if skipped.

### Step 3 — Confirm before any deletion
Even for `SAFE` items, confirm the list before acting. For `EMPTY` branches, ask per item: "Branch X has zero commits and points at main. Is this finished, or still in use?" Do not bundle EMPTY deletions into a single yes/no.

### Step 4 — Delete only what the user confirmed

Bulk-delete everything classified SAFE:
```bash
"$CLAUDE_PLUGIN_ROOT/scripts/safe-branch-cleanup.sh" --delete-safe --yes
```

Delete one item by branch name or worktree path:
```bash
"$CLAUDE_PLUGIN_ROOT/scripts/safe-branch-cleanup.sh" --delete <branch-or-path> --yes
```

The script re-classifies right before acting and refuses anything that is no longer `SAFE`. It never passes `--force` to `git worktree remove` and uses `git branch -d` (safe delete), not `-D`.

### Step 5 — Remote branches are a separate ask
Local cleanup never touches remote. If the user also wants remote branches gone, ask explicitly, then:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/safe-branch-cleanup.sh" --delete-remote <branch> --yes
```

## Hard rules (do not break)

- Never run `git branch -D`, `git worktree remove --force`, or `rm -rf` on a worktree to satisfy a cleanup request. If the script refuses, escalate to the user — don't bypass it.
- Never batch-delete `EMPTY` branches. They are the exact failure mode this skill exists to prevent.
- Never delete remote branches in the same confirmation as local ones.
- If the user asks "clean it all up" without specifying, run the audit and show it — don't guess.

## JSON mode

For programmatic use (or when you need to reason over the output):
```bash
"$CLAUDE_PLUGIN_ROOT/scripts/safe-branch-cleanup.sh" --json
```

## Tuning the active-window

Default is 24 hours. To treat anything modified in the last 2 hours as ACTIVE:
```bash
SAFE_CLEANUP_ACTIVE_HOURS=2 "$CLAUDE_PLUGIN_ROOT/scripts/safe-branch-cleanup.sh"
```
