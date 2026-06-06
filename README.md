# macOS Pro Scripts (v2.0)

A collection of advanced, AI-enhanced bash scripts designed to automate maintenance, health diagnostics, and system upgrades on macOS (especially optimized for Apple Silicon / M-Series Macs).

## Features (v2.0)

- 🛡️ **Fail-safe**: All scripts use `set -euo pipefail` with error trapping
- 📝 **Auto-logging**: Every run is logged to `~/.mac-scripts/logs/`
- 🔍 **Dry-run mode**: Preview destructive actions before committing (`--dry-run`)
- 🧩 **Shared library**: Common utilities in `lib/common.sh` — no code duplication
- ❓ **Self-documenting**: Every script supports `--help`

## Scripts Overview

### 1. `mac_health_check.sh`
**Advanced macOS Health Check (AI Enhanced)**
Provides a comprehensive diagnostic overview of your Mac's health with visual progress bars and an AI-driven summary.
- **Metrics Checked:** CPU & System Load, Memory Pressure, Disk Storage (including developer caches like Docker, Ollama, and Xcode), Network Diagnostics (auto-detected interface, ICMP ping, DNS latency), Battery Health & Cycles, **Thermal Throttling Status**, **Top CPU & Memory Processes**, and Recent Critical System Errors (Panics/Fatal logs).
- **AI Integration:** Uses a local LLM via Ollama (`llama3.1:latest`) to analyze metrics and provide a concise, actionable interpretation of the system's state without sending data to the cloud.

### 2. `cleanup.sh`
**macOS Pro-Cleanup & Maintenance**
A deep system cleaner specifically targeting developer bloat to reclaim disk space safely.
- **Cleans:** Docker containers and unused volumes, Python/Pip caches, Xcode DerivedData, NPM/Bun/Yarn caches, CocoaPods, Gradle, Go module cache, Rust/Cargo cache, Homebrew cache, and safely flushes System/User caches.
- **Safety:** Prompts for confirmation before clearing system caches. Supports `--dry-run` to preview all actions.
- **Reporting:** Displays total gigabytes reclaimed and per-section size information.

### 3. `omni-upgrade.sh`
**macOS Omni-Upgrade Script**
A one-click global upgrade utility for your package managers and system software.
- **Upgrades:** Homebrew packages & casks, Mac App Store apps, Pip, NPM, **Bun**, **uv**, and checks for macOS System Updates.
- **Change Tracking:** Shows a before/after diff of all Homebrew package changes.

### 4. `lib/common.sh`
**Shared Helper Library**
Sourced by all scripts. Provides:
- Color and style constants
- `set -euo pipefail` and error trap
- Auto-logging to `~/.mac-scripts/logs/`
- `--dry-run` and `--help` argument parsing
- `safe_rm` / `safe_exec` / `confirm_action` helpers
- `require_macos` platform guard

## Prerequisites

To get the most out of these scripts, ensure you have the following optional tools installed:
- **[Homebrew](https://brew.sh/):** Required for package management updates in `omni-upgrade.sh`.
- **[Ollama](https://ollama.com/):** Required for the AI-enhanced diagnostics in `mac_health_check.sh` (requires the `llama3.1` model downloaded: `ollama pull llama3.1`).
- **[mas-cli](https://github.com/mas-cli/mas):** Required for updating Mac App Store apps via `omni-upgrade.sh` (install with `brew install mas`).

## Usage

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Arif-Badhon/mac-scripts.git
   cd mac-scripts
   ```

2. **Make the scripts executable:**
   ```bash
   chmod +x *.sh lib/*.sh
   ```

3. **Run a script:**
   ```bash
   ./mac_health_check.sh           # Full health check
   ./cleanup.sh                    # Deep cleanup
   ./cleanup.sh --dry-run          # Preview cleanup (no deletions)
   ./omni-upgrade.sh               # Upgrade everything
   ./omni-upgrade.sh --dry-run     # Preview upgrades
   ```

4. **View logs:**
   ```bash
   ls ~/.mac-scripts/logs/
   ```

## License

This project is open-source. Feel free to fork, modify, and improve to fit your workflow!
