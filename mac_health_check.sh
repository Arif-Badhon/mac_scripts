#!/bin/bash
# =====================================================================
# macOS Health Check Pro - M-Series Optimized (AI Enhanced) (v2.1)
# Author: Arif
# Description: Advanced diagnostics with visual bars, thermal checks,
#              top processes, and LLM interpretation.
#              Slow probes (network, du, system_profiler, log show) run
#              in parallel while fast metrics are being displayed.
# =====================================================================

# --- Source shared helpers ---
source "$(dirname "$0")/lib/common.sh"

# --- Configuration ---
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.1:latest}"
NO_AI=false

# --- Help override ---
_show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

macOS Health Check Pro — comprehensive diagnostics for Apple Silicon Macs
with visual progress bars and optional AI-driven analysis via Ollama.

Options:
  --no-ai     Skip the Ollama AI interpretation
  --help, -h  Show this help message

Environment:
  OLLAMA_MODEL  Model used for AI analysis (default: llama3.1:latest)

Sections:
  CPU & System Load, Memory Pressure, Disk Storage, Developer Caches,
  Network Diagnostics, Battery Health, Thermal Status, Top Processes,
  Recent Critical Logs, AI Interpretation (requires Ollama).
EOF
}

for arg in "$@"; do
    [[ "$arg" == "--no-ai" ]] && NO_AI=true
done
parse_common_args "$@"
require_macos

# =====================================================================
# Kick off slow probes in the background immediately
# =====================================================================
_probe_ping() {
    ping -c 3 -t 5 8.8.8.8 2>/dev/null | awk -F'/' '/round-trip|rtt/ {print $5}'
}
_probe_dns() {
    dig google.com +noall +stats +time=2 +tries=1 2>/dev/null | awk '/Query time:/ {print $4}'
}
_probe_du() {
    du -sh "$1" 2>/dev/null | awk '{print $1}'
}
# One system_profiler call (it's slow) for both health and cycle count
_probe_power() {
    system_profiler SPPowerDataType 2>/dev/null \
        | awk -F': ' '/Maximum Capacity/ {h=$2} /Cycle Count/ {c=$2} END {print h "|" c}'
}
_probe_logs() {
    log show --last 10m --style compact \
        --predicate '(messageType == error OR messageType == fault) AND (eventMessage CONTAINS[c] "panic" OR eventMessage CONTAINS[c] "fatal")' \
        2>/dev/null \
        | awk '!/^(Timestamp|Skipping|Filtering)/ && NF' \
        | tail -n 3 | cut -c1-200 | sed 's/^/- /'
}

capture_bg ping   _probe_ping
capture_bg dns    _probe_dns
capture_bg docker _probe_du "$HOME/Library/Containers/com.docker.docker"
capture_bg ollama _probe_du "$HOME/.ollama/models"
capture_bg xcode  _probe_du "$HOME/Library/Developer/Xcode/DerivedData"
capture_bg power  _probe_power
capture_bg logs   _probe_logs

# --- Visual progress bar (pure bash, no subprocesses) ---
draw_bar() {
    local percent=${1:-0} size=20 filled empty bar="" i
    percent=$(printf '%.0f' "$percent" 2>/dev/null) || percent=0
    if (( percent < 0 )); then percent=0; fi
    if (( percent > 100 )); then percent=100; fi
    filled=$(( percent * size / 100 ))
    empty=$(( size - filled ))
    for (( i = 0; i < filled; i++ )); do bar+="█"; done
    for (( i = 0; i < empty; i++ )); do bar+="░"; done
    echo -n "[${bar}] ${percent}%"
}

# --- Uptime from kernel boot time (locale-independent) ---
BOOT_SEC=$(sysctl -n kern.boottime 2>/dev/null | awk -F'[ ,]+' '{print $4}')
if [[ "$BOOT_SEC" =~ ^[0-9]+$ ]]; then
    UP=$(( $(date +%s) - BOOT_SEC ))
    UPTIME_STR="$(( UP / 86400 ))d $(( UP % 86400 / 3600 ))h $(( UP % 3600 / 60 ))m"
