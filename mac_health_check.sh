#!/bin/bash
# =====================================================================
# macOS Health Check Pro - M-Series Optimized (AI Enhanced)
# Author: Arif
# Description: Advanced diagnostics with visual bars and LLM interpretation
# =====================================================================

# --- Colors & Styles ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Helper function to generate visual progress bars
draw_bar() {
    local percent=$1
    local size=20
    local filled=$(echo "$percent * $size / 100" | bc)
    local empty=$((size - filled))
    local bar=$(printf "%${filled}s" | tr ' ' '█')
    local space=$(printf "%${empty}s" | tr ' ' '░')
    echo -n "[${bar}${space}] ${percent}%"
}

echo -e "${BLUE}${BOLD}🩺 Starting Advanced macOS Health Check...${NC}"
echo "=========================================="
echo "Date:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "Host:   $(hostname)"
echo "macOS:  $(sw_vers -productVersion) ($(uname -m))"
echo "Uptime: $(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
echo "Chip:   $(sysctl -n machdep.cpu.brand_string)"
echo "=========================================="

# --- 🧠 CPU & SYSTEM LOAD ---
echo -e "\n${BLUE}${BOLD}🧠 CPU & SYSTEM LOAD${NC}"
LOAD=$(uptime | awk -F'load averages:' '{ print $2 }' | awk '{print $1}')
echo -n "Load Average (1m): $LOAD "

if (( $(echo "$LOAD > 8.0" | bc -l) )); then
    echo -e "${RED}⚠️ HIGH CPU LOAD${NC}"
else
    echo -e "${GREEN}✅ Normal${NC}"
fi

# --- 💾 MEMORY PRESSURE ---
echo -e "\n${BLUE}${BOLD}💾 MEMORY USAGE${NC}"
MEM_INFO=$(memory_pressure | tail -1)
MEM_FREE=$(echo "$MEM_INFO" | awk '{print $5}' | tr -d '%')
MEM_USED=$((100 - MEM_FREE))

echo -n "Pressure: "
if [ "$MEM_USED" -gt 85 ]; then
    echo -e "${RED}$(draw_bar $MEM_USED)${NC} (High Pressure)"
elif [ "$MEM_USED" -gt 70 ]; then
    echo -e "${YELLOW}$(draw_bar $MEM_USED)${NC} (Moderate)"
else
    echo -e "${GREEN}$(draw_bar $MEM_USED)${NC} (Healthy)"
fi

# --- 💽 DISK STORAGE & CACHES ---
echo -e "\n${BLUE}${BOLD}💽 DISK STORAGE${NC}"
DISK_USAGE=$(df -h / | tail -1 | awk '{ print $5 }' | sed 's/%//')
AVAIL=$(df -h / | tail -1 | awk '{ print $4 }')
TOTAL=$(df -h / | tail -1 | awk '{ print $2 }')

echo -n "System Disk: "
if [ "$DISK_USAGE" -gt 85 ]; then
    echo -e "${RED}$(draw_bar $DISK_USAGE)${NC} - ${RED}Critical: Only $AVAIL left of $TOTAL${NC}"
elif [ "$DISK_USAGE" -gt 75 ]; then
    echo -e "${YELLOW}$(draw_bar $DISK_USAGE)${NC} - ${YELLOW}Warning: $AVAIL left${NC}"
else
    echo -e "${GREEN}$(draw_bar $DISK_USAGE)${NC} - $AVAIL left of $TOTAL"
fi

echo -e "\n${BOLD}Heavy Developer Caches:${NC}"
DOCKER_SIZE=$(du -sh ~/Library/Containers/com.docker.docker 2>/dev/null | awk '{print $1}')
OLLAMA_SIZE=$(du -sh ~/.ollama/models 2>/dev/null | awk '{print $1}')
echo "  🐳 Docker Cache:   ${DOCKER_SIZE:-0B}"
echo "  🦙 Ollama Models:  ${OLLAMA_SIZE:-0B}"

