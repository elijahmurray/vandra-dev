---
description: "Rebase current branch onto main, resolve conflicts, and evaluate whether our branch should be updated based on incoming changes. Triggers on: 'rebase', 'rebase onto main', 'pull main into this branch', 'update from main', 'merge main in', 'sync with main'."
---

When the user wants to rebase or sync their branch with main, follow this workflow.

## Step 1: Analyze incoming changes

Before rebasing, understand what's new in main:

```bash
git fetch origin main
```

Review the diff between our branch point and current main:

```bash
git log --oneline HEAD..origin/main
```

Read the commit messages and identify:
- **Related changes**: Anything touching the same areas we're working on (same files, same features, same APIs)
- **New utilities/patterns**: New helpers, components, or patterns that we could use
- **Refactors**: Renamed functions, moved files, changed APIs that affect our code
- **Unrelated changes**: Changes to completely different parts of the codebase

Summarize findings to the user in two categories:
1. **Conflicts likely** — files changed in both branches
2. **Worth reviewing** — changes that don't conflict but are related to our work

## Step 2: Rebase

```bash
git rebase origin/main
```

If conflicts occur, for each conflicting file:

1. Read the conflict markers to understand both sides
2. Resolve using the correct approach:
   - If main renamed/moved something, adopt main's naming in our changes
   - If main refactored an API we're using, update our usage
   - If both sides added to the same area (e.g. imports, config), merge both additions
   - If genuinely conflicting logic, prefer our branch's intent but using main's patterns
3. Stage the resolved file: `git add <file>`
4. Continue: `git rebase --continue`

Repeat until rebase is complete.

## Step 3: Evaluate our branch in new context

This is the critical step. After rebase is complete, review what came in from main and assess:

### Check for duplication
- Did main add something similar to what we're building? If so, should we use theirs instead of ours?
- Did main add a utility/helper that replaces code we wrote from scratch?

### Check for new patterns
- Did main introduce a new pattern (e.g. new component structure, new API pattern, new error handling) that we should adopt in our branch for consistency?
- Are there new shared components we should use instead of our custom ones?

### Check for API changes
- Did main change an API/interface that we're extending? Do we need to update our additions to match?
- Did main change database schema in a way that affects our migrations?

### Check for config/env changes
- New env variables we need?
- Changed config structure?

If any of these apply, tell the user:
- What changed in main that's relevant
- What we should consider updating in our branch
- Whether it's a quick fix or a bigger refactor

Ask the user if they want you to make the updates, then do it.

## Step 4: Verify

After any updates:

```bash
# Make sure everything builds
npm run build 2>&1 | tail -20
# Or for Python
python -m py_compile <changed-files>
```

Run any relevant tests if they exist.

## Important

- Do NOT just blindly resolve conflicts — understand the intent of both sides
- Do NOT skip Step 3 — the whole point is evaluating our work in the new context
- If main made significant related changes, take time to explain them to the user
- If you recommend refactoring our branch, explain WHY with specific references to what main added
