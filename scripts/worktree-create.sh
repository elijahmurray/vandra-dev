#!/bin/bash

# worktree-create.sh
# Automated worktree creation with port isolation and terminal tab renaming

set -e

# Resolve plugin root (for accessing sibling scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"

# Function to find project root (directory containing .git)
# Prefers .git directory (main repo) over .git file (worktree) so that
# running from inside a worktree still resolves to the actual project root.
find_project_root() {
    local current_dir="$(pwd)"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            echo "$current_dir"
            return
        fi
        current_dir="$(dirname "$current_dir")"
    done
    # Fallback: look for .git file (standalone worktree not under main repo)
    current_dir="$(pwd)"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/.git" ]]; then
            echo "$current_dir"
            return
        fi
        current_dir="$(dirname "$current_dir")"
    done
    echo "Error: Not in a git repository" >&2
    exit 1
}

# Get project root and change to it
PROJECT_ROOT=$(find_project_root)
cd "$PROJECT_ROOT"
echo "Working from project root: $PROJECT_ROOT"

# Get parameters
BRANCH_TYPE=${1:-"feature"}
BRANCH_NAME=${2:-""}

if [ -z "$BRANCH_NAME" ]; then
    echo "Error: Branch name is required"
    echo "Usage: worktree-create.sh [branch-type] <branch-name>"
    echo "Example: worktree-create.sh feature my-new-feature"
    exit 1
fi

echo "Creating worktree for $BRANCH_TYPE/$BRANCH_NAME..."

# Create trees directory if it doesn't exist
mkdir -p trees

# Create worktree
git worktree add trees/${BRANCH_NAME} -b ${BRANCH_TYPE}/${BRANCH_NAME}

# Go there
cd trees/${BRANCH_NAME}

echo "Setting up worktree environment..."

# ============================================================================
# PORT SLOT ASSIGNMENT
# ============================================================================
SLOT=""
PORTS_SCRIPT="$SCRIPT_DIR/worktree-ports.sh"
WORKTREE_CONFIG="$PROJECT_ROOT/.worktree.json"

if [ -f "$WORKTREE_CONFIG" ] && [ -f "$PORTS_SCRIPT" ]; then
    echo "Assigning port slot..."
    SLOT=$("$PORTS_SCRIPT" assign "${BRANCH_TYPE}/${BRANCH_NAME}")
    echo "Port slot assigned: $SLOT"
fi

# ============================================================================
# COPY ENVIRONMENT FILES
# ============================================================================
echo "Copying environment configuration files..."

# Find and copy all .env* files from the project root, maintaining directory structure
# Note: We copy real .env files (not .env.example) from the main worktree, which has
# actual credentials/config. The git checkout may have placeholder .env.example files
# but we always want the real values from the main worktree.
echo "Discovering environment files..."
env_files_found=0

while IFS= read -r env_file; do
    rel_path="${env_file#$PROJECT_ROOT/}"
    target_dir="$(dirname "$rel_path")"

    if [ "$target_dir" != "." ]; then
        mkdir -p "$target_dir"
    fi

    cp "$env_file" "$rel_path"
    echo "  Copied $rel_path"
    env_files_found=$((env_files_found + 1))
done < <(find "$PROJECT_ROOT" -type f \( -name ".env*" -o -name "*.env" \) \
    ! -name "*.example" \
    ! -path "*/node_modules/*" \
    ! -path "*/.git/*" \
    ! -path "*/trees/*" \
    ! -path "*/venv/*" \
    ! -path "*/__pycache__/*" \
    ! -path "*/dist/*" \
    ! -path "*/build/*")

# If no real .env files found, fall back to .env.example templates
if [ $env_files_found -eq 0 ]; then
    echo "No .env files found, looking for .env.example templates..."
    while IFS= read -r example_file; do
        rel_path="${example_file#$PROJECT_ROOT/}"
        target_path="${rel_path%.example}"
        target_dir="$(dirname "$target_path")"

        if [ "$target_dir" != "." ]; then
            mkdir -p "$target_dir"
        fi

        cp "$example_file" "$target_path"
        echo "  Copied $rel_path as $target_path - configure as needed"
    done < <(find "$PROJECT_ROOT" -type f -name ".env.example" \
        ! -path "*/node_modules/*" \
        ! -path "*/.git/*" \
        ! -path "*/trees/*")
fi

