#!/bin/bash
# =====================================================================
# macOS Pro-Cleanup & Maintenance (v2.1)
# Author: Arif
# Description: Deep system cleaner targeting developer bloat.
#              Supports --dry-run mode and per-section size reporting.
#              Independent cleanup tasks run in parallel.
# =====================================================================

# --- Source shared helpers ---
source "$(dirname "$0")/lib/common.sh"

# --- Help override ---
_show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

macOS Pro-Cleanup & Maintenance — safely reclaims disk space from
developer caches, containers, and system caches.

Options:
  --dry-run   Preview what would be deleted without making changes
  --help, -h  Show this help message

Examples:
  ./cleanup.sh              # Run full cleanup
  ./cleanup.sh --dry-run    # Preview cleanup actions
EOF
}

parse_common_args "$@"
require_macos

# Skip Homebrew's auto-update/hints — we only need cleanup here
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1

echo -e "${BLUE}${BOLD}🧹 Starting Deep System Cleanup...${NC}"

# --- Disk space tracking (KB precision instead of whole GB) ---
get_free_kb() { df -k / | awk 'NR==2 {print $4}'; }
kb_to_gb()    { awk -v k="$1" 'BEGIN {printf "%.2f", k / 1048576}'; }

BEFORE_KB=$(get_free_kb)

# =====================================================================
# Task definitions (each runs in its own background job)
# =====================================================================

# clean_dir <label> <dir> [contents]
#   Reports size, then deletes the directory (or only its contents).
clean_dir() {
    local label=$1 dir=$2 mode=${3:-dir} size
    [[ -d "$dir" ]] || return 0
    size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY RUN]${NC} Would clear ${label} (${size:-?}): $dir"
        return 0
    fi
    if [[ "$mode" == "contents" ]]; then
        find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    else
        rm -rf "$dir" 2>/dev/null || true
    fi
    log_ok "${label} cleared (${size:-?})."
}

# 🐳 Docker — containers, networks, volumes, build cache (images preserved)
_clean_docker() {
    if ! docker info >/dev/null 2>&1; then
        log_info "Docker not running, skipping..."
        return 0
    fi
    local running count
    running=$(docker ps -q 2>/dev/null || true)
    if [[ -n "$running" ]]; then
        count=$(printf '%s\n' "$running" | wc -l | tr -d ' ')
        log_info "Stopping ${count} running container(s)..."
        # shellcheck disable=SC2086  # intentional word-splitting of IDs
        safe_exec docker stop $running >/dev/null 2>&1 || true
    fi
    safe_exec docker container prune -f 2>/dev/null || true
    safe_exec docker network prune -f 2>/dev/null || true
    safe_exec docker volume prune -f 2>/dev/null || true
    safe_exec docker builder prune -f 2>/dev/null || true
    log_ok "Docker cleanup done (images preserved)."
}

# 🐍 __pycache__ — skip huge/irrelevant trees and don't descend into matches
_find_pycache() {
    find "$HOME" -maxdepth 6 \
        \( -path "$HOME/Library" -o -path "$HOME/.Trash" -o -name node_modules -o -name .git \) -prune \
        -o -type d -name "__pycache__" -prune "$@" 2>/dev/null
}

_clean_pycache() {
    if [[ "$DRY_RUN" == "true" ]]; then
        local count
        count=$(_find_pycache -print | wc -l | tr -d ' ') || true
        echo -e "  ${YELLOW}[DRY RUN]${NC} Would delete ${count:-0} __pycache__ directories under \$HOME"
    else
        _find_pycache -exec rm -rf {} + || true
    fi
    log_ok "Python __pycache__ directories cleared."
}

_clean_pnpm() {
    safe_exec pnpm store prune 2>/dev/null || true
    log_ok "pnpm store pruned."
}

_clean_simulators() {
    safe_exec xcrun simctl delete unavailable 2>/dev/null || true
    log_ok "Unavailable iOS Simulators cleaned."
}

_brew_maintenance() {
    safe_exec brew cleanup -s 2>/dev/null || true
    safe_exec brew autoremove 2>/dev/null || true
    log_ok "Homebrew cleanup done."
}

# =====================================================================
# Phase 1: parallel developer cleanup
# =====================================================================
log_step "⚡ Running developer cleanup tasks in parallel..."

