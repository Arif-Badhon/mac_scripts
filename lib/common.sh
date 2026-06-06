#!/bin/bash
# =====================================================================
# Shared Helper Library for macOS Pro Scripts
# Author: Arif
# Description: Common colors, logging, safety helpers, and utilities.
#              Source this file in every script:
#              source "$(dirname "$0")/lib/common.sh"
# =====================================================================

# --- Prevent double-sourcing ---
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# --- Colors & Styles ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Safety Flags ---
set -euo pipefail
trap '_on_error $LINENO' ERR

_on_error() {
    echo -e "${RED}❌ Script failed at line $1. Aborting.${NC}" >&2
    exit 1
}

# --- Logging ---
LOG_DIR="$HOME/.mac-scripts/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(basename "$0" .sh)_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo -e "${BLUE}📝 Log file: ${LOG_FILE}${NC}"

# --- Platform Guard ---
require_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        echo -e "${RED}❌ These scripts are designed for macOS only.${NC}"
        exit 1
    fi
}

# --- Logging Helpers ---
log_step()  { echo -e "\n${YELLOW}$1${NC}"; }
log_ok()    { echo -e "${GREEN}✅ $1${NC}"; }
log_err()   { echo -e "${RED}❌ $1${NC}"; }
log_warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_info()  { echo -e "${BLUE}ℹ️  $1${NC}"; }

# --- Dry-Run Support ---
# Scripts can set DRY_RUN=true before sourcing, or pass --dry-run as $1
DRY_RUN="${DRY_RUN:-false}"

parse_common_args() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            --help|-h) _show_help; exit 0 ;;
        esac
    done
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}${BOLD}🔍 DRY-RUN MODE — no destructive actions will be taken.${NC}"
    fi
}

# Override this in individual scripts
_show_help() {
    echo "Usage: $(basename "$0") [--dry-run] [--help]"
}

# Wrapper: safe delete
safe_rm() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY RUN]${NC} Would delete: $*"
    else
        rm -rf "$@"
    fi
}

# Wrapper: safe command execution (for destructive commands)
safe_exec() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY RUN]${NC} Would run: $*"
    else
        "$@"
    fi
}

# --- Utility: confirm before dangerous operations ---
confirm_action() {
    local message="${1:-Proceed?}"
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0 # In dry-run, always "confirm" so we see what would happen
    fi
    read -rp "$(echo -e "${YELLOW}⚠️  ${message} [y/N]: ${NC}")" confirm
    [[ "$confirm" =~ ^[Yy]$ ]]
}