# Copy other configuration files (credentials, secrets, local configs)
echo "Looking for additional configuration files..."
find "$PROJECT_ROOT" -maxdepth 3 -type f \( \
    -name "*credentials*.json" -o \
    -name "*secret*" -o \
    -name "*config.local*" -o \
    -name "*.key" -o \
    -name "*.pem" \) \
    ! -path "*/node_modules/*" \
    ! -path "*/.git/*" \
    ! -path "*/trees/*" \
    ! -path "*/venv/*" | while read -r config_file; do

    rel_path="${config_file#$PROJECT_ROOT/}"
    target_dir="$(dirname "$rel_path")"

    if [ "$target_dir" != "." ]; then
        mkdir -p "$target_dir"
    fi

    cp "$config_file" "$rel_path"
    echo "  Copied config: $rel_path"
done

# Copy frontend lib directory for auth and utilities
if [ -d "$PROJECT_ROOT/frontend/lib" ]; then
    mkdir -p frontend
    cp -r "$PROJECT_ROOT/frontend/lib" frontend/
    echo "  Copied frontend/lib directory"
fi

# ============================================================================
# PORT REWRITING IN ENV FILES
# ============================================================================
if [ -n "$SLOT" ] && [ "$SLOT" -gt 0 ] 2>/dev/null && [ -f "$WORKTREE_CONFIG" ] && [ -f "$PORTS_SCRIPT" ]; then
    echo "Rewriting ports for slot $SLOT..."

    # Parse .worktree.json services and rewrite env files
    if command -v jq >/dev/null 2>&1; then
        service_count=$(jq '.services | length' "$WORKTREE_CONFIG" 2>/dev/null || echo "0")
        for i in $(seq 0 $((service_count - 1))); do
            svc_name=$(jq -r ".services[$i].name" "$WORKTREE_CONFIG")
            svc_envFile=$(jq -r ".services[$i].envFile // empty" "$WORKTREE_CONFIG")
            svc_envVar=$(jq -r ".services[$i].envVar // empty" "$WORKTREE_CONFIG")
            svc_basePort=$(jq -r ".services[$i].basePort" "$WORKTREE_CONFIG")

            if [ -n "$svc_envFile" ] && [ -n "$svc_envVar" ] && [ -f "$svc_envFile" ]; then
                "$PORTS_SCRIPT" rewrite "$svc_envFile" "$svc_envVar" "$svc_basePort" "$SLOT"
                new_port=$((svc_basePort + SLOT))
                echo "  $svc_name: $svc_basePort -> $new_port ($svc_envFile)"
            fi
        done
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json, subprocess, sys
with open('$WORKTREE_CONFIG') as f:
    config = json.load(f)
for svc in config.get('services', []):
    env_file = svc.get('envFile', '')
    env_var = svc.get('envVar', '')
    base_port = svc.get('basePort', 0)
    name = svc.get('name', '')
    if env_file and env_var:
        import os
        if os.path.isfile(env_file):
            subprocess.run(['$PORTS_SCRIPT', 'rewrite', env_file, env_var, str(base_port), '$SLOT'])
            new_port = base_port + $SLOT
            print(f'  {name}: {base_port} -> {new_port} ({env_file})')
"
    else
        echo "  Warning: jq or python3 required for port rewriting, skipping"
    fi
fi

