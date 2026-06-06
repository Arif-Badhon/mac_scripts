#!/bin/bash
# =====================================================================
# macOS Omni-Upgrade Script (v2.0)
# Author: Arif
# Description: One-click global upgrade for Homebrew, MAS, Python, NPM,
#              Bun, uv, and macOS — with change tracking.
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

echo -e "${BLUE}${BOLD}🚀 Starting Global System Upgrade...${NC}"

# --- Temp files for change tracking ---
BREW_BEFORE=$(mktemp /tmp/brew_before.XXXXXX) || true
BREW_AFTER=$(mktemp /tmp/brew_after.XXXXXX) || true
# Clean up temp files on exit
trap 'rm -f "$BREW_BEFORE" "$BREW_AFTER"; _on_error ${LINENO:-0}' ERR
trap 'rm -f "$BREW_BEFORE" "$BREW_AFTER"' EXIT

# --- 1. HOMEBREW (Core & Casks) ---
if command -v brew &> /dev/null; then
    log_step "🍺 Upgrading Homebrew packages and Casks..."
    # Snapshot before
    brew list --versions > "$BREW_BEFORE" 2>/dev/null || true
    safe_exec brew update
    safe_exec brew upgrade
    safe_exec brew upgrade --cask --greedy  # --greedy forces updates for apps that auto-update
    # Snapshot after
    brew list --versions > "$BREW_AFTER" 2>/dev/null || true
    log_ok "Homebrew upgrade done."
else
    log_err "Homebrew not found. Install from https://brew.sh/"
fi

# --- 2. MAC APP STORE (via MAS CLI) ---
if command -v mas &> /dev/null; then
    log_step "🍎 Checking Mac App Store updates..."
    safe_exec mas upgrade
    log_ok "App Store upgrade done."
else
    log_info "Tip: Install 'mas' (brew install mas) to update App Store apps via script."
fi

# --- 3. PYTHON (Pip) ---
if command -v pip3 &> /dev/null; then
    log_step "🐍 Upgrading pip..."
    safe_exec python3 -m pip install --upgrade pip 2>/dev/null || true
    log_ok "Pip upgraded."
fi

# --- 4. NODE.JS / NPM ---
if command -v npm &> /dev/null; then
    log_step "📦 Upgrading NPM..."
    safe_exec npm install -g npm@latest 2>/dev/null || true
    log_ok "NPM upgraded."
fi

# --- 5. BUN ---
if command -v bun &> /dev/null; then
    log_step "🧄 Upgrading Bun..."
    safe_exec bun upgrade 2>/dev/null || true
    log_ok "Bun upgraded."
fi

# --- 6. UV (Python) ---
if command -v uv &> /dev/null; then
    log_step "⚡ Upgrading uv..."
    safe_exec uv self update 2>/dev/null || true
    log_ok "uv upgraded."
fi

# --- 7. macOS SYSTEM UPDATES ---
log_step "💻 Checking for macOS Software Updates..."
# -l lists updates; -i -a would install them (requires restart usually)
softwareupdate -l 2>/dev/null || log_warn "Could not check for macOS updates."

# --- 8. POST-UPGRADE CLEANUP ---
if command -v brew &> /dev/null; then
    log_step "🧹 Running post-upgrade cleanup..."
    safe_exec brew cleanup -s 2>/dev/null || true
    log_ok "Homebrew cleanup done."
fi

# --- 📋 CHANGE REPORT ---
echo ""
echo "=========================================="
echo -e "${BLUE}${BOLD}📋 UPGRADE CHANGE REPORT${NC}"
echo "=========================================="

if command -v brew &> /dev/null && [[ -s "$BREW_BEFORE" ]] && [[ -s "$BREW_AFTER" ]]; then
    CHANGES=$(diff "$BREW_BEFORE" "$BREW_AFTER" 2>/dev/null | grep "^[<>]") || CHANGES=""
    if [[ -n "$CHANGES" ]]; then
        ADDED=$(echo "$CHANGES" | grep "^>" | sed 's/^> /  + /')
        REMOVED=$(echo "$CHANGES" | grep "^<" | sed 's/^< /  - /')
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
echo -e "${GREEN}${BOLD}✅ ALL SYSTEMS UP TO DATE${NC}"
echo "=========================================="
echo -e "${BLUE}📝 Full log: ${LOG_FILE}${NC}"