else
    UPTIME_STR="unknown"
fi

echo -e "${BLUE}${BOLD}🩺 Starting Advanced macOS Health Check...${NC}"
echo "=========================================="
echo "Date:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "Host:   $(hostname)"
echo "macOS:  $(sw_vers -productVersion) ($(uname -m))"
echo "Uptime: ${UPTIME_STR}"
echo "Chip:   $(sysctl -n machdep.cpu.brand_string)"
echo "=========================================="

# --- 🧠 CPU & SYSTEM LOAD ---
echo -e "\n${BLUE}${BOLD}🧠 CPU & SYSTEM LOAD${NC}"
NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)
# vm.loadavg looks like: "{ 1.95 2.10 2.20 }"
read -r _ LOAD _ <<<"$(sysctl -n vm.loadavg 2>/dev/null)" || true
LOAD="${LOAD:-0}"
echo -n "Load Average (1m): $LOAD (${NCPU} cores) "

# Threshold scales with core count instead of a fixed 8.0
if awk -v l="$LOAD" -v n="$NCPU" 'BEGIN {exit !(l > n)}'; then
    echo -e "${RED}⚠️ HIGH CPU LOAD${NC}"
else
    echo -e "${GREEN}✅ Normal${NC}"
fi

# --- 💾 MEMORY PRESSURE ---
echo -e "\n${BLUE}${BOLD}💾 MEMORY USAGE${NC}"
# kern.memorystatus_level = system-wide free memory % (same value memory_pressure prints)
MEM_FREE=$(sysctl -n kern.memorystatus_level 2>/dev/null || true)
if ! [[ "$MEM_FREE" =~ ^[0-9]+$ ]]; then
    MEM_FREE=$(memory_pressure 2>/dev/null | awk '/free percentage/ {gsub("%", "", $5); print $5}') || true
fi
if ! [[ "$MEM_FREE" =~ ^[0-9]+$ ]]; then
    MEM_FREE=0
    log_warn "Could not parse memory pressure output, showing 100% used."
fi
MEM_USED=$((100 - MEM_FREE))

echo -n "Pressure: "
if (( MEM_USED > 85 )); then
    echo -e "${RED}$(draw_bar "$MEM_USED")${NC} (High Pressure)"
elif (( MEM_USED > 70 )); then
    echo -e "${YELLOW}$(draw_bar "$MEM_USED")${NC} (Moderate)"
else
    echo -e "${GREEN}$(draw_bar "$MEM_USED")${NC} (Healthy)"
fi

# --- 💽 DISK STORAGE & CACHES ---
echo -e "\n${BLUE}${BOLD}💽 DISK STORAGE${NC}"
# On APFS, "/" is the sealed system snapshot; the Data volume reflects real usage
DISK_VOL="/System/Volumes/Data"
[[ -d "$DISK_VOL" ]] || DISK_VOL="/"
read -r _ TOTAL _ AVAIL DISK_USAGE _ <<<"$(df -h "$DISK_VOL" | awk 'NR==2')" || true
DISK_USAGE="${DISK_USAGE%\%}"
[[ "$DISK_USAGE" =~ ^[0-9]+$ ]] || DISK_USAGE=0

echo -n "System Disk: "
if (( DISK_USAGE > 85 )); then
    echo -e "${RED}$(draw_bar "$DISK_USAGE")${NC} - ${RED}Critical: Only $AVAIL left of $TOTAL${NC}"
elif (( DISK_USAGE > 75 )); then
    echo -e "${YELLOW}$(draw_bar "$DISK_USAGE")${NC} - ${YELLOW}Warning: $AVAIL left${NC}"
else
    echo -e "${GREEN}$(draw_bar "$DISK_USAGE")${NC} - $AVAIL left of $TOTAL"