# ============================================================================
# CROSS-SERVICE PORT REWRITES
# ============================================================================
# Handle crossServiceRewrites in .worktree.json — sets env vars in one service
# that reference another service's port (e.g. BACKEND_PORT in frontend/.env.local)
if [ -n "$SLOT" ] && [ "$SLOT" -gt 0 ] 2>/dev/null && [ -f "$WORKTREE_CONFIG" ]; then
    if command -v jq >/dev/null 2>&1; then
        rewrite_count=$(jq '.crossServiceRewrites // [] | length' "$WORKTREE_CONFIG" 2>/dev/null || echo "0")
        if [ "$rewrite_count" -gt 0 ]; then
            echo "Applying cross-service port rewrites..."
            for i in $(seq 0 $((rewrite_count - 1))); do
                rw_file=$(jq -r ".crossServiceRewrites[$i].file // empty" "$WORKTREE_CONFIG")
                rw_var=$(jq -r ".crossServiceRewrites[$i].var // empty" "$WORKTREE_CONFIG")
                rw_source=$(jq -r ".crossServiceRewrites[$i].sourceService // empty" "$WORKTREE_CONFIG")
                rw_template=$(jq -r ".crossServiceRewrites[$i].template // empty" "$WORKTREE_CONFIG")

                if [ -z "$rw_file" ] || [ -z "$rw_var" ]; then
                    continue
                fi

                # Resolve source service port
                source_port=""
                if [ -n "$rw_source" ]; then
                    source_base=$(jq -r --arg name "$rw_source" '.services[] | select(.name == $name) | .basePort' "$WORKTREE_CONFIG" 2>/dev/null)
                    if [ -n "$source_base" ]; then
                        source_port=$((source_base + SLOT))
                    fi
                fi

                if [ -n "$source_port" ]; then
                    # Ensure target file exists
                    if [ -f "$rw_file" ]; then
                        if [ -n "$rw_template" ]; then
                            # Template mode: replace {service_port} placeholder
                            new_value="${rw_template//\{${rw_source}_port\}/$source_port}"
                            # Update or append
                            if grep -q "^${rw_var}=" "$rw_file"; then
                                sed -i'' -e "s|^${rw_var}=.*|${rw_var}=${new_value}|" "$rw_file"
                            else
                                echo "${rw_var}=${new_value}" >> "$rw_file"
                            fi
                            echo "  ${rw_var}=${new_value} ($rw_file)"
                        else
                            # Simple port mode
                            if grep -q "^${rw_var}=" "$rw_file"; then
                                sed -i'' -e "s|^${rw_var}=.*|${rw_var}=${source_port}|" "$rw_file"
                            else
                                echo "${rw_var}=${source_port}" >> "$rw_file"
                            fi
                            echo "  ${rw_var}=${source_port} ($rw_file)"
                        fi
                    fi
                fi
            done
        fi
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json, os, re, sys

with open('$WORKTREE_CONFIG') as f:
    config = json.load(f)

slot = $SLOT
rewrites = config.get('crossServiceRewrites', [])
services = {s['name']: s for s in config.get('services', [])}

for rw in rewrites:
    rw_file = rw.get('file', '')
    rw_var = rw.get('var', '')
    source = rw.get('sourceService', '')
    template = rw.get('template', '')

    if not rw_file or not rw_var or not source:
        continue
    if source not in services:
        continue

    source_port = services[source]['basePort'] + slot

    if not os.path.isfile(rw_file):
        continue

    if template:
        new_value = template.replace('{' + source + '_port}', str(source_port))
    else:
        new_value = str(source_port)

    with open(rw_file) as f:
        lines = f.readlines()

    found = False
    for i, line in enumerate(lines):
        if line.startswith(rw_var + '='):
            lines[i] = f'{rw_var}={new_value}\n'
            found = True
            break
    if not found:
        lines.append(f'{rw_var}={new_value}\n')

    with open(rw_file, 'w') as f:
        f.writelines(lines)
    print(f'  {rw_var}={new_value} ({rw_file})')
"
    fi
fi

# ============================================================================
# PYTHON PROJECT SETUP
# ============================================================================
echo "Detecting Python projects..."

PYTHON_CMD=""
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
    echo "  Python 3 found: $(python3 --version)"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
    echo "  Python found: $(python --version)"
else
    echo "  Python not found - Python projects will need manual setup"
fi

setup_python_env() {
    local dir="$1"
    local requirements_file="$2"

    echo "Setting up Python environment in $dir..."

    if [ -z "$PYTHON_CMD" ]; then
        echo "  Python not available - skipping $dir"
        return 1
    fi

    local original_dir=$(pwd)
    cd "$dir"

    echo "  Creating virtual environment..."
    $PYTHON_CMD -m venv venv

    if [ -f "venv/bin/activate" ]; then
        source venv/bin/activate
        echo "  Virtual environment activated"

        echo "  Installing dependencies from $requirements_file..."
        $PYTHON_CMD -m pip install -r "$requirements_file"
        echo "  Python dependencies installed in $dir"

        deactivate 2>/dev/null || true
    else
        echo "  Failed to create virtual environment in $dir"
        cd "$original_dir"
        return 1
    fi

    cd "$original_dir"
    return 0
}

PYTHON_ENVS_CREATED=0
PYTHON_DIRS=("." "backend" "api" "server" "app" "src")

for dir in "${PYTHON_DIRS[@]}"; do
    requirements_path="$dir/requirements.txt"

    if [ -f "$requirements_path" ]; then
        echo "Found Python project: $requirements_path"

        if [ -z "$PYTHON_CMD" ]; then
            echo "  Skipping $dir - Python not available"
            continue
        fi

        mkdir -p "$dir"

        if setup_python_env "$dir" "requirements.txt"; then
            ((PYTHON_ENVS_CREATED++))
        fi
    fi
