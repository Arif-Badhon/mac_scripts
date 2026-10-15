#!/bin/bash
# =====================================================================
# macOS Omni-Upgrade Script (v2.1)
# Author: Arif
# Description: One-click global upgrade for Homebrew, MAS, Python, NPM,
#              Bun, uv, and macOS — with change tracking.
#              macOS update check runs in the background during Homebrew;
#              toolchain upgrades run in parallel afterwards.
# =====================================================================

# --- Source shared helpers ---
source "$(dirname "$0")/lib/common.sh"

# --- Help override ---
_show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

macOS Omni-Upgrade — one-click global upgrade utility for all your
package managers and system software.

Options:
  --dry-run   Preview upgrade commands without executing them
  --help, -h  Show this help message

Sections:
  Homebrew (formulae + casks), Mac App Store (via mas), Python/Pip,
  NPM, Bun, uv, macOS Software Updates.
EOF
}

parse_common_args "$@"
require_macos

# We run `brew update` explicitly and a single `brew cleanup` at the end,
# so skip Homebrew's implicit auto-update and per-package cleanup.
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1

WARNINGS=0
warn() { log_warn "$1"; WARNINGS=$((WARNINGS + 1)); }

echo -e "${BLUE}${BOLD}🚀 Starting Global System Upgrade...${NC}"

# --- 0. macOS update check (slow, read-only) — start it right away ---
_sw_check() { softwareupdate -l 2>&1; }
log_info "Checking macOS Software Updates in the background..."
capture_bg swupdate _sw_check

# --- Change tracking snapshots (inside auto-cleaned $TMP_WORKDIR) ---
BREW_BEFORE="$TMP_WORKDIR/brew_before"
BREW_AFTER="$TMP_WORKDIR/brew_after"
BREW_PREFIX=""

# --- 1. HOMEBREW (Core & Casks) ---
if has brew; then
    BREW_PREFIX="${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null || true)}"
    log_step "🍺 Upgrading Homebrew packages and Casks..."
    brew list --versions > "$BREW_BEFORE" 2>/dev/null || true
    safe_exec brew update || warn "brew update failed — continuing with cached metadata."
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Currently outdated (based on cached metadata):"
        brew outdated --greedy --verbose 2>/dev/null | sed 's/^/    /' || true
    fi
    # Formulae and casks separately so casks are only checked once (with --greedy)
    safe_exec brew upgrade --formula || warn "Some formulae failed to upgrade."
    safe_exec brew upgrade --cask --greedy || warn "Some casks failed to upgrade."  # --greedy includes auto-updating apps
    brew list --versions > "$BREW_AFTER" 2>/dev/null || true
    log_ok "Homebrew upgrade done."
else
    log_err "Homebrew not found. Install from https://brew.sh/"
fi

# Returns 0 if the given command lives inside the Homebrew prefix
# (in which case `brew upgrade` already handled it).
_managed_by_brew() {
    local path
    path=$(command -v "$1" 2>/dev/null) || return 1
    [[ -n "$BREW_PREFIX" && "$path" == "$BREW_PREFIX"/* ]]
}

# --- 2–6. Independent upgrades (run in parallel) ---
_up_mas() {
    safe_exec mas upgrade
    log_ok "App Store upgrade done."
}

_up_pip() {
    local out
    if out=$(safe_exec python3 -m pip install --upgrade --quiet --disable-pip-version-check pip 2>&1); then
        [[ -n "$out" ]] && echo "$out"
        log_ok "Pip upgraded."
    elif [[ "$out" == *externally-managed* ]]; then
        log_info "Python is externally managed (PEP 668) — pip is upgraded with its Python."
    else
        echo "$out"
        return 1
    fi
}

_up_npm() {
    safe_exec npm install -g npm@latest --no-fund --no-audit --loglevel=error
    log_ok "NPM upgraded."
}

_up_bun() {
    safe_exec bun upgrade
    log_ok "Bun upgraded."
}

_up_uv() {
    safe_exec uv self update
    log_ok "uv upgraded."
}

_brew_cleanup() {
    safe_exec brew cleanup -s 2>/dev/null || true
    log_ok "Homebrew cleanup done."
}

log_step "⚡ Upgrading App Store apps & toolchains in parallel..."

if has mas; then
    run_bg "🍎 Mac App Store" _up_mas
else
    log_info "Tip: Install 'mas' (brew install mas) to update App Store apps via script."
fi

if has python3; then
    PY_PATH=$(command -v python3)
    if _managed_by_brew python3; then
        log_info "🐍 python3 is managed by Homebrew — pip already handled."
    elif [[ "$PY_PATH" == /usr/bin/python3 ]]; then
        log_info "🐍 Skipping pip for Apple's system Python (${PY_PATH})."
    else
        run_bg "🐍 Python / Pip" _up_pip
    fi
fi

has npm && run_bg "📦 NPM" _up_npm

if has bun; then
    if _managed_by_brew bun; then
        log_info "🧄 Bun is managed by Homebrew — already upgraded."
    else
        run_bg "🧄 Bun" _up_bun
    fi
fi

if has uv; then
    if _managed_by_brew uv; then
        log_info "⚡ uv is managed by Homebrew — already upgraded."
    else
        run_bg "⚡ uv" _up_uv
    fi
fi

has brew && run_bg "🧹 Post-upgrade cleanup" _brew_cleanup

wait_bg
WARNINGS=$((WARNINGS + BG_FAILURES))

# --- 7. macOS SYSTEM UPDATES (collect background result) ---
log_step "💻 macOS Software Updates:"
capture_get swupdate SW_OUT
if [[ -n "$SW_OUT" ]]; then
    printf '%s\n' "$SW_OUT" | sed 's/^/  /'
else
    warn "Could not check for macOS updates."
fi
log_info "To install: sudo softwareupdate -i -a  (may require a restart)"

# --- 📋 CHANGE REPORT ---
echo ""
echo "=========================================="
echo -e "${BLUE}${BOLD}📋 UPGRADE CHANGE REPORT${NC}"
echo "=========================================="

if [[ -s "$BREW_BEFORE" && -s "$BREW_AFTER" ]]; then
    DIFF_FILE="$TMP_WORKDIR/brew_diff"
    diff "$BREW_BEFORE" "$BREW_AFTER" > "$DIFF_FILE" 2>/dev/null || true
    REMOVED=$(sed -n 's/^< /  - /p' "$DIFF_FILE")
    ADDED=$(sed -n 's/^> /  + /p' "$DIFF_FILE")
    if [[ -n "$REMOVED" || -n "$ADDED" ]]; then
        if [[ -n "$REMOVED" ]]; then
            echo -e "${RED}Removed/Old versions:${NC}"
            echo "$REMOVED"
        fi
        if [[ -n "$ADDED" ]]; then
            echo -e "${GREEN}Added/Updated versions:${NC}"
            echo "$ADDED"
        fi
    else
        echo "  No Homebrew package changes detected."
    fi
else
    echo "  Homebrew not available or no snapshot taken."
fi

echo ""
echo "=========================================="
if (( WARNINGS > 0 )); then
    echo -e "${YELLOW}${BOLD}⚠️  UPGRADE FINISHED WITH ${WARNINGS} WARNING(S)${NC}"
else
    echo -e "${GREEN}${BOLD}✅ ALL SYSTEMS UP TO DATE${NC}"
fi
echo "=========================================="
echo -e "${BLUE}📝 Full log: ${LOG_FILE}${NC}"
