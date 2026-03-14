# vandra-dev

A Claude Code plugin for opinionated development workflows with git worktree management, port isolation, issue tracking, and PR workflows.

## Install

```bash
# From marketplace (when published)
claude plugin install vandra-dev

# Local development
claude --plugin-dir ./vandra-dev
```

## Features

### Git Worktree Management
Create isolated worktrees with automatic port assignment, database cloning, dependency installation, and terminal tab renaming.

```
/vandra-dev:cmd-worktree-create feature login-page
```

Each worktree gets:
- Its own port slot (frontend=3001, api=8001 for slot 1)
- An isolated database clone
- Python venvs and Node dependencies
- A renamed terminal tab: "Feature: Login Page (3001/8001)"

### Port Isolation

Configure your project's port topology in `.worktree.json`:

```json
{
  "services": [
    { "name": "frontend", "directory": "frontend", "basePort": 3000, "envVar": "PORT", "envFile": "frontend/.env.local" },
    { "name": "api", "directory": "backend", "basePort": 8000, "envVar": "API_PORT", "envFile": "backend/.env" }
  ],
  "database": { "type": "postgres", "envVar": "DATABASE_URL" },
  "tabFormat": "{type}: {name} ({ports})"
}
```

First-time setup: run `/vandra-dev:cmd-worktree-setup` to auto-detect your services.

### Issue & PR Workflow
- `/vandra-dev:cmd-issue-start` — Start work on a ticket (TDD approach)
- `/vandra-dev:cmd-issue-create` — Create a ticket in your tracker
- `/vandra-dev:cmd-issue-complete` — Clean up after merge
- `/vandra-dev:cmd-pr-create` — Create a pull request
- `/vandra-dev:cmd-pr-review` — Review and implement feedback
- `/vandra-dev:cmd-pr-finalize` — Final checks before merge
- `/vandra-dev:cmd-commit` — Conventional commit formatting

### Development Tools
- `/vandra-dev:cmd-feature-document` — Document features before PR
- `/vandra-dev:cmd-git-cleanup` — Clean up merged branches, worktrees, databases
- `/vandra-dev:cmd-mcp-install` — Install MCP servers
- `/vandra-dev:cmd-setup-ticket-system` — Configure issue tracker (GitHub, Linear, Jira, GitLab)

### Prompts
- `refactor` — Code refactoring guidance
- `test-suite` — Test creation and improvement
- `optimize` — Performance optimization

## Port Slot System

Each worktree gets a slot number. Ports offset from base:

```
Slot 0 (main):           frontend=3000, api=8000
Slot 1 (feature/login):  frontend=3001, api=8001
Slot 2 (spike/ai):       frontend=3002, api=8002
```

Managed automatically by the worktree scripts. Slots are tracked in `trees/.worktree-slots.json`.

## Terminal Tab Naming

Tabs are automatically renamed when creating worktrees:

- `Feature: Login Page (3001/8001)`
- `Bugfix: Header Overflow (3002/8002)`
- `Spike: AI Architecture (N/A)`

Works with iTerm2, Terminal.app, Warp, and most ANSI-compatible terminals.

Format is configurable via `tabFormat` in `.worktree.json`.

## Notifications

Desktop notifications fire automatically on:
- Claude session completion
- When Claude needs your attention

Uses `terminal-notifier` (macOS) with `osascript` fallback.

## Development Workflow

1. **Start**: `/vandra-dev:cmd-issue-start` — Begin work on a ticket
2. **Worktree**: `/vandra-dev:cmd-worktree-create feature my-feature` — Isolated environment
3. **Develop**: Write tests first (TDD), implement, commit regularly
4. **Document**: `/vandra-dev:cmd-feature-document` — Spec + changelog
5. **PR**: `/vandra-dev:cmd-pr-create` — Create pull request
6. **Cleanup**: `/vandra-dev:cmd-issue-complete` — Remove worktree, database, port slot

## Contributing

```bash
# Clone the repo
git clone https://github.com/elijahmurray/vandra-dev.git

# Test locally
claude --plugin-dir ./vandra-dev

# Reload after changes
/reload-plugins
```
