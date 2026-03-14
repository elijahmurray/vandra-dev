---
description: Scan project to auto-generate .worktree.json for worktree port management
disable-model-invocation: true
---

# Worktree Setup

Scan the current project to generate a `.worktree.json` configuration file for managing ports across git worktrees.

## Steps

1. **Scan for services** in the project root:
   - Look for `package.json` files (check `scripts.start`/`scripts.dev` for port flags like `--port`, `-p`)
   - Look for `requirements.txt`, `pyproject.toml` (Python projects)
   - Look for `docker-compose.yml` / `docker-compose.yaml` (extract port mappings)
   - Look for `Procfile` (process definitions)
   - Look for `go.mod`, `Cargo.toml`

2. **Detect frameworks** from dependencies:
   - `next` → Next.js, default port 3000
   - `nuxt` → Nuxt.js, default port 3000
   - `@angular/core` → Angular, default port 4200
   - `vite` → Vite dev server, default port 5173
   - `react-scripts` → CRA, default port 3000
   - `express` / `fastify` → Node API, default port 3000
   - `django` → Django, default port 8000
   - `flask` → Flask, default port 5000
   - `fastapi` / `uvicorn` → FastAPI, default port 8000
   - `rails` → Rails, default port 3000
   - `gin` / `echo` / `fiber` → Go web, default port 8080

3. **Scan .env files** for port variables:
   - Find all `.env*` files up to 3 levels deep
   - Extract variables containing "PORT" in name
   - Note current values as base ports

4. **Parse docker-compose.yml** if present:
   - Extract service names and port mappings
   - Use host port as basePort

5. **Detect database**:
   - Look for DATABASE_URL in .env files → postgres
   - Look for docker-compose services named postgres/mysql/redis
   - Set database type and envVar

6. **Generate `.worktree.json`**:
   Build the config with detected services, showing the user what was found:
   ```json
   {
     "services": [...detected services...],
     "database": { "type": "detected_type", "envVar": "DATABASE_URL" },
     "tabFormat": "{type}: {name} ({ports})"
   }
   ```

7. **Present to user** for review and confirmation.

8. **Write** `.worktree.json` to project root.

9. **Suggest** adding `.worktree.json` to version control so the team benefits.