# --- 🌐 NETWORK DIAGNOSTICS ---
echo -e "\n${BLUE}${BOLD}🌐 NETWORK INFO${NC}"
IP=$(ipconfig getifaddr en0)
echo "Internal IP: ${IP:-Not Connected}"

PING=$(ping -c 3 8.8.8.8 2>/dev/null | tail -1 | awk -F '/' '{print $5}')
if [ -n "$PING" ]; then
    if (( $(echo "$PING > 150" | bc -l) )); then
        echo -e "DNS Latency: ${YELLOW}${PING}ms ⚠️ (Elevated)${NC}"
    else
        echo -e "DNS Latency: ${GREEN}${PING}ms ✅${NC}"
    fi
else
    echo -e "DNS Latency: ${RED}Unreachable ❌${NC}"
fi

# --- 🔋 BATTERY HEALTH ---
echo -e "\n${BLUE}${BOLD}🔋 BATTERY STATUS${NC}"
BATT_LEVEL=$(pmset -g batt | grep -o "[0-9]*%" | head -1)
BATT_STATUS=$(pmset -g batt | grep -o "'.*'" | tr -d "'")
BATT_HEALTH=$(system_profiler SPPowerDataType | grep "Maximum Capacity" | awk -F': ' '{print $2}')
BATT_CYCLES=$(system_profiler SPPowerDataType | grep "Cycle Count" | awk -F': ' '{print $2}')

echo "Charge Level:   ${BATT_LEVEL} ($BATT_STATUS)"
echo "Maximum Health: ${BATT_HEALTH:-N/A}"
echo "Cycle Count:    ${BATT_CYCLES:-N/A}"

# --- 🧾 RECENT ERRORS ---
echo -e "\n${BLUE}${BOLD}🧾 RECENT CRITICAL LOGS (Last 10m)${NC}"
CRITICAL_LOGS=$(log show --predicate 'eventMessage contains "fatal" OR eventMessage contains "panic"' --last 10m --level error 2>/dev/null | grep "eventMessage" | tail -n 3 | awk -F'\] ' '{print "- " $2}')
if [ -z "$CRITICAL_LOGS" ]; then
    echo "  ${GREEN}No critical system panics detected.${NC}"
else
    echo "$CRITICAL_LOGS"
fi

echo -e "\n${GREEN}${BOLD}✅ Health Check Completed!${NC}\n"

# =====================================================================
# 🤖 LOCAL LLM INTERPRETATION VIA OLLAMA (llama3.1:latest)
# =====================================================================

if command -v ollama >/dev/null 2>&1 && ollama list >/dev/null 2>&1; then
    echo -e "${BLUE}${BOLD}🤖 Generating AI Diagnostic Interpretation...${NC}"
    echo "--------------------------------------------------------"
    
    SYSTEM_PROMPT="You are a senior macOS systems engineer. Review this system health data and provide a short, user-friendly summary. Use bullet points and address: 1. What happened (Current state), 2. How it happened (Triggers for any warnings), and 3. What to do (Specific terminal commands or actions to resolve issues). Be concise."

    CHARGES="Disk Usage: $DISK_USAGE%, Memory Pressure: $MEM_USED%, 1m Load Average: $LOAD, Ping Latency: ${PING:-N/A}ms, Battery Health: ${BATT_HEALTH:-N/A}, Docker Cache Size: ${DOCKER_SIZE:-0B}, Ollama Models Size: ${OLLAMA_SIZE:-0B}. Recent Errors: ${CRITICAL_LOGS:-None}."
    
    # Passing the variables directly into llama3.1
    ollama run llama3.1:latest "Analyze these metrics: $CHARGES. $SYSTEM_PROMPT"
    
    echo "--------------------------------------------------------"
else
    echo -e "${YELLOW}⚠️ Ollama is either not installed or the daemon is not running. Skipping AI analysis.${NC}"
fi