#!/bin/bash
##  ZFS send/receive backup to external drives
#
#   Usage:
#     zbackup [--config CONFIG_FILE]
#
#   This script backs up ZFS datasets to an external backup pool using
#   ZFS send/receive with mbuffer for buffering. It handles drive
#   detection, pool import/export, encryption keys, and incremental
#   or initial backups automatically.
#
#   Configuration files in backup-configs/ define the backup pool,
#   source datasets, drive ID, and log file for each target.

set -uo pipefail  # Remove -e to handle errors gracefully

# Resolve the actual script location, following symbolic links
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"

# Source machine-specific environment variables if env.sh exists
if [[ -f "${SCRIPT_DIR}/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/env.sh"
fi

# Source BUMP library
# shellcheck source=bump/bump.sh
source "${SCRIPT_DIR}/bump/bump.sh"

# Default configuration directory
CONFIG_DIR="${SCRIPT_DIR}/backup-configs"

# Configuration variables (set by --config file, no defaults)
BACKUP_POOL=""
BACKUP_PATH=""
SOURCE_DATASETS=()
BACKUP_DRIVE_ID=""
LOG_FILE=""

# Logging function - writes to stderr (via BUMP), log file, and syslog
log() {
    local message="$*"
    log_message "$message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $message" | sudo tee -a "$LOG_FILE" >/dev/null
    logger -t zfs-backup "$message"
}

# Check if backup drive is connected
check_backup_drive() {
    if [ ! -e "/dev/disk/by-id/$BACKUP_DRIVE_ID" ]; then
        log "ERROR: Backup drive not connected"
        cleanup "$MISSING_DISK"
    fi

    # Try to import pool if not already imported
    if ! zpool list "$BACKUP_POOL" >/dev/null 2>&1; then
        log "Importing backup pool..."
        if ! sudo zpool import -d /dev/disk/by-id "$BACKUP_POOL"; then
            log "ERROR: Failed to import backup pool"
            cleanup "$MISSING_DISK"
        fi
        sudo zfs load-key -a 2>/dev/null
    fi

    # Check if encryption keys are loaded for the backup pool
    local keystatus
    keystatus=$(sudo zfs get -H -o value keystatus "$BACKUP_POOL" 2>/dev/null)
    if [ "$keystatus" = "unavailable" ]; then
        log "Encryption key required for $BACKUP_POOL"
        if ! sudo zfs load-key "$BACKUP_POOL"; then
            log "ERROR: Failed to load encryption key for $BACKUP_POOL"
            cleanup "$SECURITY_FAILURE"
        fi
    fi
}

# Find the most recent common snapshot between source and backup
find_common_snapshot() {
    local source_dataset="$1"
    local backup_dataset="$2"

    # Get all snapshots from both datasets
    local source_snaps
    source_snaps=$(zfs list -t snapshot -H -o name "$source_dataset" 2>/dev/null | cut -d@ -f2 | sort -r)
    local backup_snaps
    backup_snaps=$(zfs list -t snapshot -H -o name "$backup_dataset" 2>/dev/null | cut -d@ -f2 | sort -r)

    # Find the most recent common snapshot
    for backup_snap in $backup_snaps; do
        for source_snap in $source_snaps; do
            if [ "$backup_snap" = "$source_snap" ]; then
                echo "$backup_snap"
                return 0
            fi
        done
    done

    return 1
}

# Ensure parent datasets exist in backup pool
ensure_parent_datasets() {
    local backup_dataset="$1"
    local parent=""

    # Split the dataset path and create each parent level if needed
    IFS='/' read -ra PARTS <<< "$backup_dataset"

    for ((i=0; i<${#PARTS[@]}-1; i++)); do
        if [ -z "$parent" ]; then
            parent="${PARTS[$i]}"
        else
            parent="${parent}/${PARTS[$i]}"
        fi

        # Skip the pool name itself
        if [ "$parent" = "$BACKUP_POOL" ]; then
            continue
        fi

        # Create parent dataset if it doesn't exist
        if ! zfs list "$parent" >/dev/null 2>&1; then
            log "Creating parent dataset: $parent"
            if ! sudo zfs create -p "$parent"; then
                log "ERROR: Failed to create parent dataset $parent"
                return "$FILING_ERROR"
            fi
        fi
    done

    return 0
}

# Main backup function
perform_backup() {
    local failed_datasets=()
    local successful_datasets=()

    for dataset in "${SOURCE_DATASETS[@]}"; do
        local backup_dataset="${BACKUP_POOL}/${BACKUP_PATH}/${dataset#*/}"

        # Check if source dataset exists
        if ! zfs list "$dataset" >/dev/null 2>&1; then
            log "WARNING: Source dataset $dataset does not exist, skipping"
            failed_datasets+=("$dataset")
            continue
        fi

        # Get latest snapshot from source
        local latest_snap
        latest_snap=$(zfs list -t snapshot -H -o name "$dataset" 2>/dev/null | tail -1 | cut -d@ -f2)

        if [ -z "$latest_snap" ]; then
            log "WARNING: No snapshots found for $dataset"
            failed_datasets+=("$dataset")
            continue
        fi

        # Check if initial or incremental backup
        if ! zfs list "$backup_dataset" >/dev/null 2>&1; then
            # Ensure parent datasets exist
            if ! ensure_parent_datasets "$backup_dataset"; then
                log "ERROR: Failed to create parent datasets for $backup_dataset"
                failed_datasets+=("$dataset")
                continue
            fi

            log "Performing initial backup of $dataset@$latest_snap"
            if sudo zfs send -v "${dataset}@${latest_snap}" | \
                mbuffer -s 128k -m 1G -q | \
                sudo zfs receive -F "$backup_dataset"; then
                successful_datasets+=("$dataset")
            else
                log "ERROR: Failed to backup $dataset"
                failed_datasets+=("$dataset")
            fi
        else
            # Check if backup is already up to date
            local last_backup_snap
            last_backup_snap=$(zfs list -t snapshot -H -o name "$backup_dataset" 2>/dev/null | tail -1 | cut -d@ -f2)

            if [ "$last_backup_snap" = "$latest_snap" ]; then
                log "Backup dataset $backup_dataset already up to date with @${latest_snap}"
                successful_datasets+=("$dataset")
                continue
            fi

            # Find the most recent common snapshot
            local common_snap
            common_snap=$(find_common_snapshot "$dataset" "$backup_dataset")

            if [ -n "$common_snap" ]; then
                log "Performing incremental backup of $dataset from @${common_snap} to @${latest_snap}"
                if sudo zfs send -vi "${dataset}@${common_snap}" "${dataset}@${latest_snap}" | \
                    mbuffer -s 128k -m 1G -q | \
                    sudo zfs receive -F "$backup_dataset"; then
                    successful_datasets+=("$dataset")
                else
                    log "ERROR: Failed to backup $dataset"
                    failed_datasets+=("$dataset")
                fi
            else
                log "WARNING: No common snapshot found between source and backup for $dataset"
                log "Performing full replication (destroying existing backup snapshots)"

                # List existing snapshots for logging
                local existing_snaps
                existing_snaps=$(zfs list -t snapshot -H -o name "$backup_dataset" 2>/dev/null | wc -l)
                log "Will destroy $existing_snaps existing snapshots in $backup_dataset"

                # Destroy the backup dataset and recreate with full send
                if sudo zfs destroy -r "$backup_dataset" 2>/dev/null; then
                    log "Destroyed existing backup dataset $backup_dataset"
                fi

                # Ensure parent datasets exist after destroying
                if ! ensure_parent_datasets "$backup_dataset"; then
                    log "ERROR: Failed to create parent datasets for $backup_dataset"
                    failed_datasets+=("$dataset")
                    continue
                fi

                if sudo zfs send -v "${dataset}@${latest_snap}" | \
                    mbuffer -s 128k -m 1G -q | \
                    sudo zfs receive -F "$backup_dataset"; then
                    successful_datasets+=("$dataset")
                else
                    log "ERROR: Failed to backup $dataset"
                    failed_datasets+=("$dataset")
                fi
            fi
        fi
    done

    # Report summary
    log "Backup summary:"
    log "  Successful: ${#successful_datasets[@]} datasets"
    for ds in "${successful_datasets[@]}"; do
        log "    ok $ds"
    done
    if [ ${#failed_datasets[@]} -gt 0 ]; then
        log "  Failed: ${#failed_datasets[@]} datasets"
        for ds in "${failed_datasets[@]}"; do
            log "    FAILED $ds"
        done
    fi
}

# Sync snapshots - remove orphaned snapshots from backup
sync_snapshots() {
    for dataset in "${SOURCE_DATASETS[@]}"; do
        local backup_dataset="${BACKUP_POOL}/${BACKUP_PATH}/${dataset#*/}"

        # Skip if source dataset doesn't exist
        if ! zfs list "$dataset" >/dev/null 2>&1; then
            continue
        fi

        # Skip if backup dataset doesn't exist yet
        if ! zfs list "$backup_dataset" >/dev/null 2>&1; then
            continue
        fi

        # Get snapshot lists
        local source_snaps
        source_snaps=$(zfs list -t snapshot -H -o name "$dataset" 2>/dev/null | cut -d@ -f2 | sort)
        local backup_snaps
        backup_snaps=$(zfs list -t snapshot -H -o name "$backup_dataset" 2>/dev/null | cut -d@ -f2 | sort)

        # Find snapshots that exist in backup but not in source
        local orphaned_snaps
        orphaned_snaps=$(comm -13 <(echo "$source_snaps") <(echo "$backup_snaps"))

        # Remove orphaned snapshots
        while IFS= read -r snap; do
            if [ -n "$snap" ]; then
                log "Removing orphaned snapshot: ${backup_dataset}@${snap}"
                sudo zfs destroy "${backup_dataset}@${snap}" || log "WARNING: Failed to destroy ${backup_dataset}@${snap}"
            fi
        done <<< "$orphaned_snaps"
    done
}

# Export pool safely (BUMP cleanup function)
cleanup_export_backup_pool() {
    if zpool list "$BACKUP_POOL" >/dev/null 2>&1; then
        log_message "Exporting backup pool ${BACKUP_POOL}..."
        sync
        sudo zpool export "$BACKUP_POOL" || sudo zpool export -f "$BACKUP_POOL"
    fi
}

# Main function - parse args, load config, run backup
main() {
    set_stamp

    # Parse command line arguments
    local config_file=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config|-c)
                config_file="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 --config CONFIG_NAME"
                echo "  --config, -c    Config file path or name (looks in ${CONFIG_DIR}/)"
                echo "  --help, -h      Show this help message"
                echo ""
                echo "A config file is required. Each config sets BACKUP_POOL,"
                echo "BACKUP_PATH, SOURCE_DATASETS, BACKUP_DRIVE_ID, and LOG_FILE."
                echo ""
                echo "Examples:"
                echo "  $0 --config mypool        # Use ${CONFIG_DIR}/mypool.conf"
                echo "  $0 --config mypool.conf   # Use ${CONFIG_DIR}/mypool.conf"
                echo "  $0 --config /path/to/custom.conf  # Use custom path"
                echo ""
                echo "Available configs in ${CONFIG_DIR}/:"
                if [ -d "$CONFIG_DIR" ]; then
                    for conf in "$CONFIG_DIR"/*.conf; do
                        [ -f "$conf" ] && echo "  - $(basename "$conf")"
                    done
                fi
                exit 0
                ;;
            *)
                log_message "Unknown option: $1"
                log_message "Use --help for usage information"
                cleanup "$BAD_CONFIGURATION"
                ;;
        esac
    done

    # A config file is required
    if [ -z "$config_file" ]; then
        log_message "No configuration specified. Use --config <name> or --help."
        cleanup "$BAD_CONFIGURATION"
    fi

    # Load configuration file
    # Check if it's just a filename (no path separators)
    if [[ ! "$config_file" =~ / ]]; then
        # Look for the file in the config directory
        if [ -f "${CONFIG_DIR}/${config_file}" ]; then
            config_file="${CONFIG_DIR}/${config_file}"
        elif [ -f "${CONFIG_DIR}/${config_file}.conf" ]; then
            config_file="${CONFIG_DIR}/${config_file}.conf"
        fi
    else
        # Full path provided - check if .conf needs to be added
        if [ ! -f "$config_file" ] && [ -f "${config_file}.conf" ]; then
            config_file="${config_file}.conf"
        fi
    fi

    if [ ! -f "$config_file" ]; then
        log_message "Configuration file not found: $config_file"
        log_message "Looked in: ${CONFIG_DIR}/"
        cleanup "$MISSING_FILE"
    fi

    # Source the configuration file
    # shellcheck source=/dev/null
    source "$config_file"

    # Set log file from pool name if not explicitly set in config
    if [ -z "$LOG_FILE" ]; then
        LOG_FILE="/var/log/zfs-backup-${BACKUP_POOL}.log"
    fi

    log_message "Loaded configuration from: $config_file"

    # Log configuration
    log_setting "backup pool" "$BACKUP_POOL"
    log_setting "backup path" "$BACKUP_PATH"
    log_setting "log file" "$LOG_FILE"
    log_setting "drive ID" "$BACKUP_DRIVE_ID"

    # Register cleanup and signal handling
    cleanup_functions+=("cleanup_export_backup_pool")
    trap handle_signal 1 2 3 6 15

    # Run backup
    log "Start the ZFS backup process."
    check_backup_drive
    perform_backup
    # Use sanoid to trim snapshots in the backup pool
    # sync_snapshots
    log "Backup completed successfully."

    cleanup 0
}

# Only run main when executed directly (not when sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