fi

echo -e "\n${BOLD}Heavy Developer Caches:${NC}"
capture_get docker DOCKER_SIZE
capture_get ollama OLLAMA_SIZE
capture_get xcode  XCODE_SIZE
echo "  🐳 Docker Cache:      ${DOCKER_SIZE:-0B}"
echo "  🦙 Ollama Models:     ${OLLAMA_SIZE:-0B}"
echo "  🛠  Xcode DerivedData: ${XCODE_SIZE:-0B}"

# --- 🌐 NETWORK DIAGNOSTICS ---
echo -e "\n${BLUE}${BOLD}🌐 NETWORK INFO${NC}"
# Use the default route interface instead of hardcoding en0
DEFAULT_IF=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}') || true
IP=$(ipconfig getifaddr "${DEFAULT_IF:-en0}" 2>/dev/null || echo "")
echo "Interface:   ${DEFAULT_IF:-unknown}"
echo "Internal IP: ${IP:-Not Connected}"

# Actual ping latency (ICMP)
capture_get ping PING
if [[ -n "$PING" ]]; then
    if awk -v p="$PING" 'BEGIN {exit !(p > 150)}'; then
        echo -e "Ping Latency: ${YELLOW}${PING}ms ⚠️ (Elevated)${NC}"
    else
        echo -e "Ping Latency: ${GREEN}${PING}ms ✅${NC}"
    fi
else
    echo -e "Ping Latency: ${RED}Unreachable ❌${NC}"
fi

# Actual DNS resolution test
capture_get dns DNS_LATENCY
if [[ "$DNS_LATENCY" =~ ^[0-9]+$ ]]; then
    if (( DNS_LATENCY > 200 )); then
        echo -e "DNS Latency:  ${YELLOW}${DNS_LATENCY}ms ⚠️ (Slow)${NC}"
    else
        echo -e "DNS Latency:  ${GREEN}${DNS_LATENCY}ms ✅${NC}"
    fi
else
    DNS_LATENCY=""
    echo -e "DNS Latency:  ${RED}Could not resolve ❌${NC}"
fi

# --- 🔋 BATTERY HEALTH ---
echo -e "\n${BLUE}${BOLD}🔋 BATTERY STATUS${NC}"
BATT_RAW=$(pmset -g batt 2>/dev/null || true)
BATT_LEVEL="" BATT_STATUS=""
_re_level='([0-9]+)%'
_re_source="'([^']+)'"
[[ "$BATT_RAW" =~ $_re_level ]] && BATT_LEVEL="${BASH_REMATCH[1]}%"
[[ "$BATT_RAW" =~ $_re_source ]] && BATT_STATUS="${BASH_REMATCH[1]}"

capture_get power POWER_RAW
BATT_HEALTH="${POWER_RAW%%|*}"
BATT_CYCLES="${POWER_RAW#*|}"

echo "Charge Level:   ${BATT_LEVEL:-N/A} (${BATT_STATUS:-Unknown})"
echo "Maximum Health: ${BATT_HEALTH:-N/A}"
echo "Cycle Count:    ${BATT_CYCLES:-N/A}"

# --- 🌡️ THERMAL STATUS ---
echo -e "\n${BLUE}${BOLD}🌡️ THERMAL STATUS${NC}"
THERMAL=$(pmset -g therm 2>/dev/null | awk '/CPU_Scheduler_Limit/ {print $3}') || true
if [[ "$THERMAL" =~ ^[0-9]+$ ]] && (( THERMAL < 100 )); then
    echo -e "${RED}⚠️  CPU throttled to ${THERMAL}% — thermal pressure detected${NC}"
else
    THERMAL=100
    echo -e "${GREEN}✅ No thermal throttling${NC}"
fi

