# macOS Pro Scripts

A collection of advanced, AI-enhanced bash scripts designed to automate maintenance, health diagnostics, and system upgrades on macOS (especially optimized for Apple Silicon / M-Series Macs).

## Scripts Overview

This repository includes three primary scripts, each targeting a specific aspect of system maintenance and observability:

### 1. `mac_health_check.sh`
**Advanced macOS Health Check (AI Enhanced)**
Provides a comprehensive diagnostic overview of your Mac's health with visual progress bars and an AI-driven summary.
- **Metrics Checked:** CPU & System Load, Memory Pressure, Disk Storage (including developer caches like Docker and Ollama), Network Diagnostics (Internal IP, DNS Latency), Battery Health & Cycles, and Recent Critical System Errors (Panics/Fatal logs).
- **AI Integration:** Uses a local LLM via Ollama (`llama3.1:latest`) to analyze metrics and provide a concise, actionable interpretation of the system's state without sending data to the cloud.

### 2. `cleanup.sh`
**macOS Pro-Cleanup & Maintenance**
A deep system cleaner specifically targeting developer bloat to reclaim disk space safely.
- **Cleans:** Docker containers and unused volumes, Python/Pip caches, Xcode DerivedData, NPM/Bun/Yarn caches, Homebrew cache, and safely flushes System/User caches.
- **Reporting:** Displays total gigabytes reclaimed after the cleanup.

### 3. `omni-upgrade.sh`
**macOS Omni-Upgrade Script**
A one-click global upgrade utility for your package managers and system software.
- **Upgrades:** Homebrew packages & casks, Mac App Store apps, global Pip packages, global NPM packages, and checks for macOS System Updates.

## Prerequisites

To get the most out of these scripts, ensure you have the following optional tools installed:
- **[Homebrew](https://brew.sh/):** Required for package management updates in `omni-upgrade.sh`.
- **[Ollama](https://ollama.com/):** Required for the AI-enhanced diagnostics in `mac_health_check.sh` (requires the `llama3.1` model downloaded: `ollama pull llama3.1`).
- **[mas-cli](https://github.com/mas-cli/mas):** Required for updating Mac App Store apps via `omni-upgrade.sh` (install with `brew install mas`).

## Usage

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd mac-scripts
   ```

2. **Make the scripts executable:**
   ```bash
   chmod +x *.sh
   ```

3. **Run a script:**
   ```bash
   ./mac_health_check.sh
   # or
   ./cleanup.sh
   # or
   ./omni-upgrade.sh
   ```

## License

This project is open-source. Feel free to fork, modify, and improve to fit your workflow!
