# terminal-setup

Configure the user's terminal for persistent worktree tab titles.

## Instructions

This is a one-time setup that configures the user's shell so worktree tab names persist even while Claude Code is running.

### Step 1: Check current status

Run the check script:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/terminal-setup.sh" check
```

This checks for:
- `DISABLE_AUTO_TITLE="true"` in zshrc (prevents oh-my-zsh from overriding titles)
- `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` env var (prevents Claude Code from overriding titles)
- `tt()` shell function (sets persistent tab title)
- precmd hook (enforces title across commands)
- iTerm2 settings guidance

### Step 2: If issues found, offer to apply

If any checks fail, ask the user if they'd like to auto-patch their shell config:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/terminal-setup.sh" apply
```

This will:
1. Add `DISABLE_AUTO_TITLE="true"` before oh-my-zsh sourcing (zsh only)
2. Add `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` export
3. Add `tt()` function and precmd/preexec hooks
4. Save a flag at `~/.claude/.terminal-setup-complete`

### Step 3: Manual iTerm2 steps

After patching, remind the user to check iTerm2 settings:
- **Profile > General > Title**: Select "Session Name" only
- **Uncheck "Job Name"** (this shows process names like "node" and overrides custom titles)
- **"Applications in terminal may change the title"** should be checked

### Step 4: Verify

After the user sources their shell config or opens a new tab:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/terminal-setup.sh" check
```

All checks should pass. The user can test with `tt "Test Title"` in a terminal tab.
