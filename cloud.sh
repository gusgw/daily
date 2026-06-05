#!/bin/bash
##  Sync to cloud storage services via rclone

##  Settings
#   STAMP                   should be set by a call to set_stamp in bump.sh
#   CLOUD_SYNCS             array of sync configurations
#   SIMULTANEOUS_TRANSFERS  number of simultaneous transfers for rclone

##  Dependencies
#   return_codes.sh
#   settings.sh
#   bump.sh
#   sensitive.sh (for check_sensitive_files, build_rclone_excludes)

##  Notes
#   Cloud syncs use rclone bisync for bidirectional synchronization
#   Sensitive files are excluded using patterns from settings.sh
#   rclone configuration is expected at ~/.config/rclone/rclone.conf

# =============================================================================
#   RCLONE SYNC FUNCTIONS
# =============================================================================

function run_rclone_bisync {
    # Run bidirectional sync using rclone bisync
    #
    # Arguments:
    #   $1 - Local path
    #   $2 - Remote (format: "remote:path")
    #   $3 - (optional) "dry-run" to preview changes
    #
    # Returns:
    #   0 - Sync completed successfully
    #   Non-zero - Sync failed

    local rrb_local=$1
    local rrb_remote=$2
    local rrb_dry_run=$3

    not_empty "bisync local path" "$rrb_local"
    not_empty "bisync remote" "$rrb_remote"

    log_message "run_rclone_bisync"

    log_setting "bisync local" "$rrb_local"
    log_setting "bisync remote" "$rrb_remote"

    # Validate local path
    if [ ! -d "$rrb_local" ]; then
        log_message "local path does not exist: ${rrb_local}"
        return "$MISSING_FOLDER"
    fi

    # Check for rclone command
    if ! command -v rclone &>/dev/null; then
        report "$MISSING_FILE" "rclone command not found"
        return "$MISSING_FILE"
    fi

    # Build exclusion arguments
    local -a rrb_excludes
    mapfile -t rrb_excludes < <(get_rclone_exclude_array)

    # Build command
    local -a rrb_cmd=(rclone bisync)
    rrb_cmd+=(--copy-links)
    rrb_cmd+=(--stats-one-line --stats=1m)
    rrb_cmd+=(--transfers "${SIMULTANEOUS_TRANSFERS:-4}")
    rrb_cmd+=("${rrb_excludes[@]}")

    # Add dry-run if requested
    if [ "$rrb_dry_run" == "dry-run" ]; then
        rrb_cmd+=(--dry-run)
        log_message "DRY RUN - no changes will be made"
    fi

    rrb_cmd+=("$rrb_remote" "$rrb_local")

    # Log the command
    log_message "Running: ${rrb_cmd[*]}"

    # Run the sync
    throttle "${rrb_cmd[@]}" || {
        local rc=$?
        # bisync returns 2 for "resync required" which isn't a real error
        if [ "$rc" -eq 2 ]; then
            log_message "bisync requires --resync (first run or changes detected)"
            log_message "Run manually: rclone bisync --resync ${rrb_remote} ${rrb_local}"
        else
            report "$rc" "rclone bisync failed"
        fi
        return "$rc"
    }

    log_message "bisync completed: ${rrb_local} <-> ${rrb_remote}"
    return 0
}

function run_rclone_sync {
    # Run one-way sync using rclone sync (deletes files at destination)
    #
    # Arguments:
    #   $1 - Source path (local or remote)
    #   $2 - Destination path (local or remote)
    #   $3 - (optional) "dry-run" to preview changes
    #
    # Returns:
    #   0 - Sync completed successfully
    #   Non-zero - Sync failed

    local rrs_source=$1
    local rrs_dest=$2
    local rrs_dry_run=$3

    not_empty "sync source" "$rrs_source"
    not_empty "sync destination" "$rrs_dest"

    log_message "run_rclone_sync"

    log_setting "sync source" "$rrs_source"
    log_setting "sync destination" "$rrs_dest"

    # Check for rclone command
    if ! command -v rclone &>/dev/null; then
        report "$MISSING_FILE" "rclone command not found"
        return "$MISSING_FILE"
    fi

    # Build exclusion arguments
    local -a rrs_excludes
    mapfile -t rrs_excludes < <(get_rclone_exclude_array)

    # Build command
    local -a rrs_cmd=(rclone sync)
    rrs_cmd+=(--stats-one-line --stats=1m)
    rrs_cmd+=(--transfers "${SIMULTANEOUS_TRANSFERS:-4}")
    rrs_cmd+=("${rrs_excludes[@]}")

    if [ "$rrs_dry_run" == "dry-run" ]; then
        rrs_cmd+=(--dry-run)
        log_message "DRY RUN - no changes will be made"
    fi

    rrs_cmd+=("$rrs_source" "$rrs_dest")

    log_message "Running: ${rrs_cmd[*]}"

    throttle "${rrs_cmd[@]}" || {
        local rc=$?
        report "$rc" "rclone sync failed"
        return "$rc"
    }

    log_message "sync completed: ${rrs_source} -> ${rrs_dest}"
    return 0
}