has docker && run_bg "🐳 Docker" _clean_docker
run_bg "🐍 Python __pycache__" _clean_pycache
run_bg "🛠  Xcode DerivedData"  clean_dir "Xcode DerivedData" "$HOME/Library/Developer/Xcode/DerivedData" contents
run_bg "📦 NPM cache"           clean_dir "NPM cache"            "$HOME/.npm/_cacache"
run_bg "🥟 Bun cache"           clean_dir "Bun cache"            "$HOME/.bun/install/cache"
run_bg "🧶 Yarn cache"          clean_dir "Yarn cache"           "$HOME/Library/Caches/Yarn"
run_bg "☕ CocoaPods cache"     clean_dir "CocoaPods cache"      "$HOME/Library/Caches/CocoaPods"
run_bg "🐘 Gradle caches"       clean_dir "Gradle caches"        "$HOME/.gradle/caches"
run_bg "🐹 Go module cache"     clean_dir "Go module cache"      "$HOME/go/pkg/mod/cache"
run_bg "🦀 Cargo registry"      clean_dir "Cargo registry cache" "$HOME/.cargo/registry/cache"
run_bg "🐍 Pip wheel cache"     clean_dir "Pip wheel cache"      "$HOME/Library/Caches/pip"
run_bg "🦕 Deno cache"          clean_dir "Deno cache"           "$HOME/Library/Caches/deno"
has pnpm && run_bg "📦 pnpm store" _clean_pnpm
has xcrun && run_bg "📱 iOS Simulators" _clean_simulators
has brew && run_bg "🍺 Homebrew Maintenance" _brew_maintenance

wait_bg

# =====================================================================
# Phase 2: system caches (interactive — runs in foreground)
# =====================================================================
log_step "🧹 Flushing System Caches..."

# System-level caches — require confirmation
if confirm_action "Clear /Library/Caches/* (requires sudo)?"; then
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY RUN]${NC} Would run: sudo rm -rf /Library/Caches/*"
    else
        sudo rm -rf /Library/Caches/* 2>/dev/null || true
    fi
    log_ok "System caches cleared."
else
    log_info "Skipped system cache cleanup."
fi

# User-level caches (keep Safari safe)
if [[ "$DRY_RUN" == "true" ]]; then
    USER_CACHE_COUNT=$(find "$HOME/Library/Caches" -mindepth 1 -maxdepth 1 -not -name "com.apple.Safari" 2>/dev/null | wc -l | tr -d ' ') || true
    echo -e "  ${YELLOW}[DRY RUN]${NC} Would delete ${USER_CACHE_COUNT:-0} items in ~/Library/Caches (preserving Safari)"
else
    find "$HOME/Library/Caches" -mindepth 1 -maxdepth 1 -not -name "com.apple.Safari" -exec rm -rf {} + 2>/dev/null || true
fi
log_ok "User caches cleared."

# Empty Trash (includes hidden files, which "/*" used to miss)
if confirm_action "Empty the Trash?"; then
    if [[ "$DRY_RUN" == "true" ]]; then
        TRASH_SIZE=$(du -sh "$HOME/.Trash" 2>/dev/null | awk '{print $1}') || true
        echo -e "  ${YELLOW}[DRY RUN]${NC} Would empty Trash (${TRASH_SIZE:-unknown})"
    else
        find "$HOME/.Trash" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    fi
    log_ok "Trash emptied."
else
    log_info "Skipped emptying Trash."
fi

# --- 📊 FINAL REPORT ---
AFTER_KB=$(get_free_kb)
RECLAIMED_KB=$((AFTER_KB - BEFORE_KB))

echo ""
echo "=========================================="
echo -e "${GREEN}${BOLD}✅ Cleanup Complete!${NC}"
echo "=========================================="
echo -e "Initial Space: $(kb_to_gb "$BEFORE_KB")GB"
echo -e "Current Space: $(kb_to_gb "$AFTER_KB")GB"
NOISE_KB=10240 # ignore <10MB jitter from background writes
if (( RECLAIMED_KB > NOISE_KB )); then
    echo -e "${GREEN}${BOLD}Total Reclaimed: $(kb_to_gb "$RECLAIMED_KB")GB${NC}"
elif (( RECLAIMED_KB >= -NOISE_KB )); then
    echo -e "${BLUE}Total Reclaimed: negligible (or dry-run mode)${NC}"
else
    echo -e "${YELLOW}Disk usage increased (background processes may have written data).${NC}"
fi
if (( BG_FAILURES > 0 )); then
    log_warn "${BG_FAILURES} task(s) reported errors — see log for details."
fi
echo "=========================================="
echo -e "${BLUE}📝 Full log: ${LOG_FILE}${NC}"