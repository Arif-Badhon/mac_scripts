#!/bin/bash
# =====================================================================
# macOS Pro-Cleanup & Maintenance (v2.0)
# Author: Arif
# Description: Deep system cleaner targeting developer bloat.
#              Supports --dry-run mode and per-section size reporting.
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

echo -e "${BLUE}${BOLD}🧹 Starting Deep System Cleanup...${NC}"

# --- Disk space tracking ---
get_free_space() {
    df -g / | awk 'NR==2 {print $4}'
}

BEFORE=$(get_free_space)

# --- 🐳 DOCKER CLEANUP ---
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    log_step "🐳 Cleaning Docker..."
    # Stop running containers safely using an array
    RUNNING_CONTAINERS=( $(docker ps -q 2>/dev/null || true) )
    if [[ ${#RUNNING_CONTAINERS[@]} -gt 0 ]]; then
        log_info "Stopping ${#RUNNING_CONTAINERS[@]} running container(s)..."
        safe_exec docker stop "${RUNNING_CONTAINERS[@]}" 2>/dev/null || true
    fi
    # Only prune containers, networks, and volumes to preserve images
    safe_exec docker container prune -f 2>/dev/null || true
    safe_exec docker network prune -f 2>/dev/null || true
    safe_exec docker volume prune -f 2>/dev/null || true
    safe_exec docker builder prune -f 2>/dev/null || true
    log_ok "Docker cleanup done (images preserved)."
else
    log_info "Docker not running, skipping..."
fi

# --- 🐍 PYTHON CLEANUP ---
log_step "🐍 Cleaning Python & Pip caches..."
safe_exec python3 -m pip cache purge 2>/dev/null || true
# Search from $HOME with a depth limit instead of CWD
if [[ "$DRY_RUN" == "true" ]]; then
    PYCACHE_COUNT=$(find "$HOME" -maxdepth 6 -type d -name "__pycache__" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ${YELLOW}[DRY RUN]${NC} Would delete $PYCACHE_COUNT __pycache__ directories under \$HOME"
else
    find "$HOME" -maxdepth 6 -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
fi
log_ok "Python caches cleared."

# --- 🛠 DEVELOPER DEEP CLEAN ---
log_step "🛠 Cleaning Developer Bloat..."

# Xcode DerivedData (Can grow to 40GB+) — fixed: use $HOME, not ~
if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
    XCODE_SIZE=$(du -sh "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | awk '{print $1}')
    log_info "Xcode DerivedData: ${XCODE_SIZE:-unknown}"
    safe_rm "$HOME/Library/Developer/Xcode/DerivedData"/*
    log_ok "Xcode DerivedData cleared."
else
    log_info "No Xcode DerivedData found, skipping."
fi

# NPM cache
if [[ -d "$HOME/.npm" ]] && command -v npm >/dev/null 2>&1; then
    safe_exec npm cache clean --force 2>/dev/null || true
    log_ok "NPM cache cleared."
fi

# Bun cache
if [[ -d "$HOME/.bun/install/cache" ]]; then
    safe_rm "$HOME/.bun/install/cache"
    log_ok "Bun cache cleared."
fi

# Yarn cache
if [[ -d "$HOME/Library/Caches/Yarn" ]]; then
    YARN_SIZE=$(du -sh "$HOME/Library/Caches/Yarn" 2>/dev/null | awk '{print $1}')
    log_info "Yarn cache: ${YARN_SIZE:-unknown}"
    safe_rm "$HOME/Library/Caches/Yarn"
    log_ok "Yarn cache cleared."
fi

# CocoaPods cache
if [[ -d "$HOME/Library/Caches/CocoaPods" ]]; then
    COCOA_SIZE=$(du -sh "$HOME/Library/Caches/CocoaPods" 2>/dev/null | awk '{print $1}')
    log_info "CocoaPods cache: ${COCOA_SIZE:-unknown}"
    safe_rm "$HOME/Library/Caches/CocoaPods"
    log_ok "CocoaPods cache cleared."
fi

# Gradle caches
if [[ -d "$HOME/.gradle/caches" ]]; then
    GRADLE_SIZE=$(du -sh "$HOME/.gradle/caches" 2>/dev/null | awk '{print $1}')
    log_info "Gradle caches: ${GRADLE_SIZE:-unknown}"
    safe_rm "$HOME/.gradle/caches"
    log_ok "Gradle caches cleared."
fi

# Go module cache
if [[ -d "$HOME/go/pkg/mod/cache" ]]; then
    GO_SIZE=$(du -sh "$HOME/go/pkg/mod/cache" 2>/dev/null | awk '{print $1}')
    log_info "Go module cache: ${GO_SIZE:-unknown}"
    safe_rm "$HOME/go/pkg/mod/cache"
    log_ok "Go module cache cleared."
fi

# Rust/Cargo registry cache
if [[ -d "$HOME/.cargo/registry/cache" ]]; then
    CARGO_SIZE=$(du -sh "$HOME/.cargo/registry/cache" 2>/dev/null | awk '{print $1}')
    log_info "Cargo registry cache: ${CARGO_SIZE:-unknown}"
    safe_rm "$HOME/.cargo/registry/cache"
    log_ok "Cargo registry cache cleared."
fi

# pip wheel cache
if [[ -d "$HOME/Library/Caches/pip" ]]; then
    PIP_SIZE=$(du -sh "$HOME/Library/Caches/pip" 2>/dev/null | awk '{print $1}')
    log_info "Pip wheel cache: ${PIP_SIZE:-unknown}"
    safe_rm "$HOME/Library/Caches/pip"
    log_ok "Pip cache cleared."
fi

# pnpm cache
if command -v pnpm >/dev/null 2>&1; then
    safe_exec pnpm store prune 2>/dev/null || true
    log_ok "pnpm store pruned."
fi

# Deno cache
if command -v deno >/dev/null 2>&1; then
    safe_exec rm -rf "$HOME/Library/Caches/deno" 2>/dev/null || true
    log_ok "Deno cache cleared."
fi

# iOS Simulators (Unavailable)
if command -v xcrun >/dev/null 2>&1; then
    log_info "Cleaning unavailable iOS Simulators..."
    safe_exec xcrun simctl delete unavailable 2>/dev/null || true
    log_ok "iOS Simulators cleaned."
fi

# --- 🍺 HOMEBREW MAINTENANCE ---
if command -v brew >/dev/null 2>&1; then
    log_step "🍺 Homebrew Maintenance..."
    safe_exec brew cleanup -s 2>/dev/null || true
    safe_exec brew autoremove 2>/dev/null || true
    log_ok "Homebrew cleanup done."
fi

# --- 🧹 SYSTEM CACHES ---
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
    USER_CACHE_COUNT=$(find "$HOME/Library/Caches" -mindepth 1 -maxdepth 1 -not -name "com.apple.Safari" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ${YELLOW}[DRY RUN]${NC} Would delete $USER_CACHE_COUNT items in ~/Library/Caches (preserving Safari)"
else
    find "$HOME/Library/Caches" -mindepth 1 -maxdepth 1 -not -name "com.apple.Safari" -exec rm -rf {} + 2>/dev/null || true
fi
log_ok "User caches cleared."

# Empty Trash
if confirm_action "Empty the Trash?"; then
    if [[ "$DRY_RUN" == "true" ]]; then
        TRASH_SIZE=$(du -sh "$HOME/.Trash" 2>/dev/null | awk '{print $1}')
        echo -e "  ${YELLOW}[DRY RUN]${NC} Would empty Trash ($TRASH_SIZE)"
    else
        rm -rf "$HOME/.Trash"/* 2>/dev/null || true
    fi
    log_ok "Trash emptied."
else
    log_info "Skipped emptying Trash."
fi

# --- 📊 FINAL REPORT ---
AFTER=$(get_free_space)
RECLAIMED=$((AFTER - BEFORE))

echo ""
echo "=========================================="
echo -e "${GREEN}${BOLD}✅ Cleanup Complete!${NC}"
echo "=========================================="
echo -e "Initial Space: ${BEFORE}GB"
echo -e "Current Space: ${AFTER}GB"
if [[ "$RECLAIMED" -gt 0 ]]; then
    echo -e "${GREEN}${BOLD}Total Reclaimed: ${RECLAIMED}GB${NC}"
elif [[ "$RECLAIMED" -eq 0 ]]; then
    echo -e "${BLUE}Total Reclaimed: <1GB (or dry-run mode)${NC}"
else
    echo -e "${YELLOW}Disk usage increased (background processes may have written data).${NC}"
fi
echo "=========================================="
echo -e "${BLUE}📝 Full log: ${LOG_FILE}${NC}"