function run_rclone_copy {
    # Run one-way copy using rclone copy (does not delete at destination)
    #
    # Arguments:
    #   $1 - Source path (local or remote)
    #   $2 - Destination path (local or remote)
    #   $3 - (optional) "dry-run" to preview changes
    #
    # Returns:
    #   0 - Copy completed successfully
    #   Non-zero - Copy failed

    local rrc_source=$1
    local rrc_dest=$2
    local rrc_dry_run=$3

    not_empty "copy source" "$rrc_source"
    not_empty "copy destination" "$rrc_dest"

    log_message "run_rclone_copy"

    log_setting "copy source" "$rrc_source"
    log_setting "copy destination" "$rrc_dest"

    # Check for rclone command
    if ! command -v rclone &>/dev/null; then
        report "$MISSING_FILE" "rclone command not found"
        return "$MISSING_FILE"
    fi

    # Build exclusion arguments
    local -a rrc_excludes
    mapfile -t rrc_excludes < <(get_rclone_exclude_array)

    # Build command
    local -a rrc_cmd=(rclone copy)
    rrc_cmd+=(--progress)
    rrc_cmd+=(--transfers "${SIMULTANEOUS_TRANSFERS:-4}")
    rrc_cmd+=("${rrc_excludes[@]}")

    if [ "$rrc_dry_run" == "dry-run" ]; then
        rrc_cmd+=(--dry-run)
        log_message "DRY RUN - no changes will be made"
    fi

    rrc_cmd+=("$rrc_source" "$rrc_dest")

    log_message "Running: ${rrc_cmd[*]}"

    throttle "${rrc_cmd[@]}" || {
        local rc=$?
        report "$rc" "rclone copy failed"
        return "$rc"
    }

    log_message "copy completed: ${rrc_source} -> ${rrc_dest}"
    return 0
}

# =============================================================================
#   CLOUD SYNC DISPATCHER
# =============================================================================