done

if [ $PYTHON_ENVS_CREATED -eq 0 ]; then
    echo "  No Python projects detected"
elif [ $PYTHON_ENVS_CREATED -eq 1 ]; then
    echo "  Set up 1 Python environment"
else
    echo "  Set up $PYTHON_ENVS_CREATED Python environments"
fi

if [ $PYTHON_ENVS_CREATED -gt 0 ]; then
    echo ""
    echo "Virtual Environment Activation Guide:"
    for dir in "${PYTHON_DIRS[@]}"; do
        if [ -f "$dir/requirements.txt" ] && [ -f "$dir/venv/bin/activate" ]; then
            if [ "$dir" = "." ]; then
                echo "  Root project: source venv/bin/activate"
            else
                echo "  $dir project: cd $dir && source venv/bin/activate"
            fi
        fi
    done
    echo ""
fi

# ============================================================================
# NODE.JS SETUP
# ============================================================================
if [ -f "frontend/package.json" ]; then
    echo "Installing frontend dependencies..."
    cd frontend
    npm install
    cd ..
    echo "  Frontend dependencies installed"
elif [ -f "package.json" ]; then
    echo "Installing Node dependencies..."
    npm install
    echo "  Node dependencies installed"
fi

# ============================================================================
# DATABASE SETUP
# ============================================================================
echo "Setting up worktree database..."
if command -v psql &> /dev/null; then
    PG_HOST=${PGHOST:-localhost}
    PG_PORT=${PGPORT:-5432}
    PG_USER=${PGUSER:-$USER}

    echo "Testing PostgreSQL connection..."
    echo "  Host: $PG_HOST  Port: $PG_PORT  User: $PG_USER"

    if ! pg_isready -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" &> /dev/null; then
        echo "  PostgreSQL not running or not accessible"
        echo "  Start with: brew services start postgresql"
    else
        echo "  PostgreSQL connection successful"

        MAIN_DB_NAME=""

        for env_file in "$PROJECT_ROOT/.env" "$PROJECT_ROOT/backend/.env" "$PROJECT_ROOT/frontend/.env.local"; do
            if [ -f "$env_file" ]; then
                DB_FROM_URL=$(grep -E "^DATABASE_URL=" "$env_file" 2>/dev/null | head -1 | sed -E 's|.*://[^/]*/([^?]*)\??.*|\1|')
                DB_FROM_NAME=$(grep -E "^DB_NAME=" "$env_file" 2>/dev/null | head -1 | cut -d'=' -f2)

                if [ -n "$DB_FROM_URL" ]; then
                    MAIN_DB_NAME="$DB_FROM_URL"
                    echo "  Found database in $env_file: $MAIN_DB_NAME"
                    break
                elif [ -n "$DB_FROM_NAME" ]; then
                    MAIN_DB_NAME="$DB_FROM_NAME"
                    echo "  Found database in $env_file: $MAIN_DB_NAME"
                    break
                fi
            fi
        done

        if [ -z "$MAIN_DB_NAME" ]; then
            echo "  No database found in env files, checking existing databases..."
            EXISTING_DBS=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -lqt 2>/dev/null | cut -d \| -f 1 | grep -E "^[[:space:]]*[a-zA-Z]" | grep -v -E "^[[:space:]]*(postgres|template[01]|)" | head -1 | xargs)
            if [ -z "$EXISTING_DBS" ] && [ "$PG_USER" != "postgres" ]; then
                EXISTING_DBS=$(psql -h "$PG_HOST" -p "$PG_PORT" -U postgres -lqt 2>/dev/null | cut -d \| -f 1 | grep -E "^[[:space:]]*[a-zA-Z]" | grep -v -E "^[[:space:]]*(postgres|template[01]|)" | head -1 | xargs)
            fi

            if [ -n "$EXISTING_DBS" ]; then
                MAIN_DB_NAME="$EXISTING_DBS"
                echo "  Found existing database: $MAIN_DB_NAME"
            fi
        fi

        if [ -n "$MAIN_DB_NAME" ]; then
            BRANCH_DB_NAME="${MAIN_DB_NAME}_${BRANCH_NAME}"
            echo "  Main database: $MAIN_DB_NAME"
            echo "  Branch database: $BRANCH_DB_NAME"

            DB_EXISTS=false
            if psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$MAIN_DB_NAME"; then
                DB_EXISTS=true
            elif [ "$PG_USER" != "postgres" ] && psql -h "$PG_HOST" -p "$PG_PORT" -U postgres -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$MAIN_DB_NAME"; then
                DB_EXISTS=true
                PG_USER="postgres"
            fi

            if [ "$DB_EXISTS" = true ]; then
                echo "  Cloning database $MAIN_DB_NAME to $BRANCH_DB_NAME..."

                if createdb -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -T "$MAIN_DB_NAME" "$BRANCH_DB_NAME" 2>/dev/null; then
                    echo "  Database cloned successfully"

                    echo "  Updating environment files..."
                    for env_file in ".env" "backend/.env" "frontend/.env.local"; do
                        if [ -f "$env_file" ]; then
                            if grep -q "DATABASE_URL=" "$env_file"; then
                                sed -i.bak "s|/$MAIN_DB_NAME|/$BRANCH_DB_NAME|g" "$env_file"
                                echo "    Updated DATABASE_URL in $env_file"
                            fi

                            if grep -q "DB_NAME=" "$env_file"; then
                                sed -i.bak "s/DB_NAME=$MAIN_DB_NAME/DB_NAME=$BRANCH_DB_NAME/g" "$env_file"
                                echo "    Updated DB_NAME in $env_file"
                            fi

                            rm -f "$env_file.bak"
                        fi
                    done

                    echo "  Checking for migration commands..."
                    if [ -f "alembic.ini" ] || [ -f "../alembic.ini" ]; then
                        echo "  Found Alembic - run 'alembic upgrade head' to apply migrations"
                    elif [ -f "package.json" ] && grep -q "migrate" package.json; then
                        echo "  Found npm migrate - run 'npm run migrate'"
                    fi
                else
                    echo "  Failed to clone database"
                    echo "  Manual: createdb -h $PG_HOST -p $PG_PORT -U $PG_USER -T $MAIN_DB_NAME $BRANCH_DB_NAME"
                fi
            else
                echo "  Main database '$MAIN_DB_NAME' not found"
            fi
        else
            echo "  Could not detect main database name"
        fi
    fi
