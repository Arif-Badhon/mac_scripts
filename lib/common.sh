#!/bin/bash
# =====================================================================
# Shared Helper Library for macOS Pro Scripts (v2.1)
# Author: Arif
# Description: Common colors, logging, safety helpers, and utilities.
#              Source this file in every script:
#              source "$(dirname "$0")/lib/common.sh"
# NOTE: Must stay compatible with macOS's stock /bin/bash (3.2):
#       no associative arrays, no mapfile, guard empty-array expansion.
# =====================================================================

# --- Prevent double-sourcing ---
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# --- Colors & Styles (disabled with NO_COLOR or when not on a terminal) ---
if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
fi

# --- Safety Flags ---
set -euo pipefail
trap '_on_error $LINENO' ERR

_on_error() {
    echo -e "${RED}❌ Script failed at line $1. Aborting.${NC}" >&2
    exit 1
}

# --- Temp workspace (auto-removed on exit) ---
# Scripts should use $TMP_WORKDIR instead of setting their own EXIT trap.
TMP_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/mac-scripts.XXXXXX")"
_cleanup_tmp() { rm -rf "$TMP_WORKDIR"; }
trap _cleanup_tmp EXIT

# --- Logging ---
LOG_DIR="$HOME/.mac-scripts/logs"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
mkdir -p "$LOG_DIR"
# Rotate old logs so the directory doesn't grow forever
find "$LOG_DIR" -name '*.log' -type f -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
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

# --- Small utilities ---
has() { command -v "$1" >/dev/null 2>&1; }

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

# =====================================================================
# Parallel execution helpers
# =====================================================================

# --- Display jobs: run in background, print buffered output in order ---
# Usage: run_bg "<label>" <command> [args...]   (command may be a function)
#        wait_bg                                 (prints outputs, sets BG_FAILURES)
_BG_PIDS=()
_BG_LABELS=()
_BG_OUTS=()
BG_FAILURES=0

run_bg() {
    local label=$1; shift
    local out="$TMP_WORKDIR/bg_${#_BG_PIDS[@]}_${RANDOM}.out"
    ( "$@" ) >"$out" 2>&1 </dev/null &
    _BG_PIDS+=("$!")
    _BG_LABELS+=("$label")
    _BG_OUTS+=("$out")
}

wait_bg() {
    local i rc
    BG_FAILURES=0
    (( ${#_BG_PIDS[@]} )) || return 0
    for (( i = 0; i < ${#_BG_PIDS[@]}; i++ )); do
        rc=0
        wait "${_BG_PIDS[$i]}" || rc=$?
        if [[ -s "${_BG_OUTS[$i]}" ]]; then
            echo -e "\n${YELLOW}${_BG_LABELS[$i]}${NC}"
            cat "${_BG_OUTS[$i]}"
        fi
        if (( rc != 0 )); then
            log_warn "${_BG_LABELS[$i]} finished with errors (exit $rc)."
            BG_FAILURES=$((BG_FAILURES + 1))
        fi
    done
    _BG_PIDS=(); _BG_LABELS=(); _BG_OUTS=()
    return 0
}

# --- Value jobs: start early, collect the result later ---
# Usage: capture_bg <key> <command> [args...]   (key must be [A-Za-z0-9_])
#        capture_get <key> <VARNAME>             (waits for that job only)
# NOTE: call capture_get directly, NOT inside $(...) — wait must run in
#       the parent shell.
capture_bg() {
    local key=$1; shift
    ( "$@" ) >"$TMP_WORKDIR/cap_$key" 2>/dev/null </dev/null &
    printf -v "_CAP_PID_$key" '%s' "$!"
}

capture_get() {
    local key=$1 var="_CAP_PID_$1" pid
    pid="${!var:-}"
    if [[ -n "$pid" ]]; then
        wait "$pid" 2>/dev/null || true
        printf -v "$var" '%s' ""
    fi
    printf -v "$2" '%s' "$(cat "$TMP_WORKDIR/cap_$key" 2>/dev/null || true)"
}
