#!/bin/bash
# =====================================================================
# macOS Pro-Cleanup & Maintenance
# Author: Arif
# =====================================================================

# --- Colors for UX ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧹 Starting Deep System Cleanup...${NC}"

# Helper function to get disk space in GB
get_free_space() {
    df -g / | awk 'NR==2 {print $4}'
}

BEFORE=$(get_free_space)

# --- 🐳 UPGRADED DOCKER CLEANUP ---
if command -v docker &> /dev/null && docker info &> /dev/null; then
    echo -e "\n${YELLOW}🐳 Cleaning Docker...${NC}"
    # Stop only if containers are running
    RUNNING_COLS=$(docker ps -q)
    if [ ! -z "$RUNNING_COLS" ]; then
        docker stop $RUNNING_COLS
    fi
    docker system prune -a --volumes -f
    docker builder prune -a -f
else
    echo -e "\n${RED}⏩ Docker not running, skipping...${NC}"
fi

# --- 🐍 SMART PYTHON CLEANUP ---
# Instead of uninstalling packages (risky), we clear the massive cache
echo -e "\n${YELLOW}🐍 Cleaning Python & Pip...${NC}"
python3 -m pip cache purge 2>/dev/null
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null

# --- 🛠 DEVELOPER DEEP CLEAN (The real space savers) ---
echo -e "\n${YELLOW}🛠 Cleaning Developer Bloat...${NC}"

# Xcode Derived Data (Can grow to 40GB+)
if [ -d "~/Library/Developer/Xcode/DerivedData" ]; then
    rm -rf ~/Library/Developer/Xcode/DerivedData/*
    echo "✅ Xcode DerivedData cleared."
fi

# NPM/Bun/Yarn Caches
[ -d ~/.npm ] && npm cache clean --force &>/dev/null && echo "✅ NPM cache cleared."
[ -d ~/.bun ] && rm -rf ~/.bun/install/cache && echo "✅ Bun cache cleared."

# --- 🍺 HOMEBREW MAINTENANCE ---
if command -v brew &> /dev/null; then
    echo -e "\n${YELLOW}🍺 Homebrew Maintenance...${NC}"
    brew cleanup -s
    brew autoremove
fi

# --- 🧹 SYSTEM HYGIENE ---
echo -e "\n${YELLOW}🧹 Flushing System Caches...${NC}"
sudo rm -rf /Library/Caches/*
# Note: Targeted delete for user caches to keep app settings safe
find ~/Library/Caches -mindepth 1 -maxdepth 1 -not -name "com.apple.Safari" -exec rm -rf {} + 2>/dev/null

# --- 📊 FINAL REPORT ---
AFTER=$(get_free_space)
RECLAIMED=$((AFTER - BEFORE))

echo "=========================================="
echo -e "${GREEN}✅ Cleanup Complete!${NC}"
echo -e "Initial Space: ${BEFORE}GB"
echo -e "Current Space: ${AFTER}GB"
echo -e "${BLUE}Total Reclaimed: ${RECLAIMED}GB${NC}"
echo "=========================================="