else
    echo "  PostgreSQL client not found"
fi

# ============================================================================
# ENVIRONMENT VERIFICATION
# ============================================================================
echo ""
echo "Worktree Environment Summary:"
echo "  Location: $(pwd)"
echo "  Branch: ${BRANCH_TYPE}/${BRANCH_NAME}"

# Port summary
if [ -n "$SLOT" ] && [ -f "$PORTS_SCRIPT" ]; then
    PORT_SUMMARY=$("$PORTS_SCRIPT" summary "$SLOT" 2>/dev/null || echo "")
    if [ -n "$PORT_SUMMARY" ]; then
        echo "  Port slot: $SLOT (ports: $PORT_SUMMARY)"
    else
        echo "  Port slot: $SLOT"
    fi
fi

# Python summary
if [ $PYTHON_ENVS_CREATED -gt 0 ]; then
    echo "  Python environments:"
    for dir in "${PYTHON_DIRS[@]}"; do
        if [ -f "$dir/requirements.txt" ] && [ -f "$dir/venv/bin/activate" ]; then
            if [ "$dir" = "." ]; then
                echo "    Root (venv/)"
            else
                echo "    $dir (${dir}/venv/)"
            fi
        fi
    done
fi

# Node summary
if [ -f "package.json" ] || [ -f "frontend/package.json" ]; then
    echo "  Node.js: Installed"
fi

# Database summary
if [ -n "$BRANCH_DB_NAME" ]; then
    echo "  Database: $BRANCH_DB_NAME (cloned)"
fi

echo ""

# ============================================================================
# TERMINAL TAB RENAME
# ============================================================================
TAB_SCRIPT="$SCRIPT_DIR/worktree-tab-rename.sh"

# Determine display name
DISPLAY_TYPE=$(echo "$BRANCH_TYPE" | sed 's/^./\U&/')  # Capitalize first letter
DISPLAY_NAME=$(echo "$BRANCH_NAME" | sed 's/-/ /g' | sed 's/\b./\U&/g')  # Title case

# Determine port display
PORT_DISPLAY="N/A"
if [ -n "$SLOT" ] && [ -f "$PORTS_SCRIPT" ]; then
    PORT_DISPLAY=$("$PORTS_SCRIPT" summary "$SLOT" 2>/dev/null || echo "N/A")
fi

