#!/bin/bash
##  Run ZFS and root filesystem backups

##  Settings
#   STAMP               should be set by a call to set_stamp in bump.sh
#   ZFS_BACKUP_TARGETS  array of zbackup config names
#   SYNCOID_TARGETS     array of source datasets to replicate
#   SYNCOID_REMOTE_HOST remote host for syncoid replication
#   SYNCOID_REMOTE_POOL destination pool on remote host
#   BACKUP_CONFIGS_DIR  directory containing backup configuration files
#   SSH_TIMEOUT         timeout for SSH connectivity checks

##  Dependencies
#   return_codes.sh
#   settings.sh
#   bump.sh
#   network.sh (for check_host_reachable)

##  Notes
#   Local ZFS backups use the zbackup script for ZFS send/receive
#   Remote ZFS replication uses syncoid (part of sanoid package)
#   Root filesystem backup uses rbackup script for rsync to /mnt/root

# =============================================================================
#   DRIVE DETECTION
# =============================================================================

function check_drive_connected {
    # Check if a drive is connected by its disk ID
    #
    # Arguments:
    #   $1 - Drive ID (as found in /dev/disk/by-id/)
    #
    # Returns:
    #   0 - Drive is connected
    #   1 - Drive is not connected
    #
    # Example:
    #   check_drive_connected "usb-My_Drive_Model_Serial-0:0"

    local cdc_drive_id=$1

    if [ -z "$cdc_drive_id" ]; then
        log_message "check_drive_connected: no drive ID specified"
        return 1
    fi

    if [ -e "/dev/disk/by-id/${cdc_drive_id}" ]; then
        log_message "drive ${cdc_drive_id} is connected"
        return 0
    else
        log_message "drive ${cdc_drive_id} is not connected"
        return 1
    fi
}

# =============================================================================
#   LOCAL ZFS BACKUP FUNCTIONS
# =============================================================================

function run_zfs_local_backup {
    # Run a local ZFS backup using the zbackup script
    #
    # Arguments:
    #   $1 - Config name (matching a file in backup-configs/) - zbackup resolves the path
    #   $2 - (optional) "dry-run" to preview without making changes
    #
    # Returns:
    #   0 - Backup completed successfully
    #   Non-zero - Backup failed or skipped

    local rzlb_config="${1:-}"
    local rzlb_dry_run="${2:-}"
    local rzlb_dry_prefix=""
    if [ "$rzlb_dry_run" = "dry-run" ]; then
        rzlb_dry_prefix="[DRY-RUN] "
    fi

    not_empty "zbackup config name" "$rzlb_config"

    log_message "${rzlb_dry_prefix}run_zfs_local_backup ${rzlb_config}"

    log_setting "zbackup config" "$rzlb_config"

    # Check if zbackup command exists
    if ! command -v zbackup &>/dev/null; then
        report "$MISSING_FILE" "zbackup command not found in PATH"
        return "$MISSING_FILE"
    fi

    # Dry-run mode: show what would be done
    if [ "$rzlb_dry_run" = "dry-run" ]; then
        log_message "[DRY-RUN] would run: zbackup --config ${rzlb_config}"
        return 0
    fi

    # Run zbackup - it handles drive detection and pool import/export
    zbackup --config "$rzlb_config" || {
        local rc=$?
        report "$rc" "zbackup failed for ${rzlb_config}"
        return "$rc"
    }

    log_message "zbackup completed for ${rzlb_config}"
    return 0
}

