# worktree-create

Create a new Git worktree for parallel feature development with port isolation and terminal tab renaming.

## Variables
- BRANCH_TYPE: The type (feature, bugfix, hotfix, spike)
- BRANCH_NAME: The name of your feature

## Instructions

### Pre-flight: Check for .worktree.json

Before creating the worktree, check if `.worktree.json` exists in the project root.

If it does NOT exist, ask the user:

> No `.worktree.json` found. Would you like to set up port management for worktrees?
> This scans your project to detect services and configure isolated ports per worktree.
> **[Yes / No / Skip permanently]**

- If **Yes**: Run the `/vandra-dev:cmd-worktree-setup` command first, then continue.
- If **Skip permanently**: Create `.worktree.json` with `{"services": [], "tabFormat": "{type}: {name}"}` and continue.
- If **No**: Continue without port management for this worktree only.

### Create the Worktree

Run the automated worktree setup script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh ${BRANCH_TYPE:-"feature"} ${BRANCH_NAME}
```

The script is pre-approved in plugin settings and will run without bash command approvals.

## What the Script Does

1. **Creates the worktree** in `trees/${BRANCH_NAME}` directory
2. **Assigns a port slot** if `.worktree.json` exists (slot 0 = main, slot 1+ = worktrees)
3. **Copies environment files** (.env, frontend/.env.local, etc.)
4. **Rewrites ports** in .env files based on slot offset (e.g., 3000 → 3001 for slot 1)
5. **Installs dependencies**:
   - **Python**: Detects `requirements.txt` in root, backend/, api/, server/, app/, src/
   - **Node.js**: Installs from package.json in root or frontend/
6. **Clones database** for isolated development (PostgreSQL)
7. **Updates environment variables** to point to branch database
8. **Renames terminal tab** to show feature name and ports (e.g., "Feature: Login (3001/8001)")
9. **Sends desktop notification** when complete

## Port Slot System

Each worktree gets a unique slot number. Ports are offset from base:

```
Slot 0 (main):           frontend=3000, api=8000
Slot 1 (feature/login):  frontend=3001, api=8001
Slot 2 (spike/ai):       frontend=3002, api=8002
```

Port assignments are tracked in `trees/.worktree-slots.json`.

## Next Steps

After creating a worktree:

1. **Switch to the worktree** (follow the instructions displayed by the script)
2. **Start a new Claude session**: `claude code`
3. **Start development**: `/vandra-dev:cmd-issue-start` or begin writing tests
4. **Run services** on the assigned ports (check your .env files for the updated values)

When complete:
1. `/vandra-dev:cmd-feature-document` to create spec and documentation
2. `/vandra-dev:cmd-pr-create` to create the pull request
3. `/vandra-dev:cmd-issue-complete` to clean up worktree, ports, and database

## Common Project Structures Supported

```
# Full-stack with backend subdirectory
project/
├── backend/requirements.txt → Creates backend/venv/
├── frontend/package.json    → Runs npm install
├── .env                     → Copied with port offsets
└── .worktree.json           → Port config

# Root-level Python project
project/
├── requirements.txt         → Creates venv/
├── app/
└── .env                     → Copied with port offsets

# Microservices structure
project/
├── api/requirements.txt     → Creates api/venv/
├── server/requirements.txt  → Creates server/venv/
├── frontend/package.json    → Runs npm install
└── .worktree.json           → Multi-service port config
```