# --- 📊 TOP RESOURCE PROCESSES ---
echo -e "\n${BLUE}${BOLD}📊 TOP RESOURCE CONSUMERS${NC}"
echo -e "${BOLD}  Top CPU:${NC}"
ps -Arco pid,pcpu,comm 2>/dev/null | awk 'NR <= 4 {print "    " $0}' || true
echo -e "${BOLD}  Top Memory:${NC}"
ps -Amco pid,rss,comm 2>/dev/null | awk '
    NR == 1 {printf "    %6s %9s  %s\n", "PID", "MEM", "COMMAND"; next}
    NR <= 4 {pid = $1; rss = $2; $1 = $2 = ""; sub(/^ +/, "");
             printf "    %6s %8.0fM  %s\n", pid, rss / 1024, $0}' || true

# --- 🧾 RECENT ERRORS ---
echo -e "\n${BLUE}${BOLD}🧾 RECENT CRITICAL LOGS (Last 10m)${NC}"
capture_get logs CRITICAL_LOGS
if [[ -z "$CRITICAL_LOGS" ]]; then
    echo -e "  ${GREEN}No critical system panics detected.${NC}"
else
    echo "$CRITICAL_LOGS"
fi

echo -e "\n${GREEN}${BOLD}✅ Health Check Completed!${NC}\n"

# =====================================================================
# 🤖 LOCAL LLM INTERPRETATION VIA OLLAMA ($OLLAMA_MODEL)
# =====================================================================

# Normalise "llama3.1" -> "llama3.1:latest" to match `ollama list` output
[[ "$OLLAMA_MODEL" == *:* ]] || OLLAMA_MODEL="${OLLAMA_MODEL}:latest"

if [[ "$NO_AI" == "true" ]]; then
    log_info "AI analysis skipped (--no-ai)."
elif ! has ollama; then
    log_warn "Ollama is not installed. Skipping AI analysis."
elif ! OLLAMA_MODELS_LIST=$(ollama list 2>/dev/null); then
    log_warn "Ollama daemon is not running. Skipping AI analysis."
elif ! awk -v m="$OLLAMA_MODEL" 'NR > 1 && $1 == m {f = 1} END {exit !f}' <<<"$OLLAMA_MODELS_LIST"; then
    log_warn "Model '${OLLAMA_MODEL}' not found. Run: ollama pull ${OLLAMA_MODEL}"
else
    echo -e "${BLUE}${BOLD}🤖 Generating AI Diagnostic Interpretation (${OLLAMA_MODEL})...${NC}"
    echo "--------------------------------------------------------"

    SYSTEM_PROMPT="You are a senior macOS systems engineer. Review this system health data and provide a short, user-friendly summary. Use bullet points and address: 1. What happened (Current state), 2. How it happened (Triggers for any warnings), and 3. What to do (Specific terminal commands or actions to resolve issues). Be concise."

    METRICS="Disk Usage: ${DISK_USAGE:-N/A}%, Memory Pressure: ${MEM_USED:-N/A}%, 1m Load Average: ${LOAD:-N/A} on ${NCPU} cores, Ping Latency: ${PING:-N/A}ms, DNS Latency: ${DNS_LATENCY:-N/A}ms, Battery Health: ${BATT_HEALTH:-N/A}, Battery Cycles: ${BATT_CYCLES:-N/A}, Thermal Throttle: ${THERMAL:-100}%, Docker Cache Size: ${DOCKER_SIZE:-0B}, Ollama Models Size: ${OLLAMA_SIZE:-0B}, Xcode DerivedData: ${XCODE_SIZE:-0B}. Recent Errors: ${CRITICAL_LOGS:-None}."

    # Pass metrics and system prompt to Ollama
    ollama run "$OLLAMA_MODEL" "Analyze these metrics: $METRICS. $SYSTEM_PROMPT" || log_warn "Ollama analysis failed."

    echo "--------------------------------------------------------"
fi

echo -e "${BLUE}📝 Full log: ${LOG_FILE}${NC}"