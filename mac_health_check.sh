#!/bin/bash
# =====================================================================
# macOS Health Check Pro - M-Series Optimized (AI Enhanced) (v2.0)
# Author: Arif
# Description: Advanced diagnostics with visual bars, thermal checks,
#              top processes, and LLM interpretation.
# =====================================================================

# --- Source shared helpers ---
source "$(dirname "$0")/lib/common.sh"

# --- Help override ---
_show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

macOS Health Check Pro — comprehensive diagnostics for Apple Silicon Macs
with visual progress bars and optional AI-driven analysis via Ollama.

Options:
  --help, -h  Show this help message

Sections:
  CPU & System Load, Memory Pressure, Disk Storage, Developer Caches,
  Network Diagnostics, Battery Health, Thermal Status, Top Processes,
  Recent Critical Logs, AI Interpretation (requires Ollama).
EOF
}

parse_common_args "$@"
require_macos

# --- Visual progress bar ---
draw_bar() {
    local percent=$1
    # Sanitize: clamp to 0–100 integer
    percent=${percent:-0}
    percent=$(printf '%.0f' "$percent" 2>/dev/null) || percent=0
    (( percent < 0 )) && percent=0
    (( percent > 100 )) && percent=100
    local size=20
    local filled=$(( percent * size / 100 ))
    local empty=$(( size - filled ))
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
# Strip trailing comma if present
LOAD="${LOAD%,}"
echo -n "Load Average (1m): $LOAD "

if (( $(echo "${LOAD:-0} > 8.0" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "${RED}⚠️ HIGH CPU LOAD${NC}"
else
    echo -e "${GREEN}✅ Normal${NC}"
fi

# --- 💾 MEMORY PRESSURE ---
echo -e "\n${BLUE}${BOLD}💾 MEMORY USAGE${NC}"
MEM_INFO=$(memory_pressure 2>/dev/null | tail -1) || MEM_INFO=""
MEM_FREE=$(echo "$MEM_INFO" | awk '{print $5}' | tr -d '%')
# Guard against empty or non-numeric values
if ! [[ "$MEM_FREE" =~ ^[0-9]+$ ]]; then
    MEM_FREE=0
    log_warn "Could not parse memory pressure output, showing 100% used."
fi
MEM_USED=$((100 - MEM_FREE))

echo -n "Pressure: "
if [[ "$MEM_USED" -gt 85 ]]; then
    echo -e "${RED}$(draw_bar $MEM_USED)${NC} (High Pressure)"
elif [[ "$MEM_USED" -gt 70 ]]; then
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
if [[ "$DISK_USAGE" -gt 85 ]]; then
    echo -e "${RED}$(draw_bar "$DISK_USAGE")${NC} - ${RED}Critical: Only $AVAIL left of $TOTAL${NC}"
elif [[ "$DISK_USAGE" -gt 75 ]]; then
    echo -e "${YELLOW}$(draw_bar "$DISK_USAGE")${NC} - ${YELLOW}Warning: $AVAIL left${NC}"
else
    echo -e "${GREEN}$(draw_bar "$DISK_USAGE")${NC} - $AVAIL left of $TOTAL"
fi

echo -e "\n${BOLD}Heavy Developer Caches:${NC}"
DOCKER_SIZE=$(du -sh "$HOME/Library/Containers/com.docker.docker" 2>/dev/null | awk '{print $1}' || true)
OLLAMA_SIZE=$(du -sh "$HOME/.ollama/models" 2>/dev/null | awk '{print $1}' || true)
XCODE_SIZE=$(du -sh "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | awk '{print $1}' || true)
echo "  🐳 Docker Cache:      ${DOCKER_SIZE:-0B}"
echo "  🦙 Ollama Models:     ${OLLAMA_SIZE:-0B}"
echo "  🛠  Xcode DerivedData: ${XCODE_SIZE:-0B}"

# --- 🌐 NETWORK DIAGNOSTICS ---
echo -e "\n${BLUE}${BOLD}🌐 NETWORK INFO${NC}"
# Use the default route interface instead of hardcoding en0
DEFAULT_IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
IP=$(ipconfig getifaddr "${DEFAULT_IF:-en0}" 2>/dev/null || echo "")
echo "Interface:   ${DEFAULT_IF:-unknown}"
echo "Internal IP: ${IP:-Not Connected}"

# Actual ping latency (ICMP)
PING=$(ping -c 3 8.8.8.8 2>/dev/null | tail -1 | awk -F '/' '{print $5}')
if [[ -n "$PING" ]]; then
    if (( $(echo "$PING > 150" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "Ping Latency: ${YELLOW}${PING}ms ⚠️ (Elevated)${NC}"
    else
        echo -e "Ping Latency: ${GREEN}${PING}ms ✅${NC}"
    fi
else
    echo -e "Ping Latency: ${RED}Unreachable ❌${NC}"
fi

# Actual DNS resolution test
DNS_LATENCY=$(dig google.com +noall +stats 2>/dev/null | awk '/Query time:/{print $4}')
if [[ -n "$DNS_LATENCY" ]]; then
    if (( DNS_LATENCY > 200 )); then
        echo -e "DNS Latency:  ${YELLOW}${DNS_LATENCY}ms ⚠️ (Slow)${NC}"
    else
        echo -e "DNS Latency:  ${GREEN}${DNS_LATENCY}ms ✅${NC}"
    fi
else
    echo -e "DNS Latency:  ${RED}Could not resolve ❌${NC}"
fi

# --- 🔋 BATTERY HEALTH ---
echo -e "\n${BLUE}${BOLD}🔋 BATTERY STATUS${NC}"
BATT_LEVEL=$(pmset -g batt 2>/dev/null | grep -o "[0-9]*%" | head -1 || true)
BATT_STATUS=$(pmset -g batt 2>/dev/null | grep -o "'.*'" | tr -d "'" || true)
BATT_HEALTH=$(system_profiler SPPowerDataType 2>/dev/null | grep "Maximum Capacity" | awk -F': ' '{print $2}' || true)
BATT_CYCLES=$(system_profiler SPPowerDataType 2>/dev/null | grep "Cycle Count" | awk -F': ' '{print $2}' || true)

echo "Charge Level:   ${BATT_LEVEL:-N/A} (${BATT_STATUS:-Unknown})"
echo "Maximum Health: ${BATT_HEALTH:-N/A}"
echo "Cycle Count:    ${BATT_CYCLES:-N/A}"

# --- 🌡️ THERMAL STATUS ---
echo -e "\n${BLUE}${BOLD}🌡️ THERMAL STATUS${NC}"
THERMAL=$(pmset -g therm 2>/dev/null | grep "CPU_Scheduler_Limit" | awk '{print $3}' || true)
if [[ -n "$THERMAL" ]] && (( THERMAL < 100 )); then
    echo -e "${RED}⚠️  CPU throttled to ${THERMAL}% — thermal pressure detected${NC}"
else
    echo -e "${GREEN}✅ No thermal throttling${NC}"
fi

# --- 📊 TOP RESOURCE PROCESSES ---
echo -e "\n${BLUE}${BOLD}📊 TOP RESOURCE CONSUMERS${NC}"
echo -e "${BOLD}  Top CPU:${NC}"
(ps -Arco pid,pcpu,comm 2>/dev/null | head -4 | while IFS= read -r line; do echo "    $line"; done) || true
echo -e "${BOLD}  Top Memory:${NC}"
(ps -Amco pid,rss,comm 2>/dev/null | head -4 | while IFS= read -r line; do echo "    $line"; done) || true

# --- 🧾 RECENT ERRORS ---
echo -e "\n${BLUE}${BOLD}🧾 RECENT CRITICAL LOGS (Last 10m)${NC}"
CRITICAL_LOGS=$(log show --predicate 'eventMessage contains "fatal" OR eventMessage contains "panic"' --last 10m --level error 2>/dev/null | grep "eventMessage" | tail -n 3 | awk -F'] ' '{print "- " $2}' || true)
if [[ -z "$CRITICAL_LOGS" ]]; then
    echo -e "  ${GREEN}No critical system panics detected.${NC}"
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

    METRICS="Disk Usage: ${DISK_USAGE:-N/A}%, Memory Pressure: ${MEM_USED:-N/A}%, 1m Load Average: ${LOAD:-N/A}, Ping Latency: ${PING:-N/A}ms, DNS Latency: ${DNS_LATENCY:-N/A}ms, Battery Health: ${BATT_HEALTH:-N/A}, Thermal Throttle: ${THERMAL:-100}%, Docker Cache Size: ${DOCKER_SIZE:-0B}, Ollama Models Size: ${OLLAMA_SIZE:-0B}. Recent Errors: ${CRITICAL_LOGS:-None}."

    # Pass metrics and system prompt to Ollama
    ollama run llama3.1:latest "Analyze these metrics: $METRICS. $SYSTEM_PROMPT" || log_warn "Ollama analysis failed."

    echo "--------------------------------------------------------"
else
    log_warn "Ollama is either not installed or the daemon is not running. Skipping AI analysis."
fi

echo -e "${BLUE}📝 Full log: ${LOG_FILE}${NC}"