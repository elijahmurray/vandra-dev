#!/usr/bin/env bash
set -euo pipefail

# terminal-setup.sh — Configure terminal for persistent worktree tab titles
#
# Checks and optionally patches shell config so that worktree tab names
# persist even while Claude Code is running.
#
# Requirements:
#   1. DISABLE_AUTO_TITLE="true"         — stops oh-my-zsh from overriding
#   2. CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1 — stops Claude Code from overriding
#   3. tt() shell function + precmd hook  — sets and enforces the title
#   4. iTerm2: Profile > General > Title set to "Session Name" only

SETUP_FLAG="${HOME}/.claude/.terminal-setup-complete"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

SHELL_RC=""
SHELL_NAME=""
if [ -n "${ZSH_VERSION:-}" ] || [ "${SHELL##*/}" = "zsh" ]; then
    SHELL_RC="${HOME}/.zshrc"
    SHELL_NAME="zsh"
elif [ -n "${BASH_VERSION:-}" ] || [ "${SHELL##*/}" = "bash" ]; then
    SHELL_RC="${HOME}/.bashrc"
    SHELL_NAME="bash"
else
    echo -e "${YELLOW}Unknown shell — manual setup required${RESET}"
    SHELL_RC=""
    SHELL_NAME="unknown"
fi

issues_found=0

check_disable_auto_title() {
    if [ "$SHELL_NAME" != "zsh" ]; then
        return 0
    fi
    if [ -z "$SHELL_RC" ] || [ ! -f "$SHELL_RC" ]; then
        return 1
    fi
    # Check if DISABLE_AUTO_TITLE is set before oh-my-zsh sourcing
    if grep -q 'DISABLE_AUTO_TITLE.*true' "$SHELL_RC" 2>/dev/null; then
        echo -e "  ${GREEN}✓${RESET} DISABLE_AUTO_TITLE is set"
        return 0
    else
        echo -e "  ${RED}✗${RESET} DISABLE_AUTO_TITLE not set (oh-my-zsh overrides tab titles)"
        issues_found=$((issues_found + 1))
        return 1
    fi
}

check_claude_title_env() {
    if grep -q 'CLAUDE_CODE_DISABLE_TERMINAL_TITLE' "$SHELL_RC" 2>/dev/null; then
        echo -e "  ${GREEN}✓${RESET} CLAUDE_CODE_DISABLE_TERMINAL_TITLE is exported"
        return 0
    else
        echo -e "  ${RED}✗${RESET} CLAUDE_CODE_DISABLE_TERMINAL_TITLE not set (Claude Code overrides tab titles)"
        issues_found=$((issues_found + 1))
        return 1
    fi
}

check_tt_function() {
    if grep -q '^tt()' "$SHELL_RC" 2>/dev/null; then
        echo -e "  ${GREEN}✓${RESET} tt() function defined"
        return 0
    else
        echo -e "  ${RED}✗${RESET} tt() function not found (no persistent tab title support)"
        issues_found=$((issues_found + 1))
        return 1
    fi
}

check_precmd_hook() {
    if grep -q '_enforce_tab_title' "$SHELL_RC" 2>/dev/null; then
        echo -e "  ${GREEN}✓${RESET} precmd hook for tab title enforcement"
        return 0
    else
        echo -e "  ${RED}✗${RESET} No precmd hook (tab title won't persist across commands)"
        issues_found=$((issues_found + 1))
        return 1
    fi
}

check_iterm2() {
    if [ "${TERM_PROGRAM:-}" != "iTerm.app" ]; then
        echo -e "  ${YELLOW}–${RESET} Not running in iTerm2 (skipping iTerm2 checks)"
        return 0
    fi
    # Check if Job Name is disabled in title (can't fully check programmatically)
    echo -e "  ${YELLOW}?${RESET} iTerm2 detected — verify manually:"
    echo -e "    Profile > General > Title: select ${BOLD}Session Name${RESET} only"
    echo -e "    Uncheck ${BOLD}Job Name${RESET} (shows 'node' and overrides custom titles)"
    return 0
}

# ---------------------------------------------------------------------------
# Patch
# ---------------------------------------------------------------------------

ZSH_PATCH='
# --- vandra-dev terminal tab title support ---
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1

