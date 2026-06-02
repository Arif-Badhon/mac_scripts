#!/bin/bash
# =====================================================================
# macOS Omni-Upgrade Script
# Author: Arif
# Description: One-click upgrade for Homebrew, MAS, Python, and macOS
# =====================================================================

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting Global System Upgrade...${NC}"

# --- 1. HOMEBREW (Core & Casks) ---
if command -v brew &> /dev/null; then
    echo -e "\n${YELLOW}🍺 Upgrading Homebrew packages and Casks...${NC}"
    brew update
    brew upgrade
    brew upgrade --cask --greedy # --greedy forces updates for apps that auto-update
else
    echo -e "${RED}❌ Homebrew not found.${NC}"
fi

# --- 2. MAC APP STORE (via MAS CLI) ---
# Note: Requires 'mas' installed (brew install mas)
if command -v mas &> /dev/null; then
    echo -e "\n${YELLOW}🍎 Checking Mac App Store updates...${NC}"
    mas upgrade
else
    echo -e "${YELLOW}💡 Tip: Install 'mas' (brew install mas) to update App Store apps via script.${NC}"
fi

# --- 3. PYTHON (Pip) ---
if command -v pip3 &> /dev/null; then
    echo -e "\n${YELLOW}🐍 Upgrading global Pip and core packages...${NC}"
    python3 -m pip install --upgrade pip
    # Optional: Upgrade all global packages (Use with caution)
    # pip3 list --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1 | xargs -n1 pip3 install -U
fi

# --- 4. NODE.JS / NPM ---
if command -v npm &> /dev/null; then
    echo -e "\n${YELLOW}📦 Upgrading NPM global packages...${NC}"
    npm install -g npm@latest
    # npm update -g # Optional: updates all global node modules
fi

# --- 5. macOS SYSTEM UPDATES ---
echo -e "\n${YELLOW}💻 Checking for macOS Software Updates...${NC}"
# -l lists updates, -i -a would install them (requires restart usually)
softwareupdate -l

# --- 6. FINAL POST-UPGRADE CLEANUP ---
echo -e "\n${BLUE}🧹 Running post-upgrade cleanup...${NC}"
brew cleanup -s

echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}✅ ALL SYSTEMS UP TO DATE${NC}"
echo -e "${GREEN}==========================================${NC}"