function run_cloud_sync {
    # Run a cloud sync based on CLOUD_SYNCS entry
    #
    # Arguments:
    #   $1 - Sync configuration string
    #        Format: "local_path:remote_name:remote_path[:mode]"
    #        mode is optional: "bisync" (default), "sync", or "copy"
    #   $2 - (optional) "dry-run" to preview changes
    #
    # Returns:
    #   0 - Sync completed
    #   Non-zero - Sync failed

    local rcs_config=$1
    local rcs_dry_run=$2

    not_empty "cloud sync config" "$rcs_config"

    log_message "run_cloud_sync"

    # Parse configuration
    # Format: "local_path:remote_name:" or "local_path:remote_name::mode"
    # The trailing colon after remote_name is required (rclone remote format)
    local rcs_local rcs_remote_name rcs_remote_path rcs_mode

    # Split by colon
    IFS=':' read -r rcs_local rcs_remote_name rcs_remote_path rcs_mode <<< "$rcs_config"

    if [ -z "$rcs_local" ] || [ -z "$rcs_remote_name" ]; then
        log_message "invalid sync config: ${rcs_config}"
        log_message "expected format: local_path:remote_name:[:mode]"
        return 1
    fi

    # Build remote string (remote_name: or remote_name:path)
    local rcs_remote="${rcs_remote_name}:"
    if [ -n "$rcs_remote_path" ]; then
        rcs_remote="${rcs_remote}${rcs_remote_path}"
    fi

    # Default mode is bisync
    rcs_mode="${rcs_mode:-bisync}"

    log_setting "cloud sync local" "$rcs_local"
    log_setting "cloud sync remote" "$rcs_remote"
    log_setting "cloud sync mode" "$rcs_mode"

    # For SFTP remotes, check host is reachable before attempting sync
    local rcs_remote_type
    rcs_remote_type=$(rclone config show "$rcs_remote_name" 2>/dev/null | grep '^type' | cut -d' ' -f3)
    if [ "$rcs_remote_type" = "sftp" ]; then
        local rcs_sftp_host rcs_sftp_user
        rcs_sftp_host=$(rclone config show "$rcs_remote_name" 2>/dev/null | grep '^host' | cut -d' ' -f3)
        rcs_sftp_user=$(rclone config show "$rcs_remote_name" 2>/dev/null | grep '^user' | cut -d' ' -f3)
        local rcs_ssh_target="${rcs_sftp_user:+${rcs_sftp_user}@}${rcs_sftp_host}"
        log_message "SFTP remote detected, checking host reachability: ${rcs_ssh_target}"
        if ! check_host_reachable "$rcs_ssh_target"; then
            log_message "skipping sync - ${rcs_ssh_target} not reachable"
            return 0
        fi
    fi

    # Check local path exists
    if [ ! -d "$rcs_local" ]; then
        log_message "local path does not exist: ${rcs_local}"
        return "$MISSING_FOLDER"
    fi

    # Run appropriate sync function
    case "$rcs_mode" in
        bisync)
            run_rclone_bisync "$rcs_local" "$rcs_remote" "$rcs_dry_run"
            ;;
        sync)
            run_rclone_sync "$rcs_local" "$rcs_remote" "$rcs_dry_run"
            ;;
        copy)
            run_rclone_copy "$rcs_local" "$rcs_remote" "$rcs_dry_run"
            ;;
        *)
            log_message "unknown sync mode: ${rcs_mode}"
            log_message "valid modes: bisync, sync, copy"
            return 1
            ;;
    esac
}

function run_all_cloud_syncs {
    # Run all configured cloud syncs
    # Iterates through CLOUD_SYNCS array
    #
    # Arguments:
    #   $1 - (optional) "dry-run" to preview all syncs
    #
    # Format of CLOUD_SYNCS entries:
    #   "local_path:remote_name:remote_path[:mode]"
    #   mode is optional: bisync (default), sync, or copy

    local racs_dry_run="${1:-}"
    local racs_dry_prefix=""
    if [ "$racs_dry_run" = "dry-run" ]; then
        racs_dry_prefix="[DRY-RUN] "
    fi

    log_message "${racs_dry_prefix}run_all_cloud_syncs"

    if [ ${#CLOUD_SYNCS[@]} -eq 0 ]; then
        log_message "${racs_dry_prefix}no cloud syncs configured"
        return 0
    fi

    # Pause syncthing folders that overlap with rclone sync paths
    # to prevent simultaneous writes from corrupting data.
    # Uses config.xml edits + service restart (no REST API needed).
    local racs_syncthing_paused=false
    if [ -f "${SYNCTHING_CONFIG:-}" ] && \
       systemctl --user is-active --quiet syncthing.service 2>/dev/null; then
        for config in "${CLOUD_SYNCS[@]}"; do
            local racs_local
            IFS=':' read -r racs_local _ _ _ <<< "$config"
            local racs_norm_local="${racs_local%/}"
            for sf in "${SYNCTHING_FOLDERS[@]}"; do
                local racs_norm_sf="${sf%/}"
                if [ "$racs_norm_local" = "$racs_norm_sf" ]; then
                    racs_syncthing_paused=true
                    break 2
                fi
            done
        done
        if [ "$racs_syncthing_paused" = true ]; then
            log_message "Pausing syncthing during rclone sync"
            systemctl --user stop syncthing.service
        fi
    fi

    local racs_failed=0

    for config in "${CLOUD_SYNCS[@]}"; do
        log_message "processing cloud sync: ${config}"

        if ! run_cloud_sync "$config" "$racs_dry_run"; then
            racs_failed=$((racs_failed + 1))
        fi
    done

    # Restart syncthing if we stopped it
    if [ "$racs_syncthing_paused" = true ]; then
        log_message "Resuming syncthing after rclone sync"
        systemctl --user start syncthing.service
    fi

    if [ "$racs_failed" -gt 0 ]; then
        log_message "${racs_failed} cloud sync(s) failed"
    else
        log_message "all cloud syncs completed"
    fi

    return 0
}