_custom_tab_title=""
tt() {
  _custom_tab_title="$*"
  printf '"'"'\e]1;%s\a'"'"' "$_custom_tab_title"
}
_enforce_tab_title() {
  if [[ -n "$_custom_tab_title" ]]; then
    printf '"'"'\e]1;%s\a'"'"' "$_custom_tab_title"
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _enforce_tab_title
add-zsh-hook preexec _enforce_tab_title
# --- end vandra-dev ---'

BASH_PATCH='
# --- vandra-dev terminal tab title support ---
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1

_custom_tab_title=""
tt() {
  _custom_tab_title="$*"
  printf '"'"'\e]1;%s\a'"'"' "$_custom_tab_title"
}
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_enforce_tab_title"
_enforce_tab_title() {
  if [ -n "$_custom_tab_title" ]; then
    printf '"'"'\e]1;%s\a'"'"' "$_custom_tab_title"
  fi
}
# --- end vandra-dev ---'

apply_patch() {
    if [ -z "$SHELL_RC" ]; then
        echo -e "${RED}Cannot patch — unknown shell config file${RESET}"
        return 1
    fi

    # Check if already patched
    if grep -q '# --- vandra-dev terminal tab title support ---' "$SHELL_RC" 2>/dev/null; then
        echo -e "${YELLOW}Already patched — removing old patch first${RESET}"
        # Remove old patch
        sed -i'' -e '/# --- vandra-dev terminal tab title support ---/,/# --- end vandra-dev ---/d' "$SHELL_RC"
    fi

    local patch
    if [ "$SHELL_NAME" = "zsh" ]; then
        patch="$ZSH_PATCH"

        # Add DISABLE_AUTO_TITLE before oh-my-zsh if not present
        if ! grep -q 'DISABLE_AUTO_TITLE.*true' "$SHELL_RC" 2>/dev/null; then
            if grep -q 'source.*oh-my-zsh' "$SHELL_RC" 2>/dev/null; then
                # Insert before oh-my-zsh sourcing
                sed -i'' -e '/source.*oh-my-zsh/i\
DISABLE_AUTO_TITLE="true"
' "$SHELL_RC"
                echo -e "  ${GREEN}Added DISABLE_AUTO_TITLE before oh-my-zsh${RESET}"
            else
                # No oh-my-zsh, just add at top
                echo 'DISABLE_AUTO_TITLE="true"' >> "$SHELL_RC"
            fi
        fi
    else
        patch="$BASH_PATCH"
    fi

    echo "$patch" >> "$SHELL_RC"
    echo -e "${GREEN}Patched ${SHELL_RC}${RESET}"
    echo -e "${YELLOW}Run 'source ${SHELL_RC}' or open a new tab to activate${RESET}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

MODE="${1:-check}"

case "$MODE" in
    check)
        echo -e "${BOLD}${WHITE}Terminal Tab Title Setup Check${RESET}"
        echo ""

        if [ -z "$SHELL_RC" ] || [ ! -f "$SHELL_RC" ]; then
            echo -e "${RED}Shell config not found: ${SHELL_RC:-unknown}${RESET}"
            exit 1
        fi

        check_disable_auto_title
        check_claude_title_env
        check_tt_function
        check_precmd_hook
        check_iterm2

        echo ""
        if [ $issues_found -eq 0 ]; then
            echo -e "${GREEN}${BOLD}All checks passed!${RESET}"
            mkdir -p "$(dirname "$SETUP_FLAG")"
            touch "$SETUP_FLAG"
        else
            echo -e "${YELLOW}${BOLD}${issues_found} issue(s) found.${RESET}"
            echo -e "Run with ${CYAN}apply${RESET} to auto-patch: ${CYAN}terminal-setup.sh apply${RESET}"
        fi
        ;;

    apply)
        echo -e "${BOLD}${WHITE}Applying terminal tab title configuration...${RESET}"
        echo ""
        apply_patch
        echo ""

        # Re-run checks
        issues_found=0
        check_disable_auto_title
        check_claude_title_env
        check_tt_function
        check_precmd_hook
        check_iterm2

        echo ""
        if [ $issues_found -eq 0 ]; then
            echo -e "${GREEN}${BOLD}Setup complete!${RESET}"
            mkdir -p "$(dirname "$SETUP_FLAG")"
            touch "$SETUP_FLAG"
        fi
        ;;

    status)
        if [ -f "$SETUP_FLAG" ]; then
            echo "configured"
        else
            echo "not-configured"
        fi
        ;;

    *)
        echo "Usage: terminal-setup.sh [check|apply|status]"
        exit 1
        ;;
esac
