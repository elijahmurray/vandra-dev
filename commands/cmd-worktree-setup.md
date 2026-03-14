# worktree-setup

Set up `.worktree.json` for port management across git worktrees.

## Instructions

Scan the current project to auto-detect services, ports, and database configuration, then generate a `.worktree.json` file.

### Step 1: Scan for Services

Search the project for:

- **package.json** files: Check `scripts.start` / `scripts.dev` for port flags (`--port`, `-p`, `PORT=`)
- **requirements.txt** / **pyproject.toml**: Python project indicators
- **docker-compose.yml** / **docker-compose.yaml**: Extract service names and port mappings
- **Procfile**: Process definitions with port assignments
- **go.mod**, **Cargo.toml**: Go/Rust project indicators

### Step 2: Detect Frameworks and Default Ports

From dependencies in package.json or pyproject.toml:

| Framework | Default Port |
|-----------|-------------|
| Next.js (`next`) | 3000 |
| Nuxt.js (`nuxt`) | 3000 |
| Angular (`@angular/core`) | 4200 |
| Vite (`vite`) | 5173 |
| Create React App (`react-scripts`) | 3000 |
| Express / Fastify | 3000 |
| Django | 8000 |
| Flask | 5000 |
| FastAPI / Uvicorn | 8000 |
| Rails | 3000 |
| Go web (gin/echo/fiber) | 8080 |

### Step 3: Scan .env Files

- Find all `.env*` files up to 3 levels deep
- Extract variables containing "PORT" in the name
- Note current values as base ports
- Identify which env file each service uses

### Step 4: Parse docker-compose.yml

If present, extract:
- Service names
- Port mappings (host:container) — use host port as basePort
- Database services (postgres, mysql, redis)

### Step 5: Detect Database

- Look for `DATABASE_URL` in .env files → postgres
- Check docker-compose for postgres/mysql services
- Set database type and envVar

### Step 5b: Detect Cross-Service Dependencies

Look for env vars in one service that reference another service's port:

- `BACKEND_PORT`, `API_PORT` in frontend env files → references backend service
- `NEXT_PUBLIC_BACKEND_URL`, `NEXT_PUBLIC_API_URL` → URL templates referencing backend
- `FRONTEND_URL`, `CORS_ORIGINS` in backend env files → references frontend service

For each found, create a `crossServiceRewrites` entry.

### Step 6: Generate Config

Build a `.worktree.json` and present it to the user:

```json
{
  "services": [
    {
      "name": "<detected_name>",
      "directory": "<detected_dir>",
      "basePort": <detected_port>,
      "envVar": "<detected_var>",
      "envFile": "<detected_file>"
    }
  ],
  "crossServiceRewrites": [
    {
      "file": "<env_file_path>",
      "var": "<env_var_name>",
      "sourceService": "<service_name>",
      "template": "http://localhost:{<service_name>_port}"
    }
  ],
  "database": {
    "type": "<postgres|mysql|sqlite|none>",
    "envVar": "DATABASE_URL"
  },
  "tabFormat": "{type}: {name} ({ports})"
}
```

**crossServiceRewrites** entries:
- `file`: The env file to write to
- `var`: The env variable name to set
- `sourceService`: Which service's port to reference (must match a service `name`)
- `template` (optional): URL template with `{service_port}` placeholder. If omitted, the raw port number is written.

Examples:
- `{"file": "frontend/.env.local", "var": "BACKEND_PORT", "sourceService": "backend"}` → writes `BACKEND_PORT=8001`
- `{"file": "frontend/.env.local", "var": "NEXT_PUBLIC_BACKEND_URL", "sourceService": "backend", "template": "http://localhost:{backend_port}"}` → writes `NEXT_PUBLIC_BACKEND_URL=http://localhost:8001`

Show the user what was detected and ask for confirmation. Let them adjust services, ports, or env var names before writing.

### Step 7: Write and Commit

Write `.worktree.json` to the project root. Suggest adding it to version control so the whole team benefits.
