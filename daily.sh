#!/bin/bash

# Daily maintenance tasks
# This script performs automated system maintenance including:
# - Network and VPN verification (WireGuard)
# - System health checks (ZFS, services, journal, packages)
# - Package updates and cache maintenance
# - ZFS backups (local and remote via syncoid)
# - Cloud synchronization (rclone bisync to Google Drive)


# =============================================================================
# Command Line Arguments
# =============================================================================

DRY_RUN=""

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Daily maintenance tasks for system upkeep.

Options:
  -n, --dry-run    Preview actions without making changes
                   Shows what would be done at each step
  -h, --help       Show this help message and exit

Execution steps:
  1. Network and VPN verification (WireGuard)
  2. System health checks (ZFS, services, journal)
  3. Package updates and cache maintenance
  4. ZFS backups (local and remote via syncoid)
  5. Cloud synchronization (rclone bisync)

Configuration:
  Edit settings.sh to configure backup targets and cloud syncs.
  See README.md for detailed documentation.

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run)
            DRY_RUN="dry-run"
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

# Prevent concurrent execution with a lock file
LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/daily-maintenance.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "Another instance of daily maintenance is already running." >&2
    exit 1
fi

# Log output to file and screen
LOG_FILE="/var/log/daily-maintenance.log"
if [ ! -f "$LOG_FILE" ]; then
    sudo touch "$LOG_FILE"
    sudo chown "$USER" "$LOG_FILE"
fi
exec > >(tee -a "$LOG_FILE") 2>&1

# Set the folder where dependencies can be found.
# This is needed when the script is run via a symbolic link.
daily_path=$(dirname "$(realpath "$0")")

# Helper function to safely source files
safe_source() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "ERROR: Required file not found: $file" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    . "$file"
}

# =============================================================================
# Load Modules
# =============================================================================

# Source machine-specific environment variables if env.sh exists
if [[ -f "${daily_path}/env.sh" ]]; then
    # shellcheck disable=SC1091
    . "${daily_path}/env.sh"
fi

# Load BUMP utility library (error handling, logging, cleanup)
safe_source "${daily_path}/bump/bump.sh"

# Settings for this script
safe_source "${daily_path}/settings.sh"

# Network and VPN management
safe_source "${daily_path}/network.sh"

# Systemd unit management and health checks
safe_source "${daily_path}/system.sh"

# Package updates and checks
safe_source "${daily_path}/package.sh"

# ZFS backup routines
safe_source "${daily_path}/backup.sh"

# Sensitive file detection and exclusion
safe_source "${daily_path}/sensitive.sh"

# Cloud synchronization via rclone
safe_source "${daily_path}/cloud.sh"

# =============================================================================
# Initialization
# =============================================================================

# Set up signal handler for graceful shutdown
trap handle_signal 1 2 3 6 15

# Set a stamp for use in messages and file names
set_stamp

# Announce dry-run mode if active
if [ -n "$DRY_RUN" ]; then
    log_message "*** DRY-RUN MODE - no changes will be made ***"
fi

# =============================================================================
# Verify Dependencies
# =============================================================================

# Mandatory system commands (script cannot function without these)
check_dependency "systemctl"
check_dependency "ufw"
check_dependency "ping"
check_dependency "ip"
check_dependency "zpool"
check_dependency "zfs"
check_dependency "pacman"
check_dependency "rfkill"
check_dependency "wg"
check_dependency "vpn"

# Optional custom scripts (warn but continue if missing)
if ! command -v zbackup &>/dev/null; then
    log_message "WARNING: zbackup not found - local ZFS backups will be skipped"
fi
if ! command -v rbackup &>/dev/null; then
    log_message "WARNING: rbackup not found - root backup will be skipped"
fi

# Required configuration
not_empty "wired interface (MAIN_WIRED)" "$MAIN_WIRED"
not_empty "wireless interface (MAIN_WIRELESS)" "$MAIN_WIRELESS"
not_empty "ZFS pool name (ZFS_POOL)" "$ZFS_POOL"
not_empty "user name (USER)" "$USER"

# =============================================================================
# Execution Flow
# =============================================================================

# Step 0: Prepare backup mounts (prompt for passphrases early)
if ! prepare_root_mount; then
    log_message "WARNING: prepare_root_mount failed - root backup will be skipped later"
fi

# Step 1: Network and VPN
# Verify network connectivity and ensure WireGuard VPN is active
network_check "$MAIN_WIRED" "$MAIN_WIRELESS" "$DRY_RUN"

# Step 2: System Checks
# Ensure critical systemd units are running
system_check "$DRY_RUN"

# Step 3: Health Checks
# Run ZFS health, scrub status, failed services, journal size, etc.
# Journal vacuum requires dry-run awareness
run_all_health_checks "$DRY_RUN"

# Step 4: Package Maintenance
# Update packages, clean caches, check for issues
if [ -n "$DRY_RUN" ]; then
    log_message "[DRY-RUN] skipping package maintenance"
else
    run_package_maintenance
fi

# Step 5: Backups
# Run ZFS local backups, root backup, and syncoid replication
run_all_backups "$DRY_RUN"

# Step 6: Cloud Synchronization
# Sync configured directories to cloud storage via rclone
run_all_cloud_syncs "$DRY_RUN"

# =============================================================================
# Cleanup and Exit
# =============================================================================

cleanup 0