function run_all_zfs_local_backups {
    # Run all configured local ZFS backups
    # Iterates through ZFS_BACKUP_TARGETS array
    #
    # Arguments:
    #   $1 - (optional) "dry-run" to preview without making changes
    #
    # Format of ZFS_BACKUP_TARGETS entries:
    #   Config names matching files in backup-configs/ - zbackup handles the rest

    local razlb_dry_run="${1:-}"
    local razlb_dry_prefix=""
    if [ "$razlb_dry_run" = "dry-run" ]; then
        razlb_dry_prefix="[DRY-RUN] "
    fi

    log_message "${razlb_dry_prefix}run_all_zfs_local_backups"

    if [ ${#ZFS_BACKUP_TARGETS[@]} -eq 0 ]; then
        log_message "${razlb_dry_prefix}no ZFS backup targets configured"
        return 0
    fi

    local razlb_failed=0

    for config in "${ZFS_BACKUP_TARGETS[@]}"; do
        log_message "processing ZFS backup target: ${config}"

        if ! run_zfs_local_backup "$config" "$razlb_dry_run"; then
            razlb_failed=$((razlb_failed + 1))
        fi
    done

    if [ "$razlb_failed" -gt 0 ]; then
        log_message "${razlb_failed} ZFS backup(s) failed"
    fi

    return 0  # Don't fail the whole run for individual failures
}

# =============================================================================
#   SYNCOID REPLICATION FUNCTIONS
# =============================================================================

function run_syncoid_replication {
    # Run syncoid replication to a remote host
    #
    # Arguments:
    #   $1 - Source dataset (e.g., "pool/data")
    #   $2 - Destination in user@host:dataset format
    #   $3 - (optional) "dry-run" to preview without making changes
    #
    # Returns:
    #   0 - Replication completed successfully
    #   Non-zero - Replication failed or skipped

    local rsr_source="${1:-}"
    local rsr_dest="${2:-}"
    local rsr_dry_run="${3:-}"
    local rsr_dry_prefix=""
    if [ "$rsr_dry_run" = "dry-run" ]; then
        rsr_dry_prefix="[DRY-RUN] "
    fi

    not_empty "syncoid source" "$rsr_source"
    not_empty "syncoid destination" "$rsr_dest"

    log_message "${rsr_dry_prefix}run_syncoid_replication"

    log_setting "syncoid source" "$rsr_source"
    log_setting "syncoid destination" "$rsr_dest"

    # Check if syncoid command exists
    if ! command -v syncoid &>/dev/null; then
        report "$MISSING_FILE" "syncoid command not found (install sanoid package)"
        return "$MISSING_FILE"
    fi

    # Parse destination to extract host
    local rsr_host="${rsr_dest%%:*}"

    # Check if host is reachable
    if ! check_host_reachable "$rsr_host"; then
        log_message "skipping replication - host ${rsr_host} not reachable"
        return 0  # Not an error, just skipped
    fi

    # Dry-run mode: show what would be done (syncoid has no dry-run option)
    if [ "$rsr_dry_run" = "dry-run" ]; then
        log_message "[DRY-RUN] would run: syncoid ${rsr_source} ${rsr_dest}"
        return 0
    fi

    # Run syncoid (uses sudo on both local and remote for ZFS operations)
    # --quiet suppresses progress bars (which are imprecise for small sends)
    syncoid --quiet "$rsr_source" "$rsr_dest" || {
        local rc=$?
        report "$rc" "syncoid replication failed: ${rsr_source} -> ${rsr_dest}"
        return "$rc"
    }

    log_message "syncoid completed: ${rsr_source} -> ${rsr_dest}"
    return 0
}

function run_all_syncoid_backups {
    # Run all configured syncoid replications
    # Iterates through SYNCOID_TARGETS array
    #
    # Arguments:
    #   $1 - (optional) "dry-run" to preview without making changes
    #
    # Uses settings:
    #   SYNCOID_REMOTE_HOST - remote host (SSH config entry)
    #   SYNCOID_REMOTE_POOL - destination pool on remote
    #   SYNCOID_TARGETS     - array of source datasets to replicate

    local rasb_dry_run="${1:-}"
    local rasb_dry_prefix=""
    if [ "$rasb_dry_run" = "dry-run" ]; then
        rasb_dry_prefix="[DRY-RUN] "
    fi

    log_message "${rasb_dry_prefix}run_all_syncoid_backups"

    if [ ${#SYNCOID_TARGETS[@]} -eq 0 ]; then
        log_message "${rasb_dry_prefix}no syncoid targets configured"
        return 0
    fi

    if [ -z "${SYNCOID_REMOTE_HOST:-}" ]; then
        log_message "SYNCOID_REMOTE_HOST not configured"
        return 1
    fi

    if [ -z "${SYNCOID_REMOTE_POOL:-}" ]; then
        log_message "SYNCOID_REMOTE_POOL not configured"
        return 1
    fi

    log_setting "syncoid remote host" "$SYNCOID_REMOTE_HOST"
    log_setting "syncoid remote pool" "$SYNCOID_REMOTE_POOL"

    local rasb_failed=0

    for source in "${SYNCOID_TARGETS[@]}"; do
        # Construct destination: host:pool/source_path
        local dest="${SYNCOID_REMOTE_HOST}:${SYNCOID_REMOTE_POOL}/${source}"

        log_message "processing syncoid target: ${source} -> ${dest}"

        if ! run_syncoid_replication "$source" "$dest" "$rasb_dry_run"; then
            rasb_failed=$((rasb_failed + 1))
        fi
    done

    if [ "$rasb_failed" -gt 0 ]; then
        log_message "${rasb_failed} syncoid replication(s) failed"
    fi

    return 0  # Don't fail the whole run for individual failures
}

# =============================================================================
#   ROOT FILESYSTEM BACKUP
# =============================================================================

function prepare_root_mount {
    # Ensure /mnt/root is available by importing ROOT_BACKUP_POOL if needed
    # ROOT_BACKUP_DATASET is mounted at /mnt/root
    #
    # Requires (from settings.sh / env.sh):
    #   ROOT_BACKUP_POOL     - pool name to import
    #   ROOT_BACKUP_CONFIG   - config file name in backup-configs/ for drive ID
    #   ROOT_BACKUP_DATASET  - full dataset path to mount at /mnt/root
    #
    # Returns:
    #   0 - /mnt/root is mounted (or was successfully mounted)
    #   1 - Could not mount /mnt/root or root backup not configured

    log_message "prepare_root_mount: ROOT_BACKUP_POOL=${ROOT_BACKUP_POOL:-<unset>}" \
                "ROOT_BACKUP_CONFIG=${ROOT_BACKUP_CONFIG:-<unset>}" \
                "ROOT_BACKUP_DATASET=${ROOT_BACKUP_DATASET:-<unset>}"

    # Check that root backup is configured
    if [ -z "${ROOT_BACKUP_POOL:-}" ] || [ -z "${ROOT_BACKUP_DATASET:-}" ]; then
        log_message "prepare_root_mount: FAILED - root backup not configured" \
                    "(ROOT_BACKUP_POOL or ROOT_BACKUP_DATASET is empty)"
        return 1
    fi

    # Already mounted - nothing to do
    if mountpoint -q /mnt/root 2>/dev/null; then
        log_message "prepare_root_mount: /mnt/root is already mounted"
        return 0
    fi

    log_message "prepare_root_mount: /mnt/root is not currently mounted"

    # Check if root backup pool is imported
    if zpool list "$ROOT_BACKUP_POOL" >/dev/null 2>&1; then
        log_message "prepare_root_mount: pool ${ROOT_BACKUP_POOL} is already imported"
    else
        log_message "prepare_root_mount: pool ${ROOT_BACKUP_POOL} is not imported, looking for drive"

        # Find the config to get drive ID
        local prm_config_file="${BACKUP_CONFIGS_DIR}/${ROOT_BACKUP_CONFIG:-${ROOT_BACKUP_POOL}}.conf"

        if [ ! -f "$prm_config_file" ]; then
            log_message "prepare_root_mount: FAILED - config file not found: ${prm_config_file}"
            return 1
        fi

        # Read drive ID from config (avoid sourcing to not clobber variables)
        local prm_drive_id
        prm_drive_id=$(grep '^BACKUP_DRIVE_ID=' "$prm_config_file" | cut -d'"' -f2)

        if [ -z "$prm_drive_id" ]; then
            log_message "prepare_root_mount: FAILED - no BACKUP_DRIVE_ID in ${prm_config_file}"
            return 1
        fi

        if [ ! -e "/dev/disk/by-id/${prm_drive_id}" ]; then
            log_message "prepare_root_mount: FAILED - drive not connected:" \
                        "/dev/disk/by-id/${prm_drive_id} does not exist"
            return 1
        fi

        log_message "prepare_root_mount: drive found at /dev/disk/by-id/${prm_drive_id}"
        log_message "prepare_root_mount: importing ${ROOT_BACKUP_POOL}..."
        if ! sudo zpool import -d /dev/disk/by-id "$ROOT_BACKUP_POOL"; then
            log_message "prepare_root_mount: FAILED - zpool import returned non-zero"
            return 1
        fi
        log_message "prepare_root_mount: pool ${ROOT_BACKUP_POOL} imported successfully"
    fi

    # Load encryption keys if needed
    local prm_keystatus
    prm_keystatus=$(sudo zfs get -H -o value keystatus "$ROOT_BACKUP_POOL" 2>/dev/null)
    log_message "prepare_root_mount: keystatus for ${ROOT_BACKUP_POOL} is ${prm_keystatus:-<unknown>}"
    if [ "$prm_keystatus" = "unavailable" ]; then
        log_message "prepare_root_mount: loading encryption key for ${ROOT_BACKUP_POOL}..."
        if ! sudo zfs load-key "$ROOT_BACKUP_POOL"; then
            log_message "prepare_root_mount: FAILED - zfs load-key returned non-zero"
            return 1
        fi
        log_message "prepare_root_mount: encryption key loaded for ${ROOT_BACKUP_POOL}"
    fi

    # Mount /mnt/root
    if ! mountpoint -q /mnt/root 2>/dev/null; then
        log_message "prepare_root_mount: mounting ${ROOT_BACKUP_DATASET} at /mnt/root..."
        if ! sudo zfs mount "$ROOT_BACKUP_DATASET"; then
            log_message "prepare_root_mount: FAILED - zfs mount ${ROOT_BACKUP_DATASET} returned non-zero"
            return 1
        fi
    fi

    if mountpoint -q /mnt/root 2>/dev/null; then
        log_message "prepare_root_mount: SUCCESS - /mnt/root is ready"
        return 0
    fi

    log_message "prepare_root_mount: FAILED - /mnt/root is still not a mountpoint" \
                "after all steps completed without error"
    return 1
}

function run_root_backup {
    # Run root filesystem backup using rbackup script
    # Backs up root filesystem to /mnt/root on ZFS
    #
    # Arguments:
    #   $1 - (optional) "dry-run" to preview without making changes
    #
    # Returns:
    #   0 - Backup completed successfully
    #   Non-zero - Backup failed or skipped

    local rrb_dry_run="${1:-}"
    local rrb_dry_prefix=""
    if [ "$rrb_dry_run" = "dry-run" ]; then
        rrb_dry_prefix="[DRY-RUN] "
    fi

    log_message "${rrb_dry_prefix}run_root_backup"

    # Check if rbackup command exists
    if ! command -v rbackup &>/dev/null; then
        report "$MISSING_FILE" "rbackup command not found in PATH"
        return "$MISSING_FILE"
    fi

    # Check if /mnt/root is mounted
    if ! mountpoint -q /mnt/root 2>/dev/null; then
        local rrb_pool_state="not imported"
        if zpool list "${ROOT_BACKUP_POOL:-}" >/dev/null 2>&1; then
            rrb_pool_state="imported"
            local rrb_keystatus
            rrb_keystatus=$(sudo zfs get -H -o value keystatus "${ROOT_BACKUP_POOL}" 2>/dev/null)
            rrb_pool_state="${rrb_pool_state}, keystatus=${rrb_keystatus:-unknown}"
            local rrb_mountpoint
            rrb_mountpoint=$(sudo zfs get -H -o value mountpoint "${ROOT_BACKUP_DATASET:-}" 2>/dev/null)
            local rrb_mounted
            rrb_mounted=$(sudo zfs get -H -o value mounted "${ROOT_BACKUP_DATASET:-}" 2>/dev/null)
            rrb_pool_state="${rrb_pool_state}, dataset mountpoint=${rrb_mountpoint:-unknown}, mounted=${rrb_mounted:-unknown}"
        fi
        log_message "run_root_backup: SKIPPED - /mnt/root is not mounted" \
                    "(pool ${ROOT_BACKUP_POOL:-<unset>}: ${rrb_pool_state})"
        return 0
    fi

    # Dry-run mode: show what would be done
    if [ "$rrb_dry_run" = "dry-run" ]; then
        log_message "[DRY-RUN] would run: rbackup"
        return 0
    fi

    # Run rbackup
    rbackup || {
        local rc=$?
        # Exit code 23 = partial transfer (some files couldn't be copied)
        # This is common for locked files during backup - treat as warning
        if [ "$rc" -eq 23 ]; then
            log_message "rbackup partial transfer (exit 23) - some files may have been skipped"
            return 0
        fi
        report "$rc" "rbackup failed"
        return "$rc"
    }

    log_message "rbackup completed"
    return 0
}

# =============================================================================
#   CLEANUP: EXPORT BACKUP POOLS ON EXIT/SIGNAL
# =============================================================================

function cleanup_export_backup_pools {
    # Export any backup pools that are currently imported.
    # Registered in cleanup_functions so it runs on signal or exit.
    #
    # Pools checked:
    #   - ROOT_BACKUP_POOL (imported by prepare_root_mount)
    #   - Pools from ZFS_BACKUP_TARGETS configs (imported by zbackup)

    local cebp_pools=()

    # Collect pool name from ROOT_BACKUP_POOL
    if [ -n "${ROOT_BACKUP_POOL:-}" ]; then
        cebp_pools+=("$ROOT_BACKUP_POOL")
    fi

    # Collect pool names from ZFS_BACKUP_TARGETS config files
    local cebp_config cebp_config_file cebp_pool
    for cebp_config in "${ZFS_BACKUP_TARGETS[@]}"; do
        cebp_config_file="${BACKUP_CONFIGS_DIR}/${cebp_config}.conf"
        if [ -f "$cebp_config_file" ]; then
            cebp_pool=$(grep '^BACKUP_POOL=' "$cebp_config_file" | cut -d'"' -f2)
            if [ -n "$cebp_pool" ]; then
                cebp_pools+=("$cebp_pool")
            fi
        fi
    done

    # Deduplicate (e.g. silver appears as both ROOT_BACKUP_POOL and a target)
    local -A cebp_seen
    local cebp_name
    for cebp_name in "${cebp_pools[@]}"; do
        if [ -n "${cebp_seen[$cebp_name]+x}" ]; then
            continue
        fi
        cebp_seen[$cebp_name]=1

        if zpool list "$cebp_name" >/dev/null 2>&1; then
            log_message "cleanup: exporting backup pool ${cebp_name}..."
            sync
            sudo zpool export "$cebp_name" 2>/dev/null \
                || sudo zpool export -f "$cebp_name" 2>/dev/null \
                || log_message "cleanup: WARNING - failed to export ${cebp_name}"
        fi
    done
}

# Register the cleanup handler (runs on signal or normal exit via cleanup)
cleanup_functions+=('cleanup_export_backup_pools')

# =============================================================================
#   MAIN BACKUP ENTRY POINT
# =============================================================================

function run_all_backups {
    # Run all backup types
    # Failures in one backup type don't prevent others from running
    #
    # Arguments:
    #   $1 - (optional) "dry-run" to preview without making changes
    #
    # Order:
    #   1. Root filesystem backup (rbackup) - runs first while backup pool is mounted
    #   2. Local ZFS backups (zbackup) - exports pools after completion
    #   3. Remote syncoid replication

    local rab_dry_run="${1:-}"

    local rab_dry_prefix=""
    if [ "$rab_dry_run" = "dry-run" ]; then
        rab_dry_prefix="[DRY-RUN] "
    fi

    log_message "${rab_dry_prefix}run_all_backups"

    local rab_errors=0

    # 1. Root filesystem backup (before zbackup exports backup pools)
    log_message "${rab_dry_prefix}=== Root backup ==="
    if ! run_root_backup "$rab_dry_run"; then
        rab_errors=$((rab_errors + 1))
    fi

    # 2. Local ZFS backups
    log_message "${rab_dry_prefix}=== Local ZFS backups ==="
    if ! run_all_zfs_local_backups "$rab_dry_run"; then
        rab_errors=$((rab_errors + 1))
    fi

    # 3. Remote syncoid replication
    log_message "${rab_dry_prefix}=== Syncoid replication ==="
    if ! run_all_syncoid_backups "$rab_dry_run"; then
        rab_errors=$((rab_errors + 1))
    fi

    if [ "$rab_errors" -gt 0 ]; then
        log_message "${rab_dry_prefix}backup completed with ${rab_errors} error(s)"
    else
        log_message "${rab_dry_prefix}backup checks complete"
    fi

    return 0
}