# Read tab format from .worktree.json or use default
TAB_FORMAT="{type}: {name} ({ports})"
if [ -f "$WORKTREE_CONFIG" ] && command -v jq >/dev/null 2>&1; then
    custom_format=$(jq -r '.tabFormat // empty' "$WORKTREE_CONFIG" 2>/dev/null)
    if [ -n "$custom_format" ]; then
        TAB_FORMAT="$custom_format"
    fi
fi

if [ -f "$TAB_SCRIPT" ]; then
    "$TAB_SCRIPT" --format "$TAB_FORMAT" --type "$DISPLAY_TYPE" --name "$DISPLAY_NAME" --ports "$PORT_DISPLAY"
fi

# Build the title for display and Warp automation
TAB_TITLE="$TAB_FORMAT"
TAB_TITLE="${TAB_TITLE//\{type\}/$DISPLAY_TYPE}"
TAB_TITLE="${TAB_TITLE//\{name\}/$DISPLAY_NAME}"
TAB_TITLE="${TAB_TITLE//\{ports\}/$PORT_DISPLAY}"

# ============================================================================
# SESSION TRANSITION INSTRUCTIONS
# ============================================================================
WORKTREE_PATH="$(pwd)"
RELATIVE_PATH="trees/${BRANCH_NAME}"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
MAGENTA='\033[1;35m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${RED}+------------------------------------------------------------------------------+${RESET}"
echo -e "${RED}|${RESET}"
echo -e "${RED}|${WHITE}${BOLD}  SWITCH TO WORKTREE NOW: ${CYAN}${TAB_TITLE}${RESET}"
echo -e "${RED}|${RESET}"
echo -e "${RED}|${GREEN}  1. End this Claude session (Ctrl+C or type 'exit')${RESET}"
echo -e "${RED}|${GREEN}  2. cd ${RELATIVE_PATH}${RESET}"
echo -e "${RED}|${GREEN}  3. claude code${RESET}"
echo -e "${RED}|${RESET}"
if [ -n "$SLOT" ] && [ -n "$PORT_DISPLAY" ] && [ "$PORT_DISPLAY" != "N/A" ]; then
echo -e "${RED}|${MAGENTA}  Ports: ${PORT_DISPLAY} (slot $SLOT)${RESET}"
echo -e "${RED}|${RESET}"
fi
echo -e "${RED}+------------------------------------------------------------------------------+${RESET}"
echo ""
# Build the one-liner for the new tab
LAUNCH_CMD="cd ${WORKTREE_PATH} && claude"

# Copy to clipboard
echo -n "$LAUNCH_CMD" | pbcopy 2>/dev/null

echo -e "${BOLD}${WHITE}Copied to clipboard — paste in new tab:${RESET}"
echo -e "${CYAN}  ${LAUNCH_CMD}${RESET}"
echo ""

# Open a new tab automatically
if [ "$TERM_PROGRAM" = "WarpTerminal" ]; then
    # Warp: open new tab via URL scheme, user pastes the command
    open "warp://action/new_tab" 2>/dev/null
    echo -e "${GREEN}New Warp tab opened — just paste (Cmd+V) and hit Enter${RESET}"

elif [ "$TERM_PROGRAM" = "iTerm.app" ]; then
    # iTerm2: open new tab and run the command directly
    osascript -e "
        tell application \"iTerm2\"
            tell current window
                create tab with default profile
                tell current session of current tab
                    write text \"${LAUNCH_CMD} && printf '\\\\033]0;${TAB_TITLE}\\\\007'\"
                end tell
            end tell
        end tell
    " >/dev/null 2>&1 && echo -e "${GREEN}New iTerm2 tab opened and running${RESET}" || true

else
    # Other terminals: just show the command
    echo -e "${YELLOW}Open a new tab and paste the command above${RESET}"
fi

# Send desktop notification
NOTIFICATION_SCRIPT="$SCRIPT_DIR/notify-agent-complete.sh"
if [ -f "$NOTIFICATION_SCRIPT" ]; then
    NOTIFICATION_MESSAGE="Worktree ready! ${TAB_TITLE} - cd trees/${BRANCH_NAME}"
    "$NOTIFICATION_SCRIPT" "attention" "$NOTIFICATION_MESSAGE" "worktree-${BRANCH_NAME}" >/dev/null 2>&1 &
    echo -e "${CYAN}Desktop notification sent${RESET}"
fi

echo ""
echo -e "${GREEN}${BOLD}Worktree creation complete: ${TAB_TITLE}${RESET}"
echo -e "${WHITE}Switch sessions to work in isolation!${RESET}"
