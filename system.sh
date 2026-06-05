#!/bin/bash
##  System check and health monitoring

##  Settings
#   STAMP               should be set by a call to set_stamp in bump.sh
#   UNITS_TO_CHECK      list of systemd units to check
#   ZFS_POOL            ZFS pool name to monitor
#   SCRUB_WARN_DAYS     warn if scrub older than this many days
#   POOL_CAPACITY_WARN  warn if pool capacity exceeds this percentage
#   JOURNAL_WARN_SIZE   warn if journal exceeds this size (e.g., "1G")

##  Dependencies
#   return_codes.sh
#   settings.sh
#   bump.sh

##  Notes
#   system_check() ensures listed units are active
#   Health check functions report issues but don't abort on warnings

# =============================================================================
#   SYSTEMD UNIT MANAGEMENT
# =============================================================================

function system_check {
    # Check services are running
    #
    # Arguments:
    #   $1 - (optional) "dry-run" to skip starting services
    #
    # System units to check are set globally in ${UNITS_TO_CHECK[@]}

    local sc_dry_run="${1:-}"

    log_message "system_check${sc_dry_run:+ (dry-run)}"

    print_rule; print_error_rule
    for svc in "${UNITS_TO_CHECK[@]}"; do
        make_active "${svc}" "$sc_dry_run"
        print_rule; print_error_rule
    done
    return 0
}

function make_active {
    # Make sure a systemd unit is active
    #
    # Arguments:
    #   $1 - Unit name (e.g., "syncthing@user.service")
    #   $2 - (optional) "dry-run" to skip starting
    #
    # Returns:
    #   0 - Unit is now active
    #   Calls cleanup() with SYSTEM_UNIT_FAILURE if unit failed

    local ma_unit=$1
    local ma_dry_run="${2:-}"

    not_empty "unit to activate" "$ma_unit"
    log_setting "unit to activate" "$ma_unit"

    if ! sudo systemctl is-active --quiet "$ma_unit"; then
        if [ "$ma_dry_run" = "dry-run" ]; then
            log_message "[DRY-RUN] would start $ma_unit"
        else
            sudo systemctl start "$ma_unit" ||\
                report $? "starting $ma_unit"
            if sudo systemctl is-failed --quiet "$ma_unit"; then
                sudo systemctl status --no-pager --lines=10 "$ma_unit" ||\
                    report $? "get status of $ma_unit"
                cleanup "$SYSTEM_UNIT_FAILURE"
            fi
        fi
    fi
    sudo systemctl status --no-pager --lines=0 "$ma_unit" ||\
        report $? "get status of $ma_unit"
    return 0
}

# =============================================================================
#   ZFS HEALTH MONITORING
# =============================================================================

function check_zfs_health {
    # Check ZFS pool health status
    #
    # Checks:
    #   - Pool exists and is importable
    #   - No errors in pool status
    #   - No degraded or faulted devices
    #   - Capacity below POOL_CAPACITY_WARN threshold
    #
    # Returns:
    #   0 - Pool is healthy
    #   1 - Pool has issues (warnings emitted to stderr)

    local czh_pool="${ZFS_POOL}"
    local czh_warn_capacity="${POOL_CAPACITY_WARN:-80}"
    local czh_issues=0

    log_message "check_zfs_health ${czh_pool}"

    # Check pool exists
    if ! zpool list "$czh_pool" &>/dev/null; then
        log_message "WARNING: ZFS pool '${czh_pool}' not found"
        return 1
    fi

    # Get pool status
    local czh_status
    czh_status=$(zpool status "$czh_pool" 2>&1)

    # Check for errors
    if echo "$czh_status" | grep -qE "errors: [^N]"; then
        log_message "WARNING: ZFS pool '${czh_pool}' has errors"
        echo "$czh_status" | grep -E "errors:" >&2
        czh_issues=1
    fi

    # Check for degraded or faulted state
    if echo "$czh_status" | grep -qE "state: (DEGRADED|FAULTED|UNAVAIL)"; then
        log_message "WARNING: ZFS pool '${czh_pool}' is not healthy"
        echo "$czh_status" | grep -E "state:" >&2
        czh_issues=1
    fi

    # Check capacity
    local czh_capacity
    czh_capacity=$(zpool list -H -o capacity "$czh_pool" 2>/dev/null | tr -d '%')

    if [ -n "$czh_capacity" ] && [ "$czh_capacity" -ge "$czh_warn_capacity" ]; then
        log_message "WARNING: ZFS pool '${czh_pool}' at ${czh_capacity}% capacity (threshold: ${czh_warn_capacity}%)"
        czh_issues=1
    fi

    if [ "$czh_issues" -eq 0 ]; then
        log_message "ZFS pool '${czh_pool}' is healthy (${czh_capacity}% used)"
    fi

    return "$czh_issues"
}

function check_zfs_scrub {
    # Check ZFS scrub status
    #
    # Warns if:
    #   - No scrub has ever been run
    #   - Last scrub was more than SCRUB_WARN_DAYS ago
    #   - Scrub is currently in progress (informational)
    #
    # Returns:
    #   0 - Scrub is up to date
    #   1 - Scrub is overdue or never run

    local czs_pool="${ZFS_POOL}"
    local czs_warn_days="${SCRUB_WARN_DAYS:-30}"

    log_message "check_zfs_scrub ${czs_pool}"

    # Check pool exists
    if ! zpool list "$czs_pool" &>/dev/null; then
        log_message "ZFS pool '${czs_pool}' not found"
        return 1
    fi

    # Get scrub status
    local czs_status
    czs_status=$(zpool status "$czs_pool" 2>&1)

    # Check if scrub is in progress
    if echo "$czs_status" | grep -q "scrub in progress"; then
        log_message "ZFS scrub in progress on '${czs_pool}'"
        return 0
    fi

    # Extract last scrub date
    local czs_scrub_line
    czs_scrub_line=$(echo "$czs_status" | grep -E "scan:.*scrub")

    if [ -z "$czs_scrub_line" ]; then
        # Check for "none requested" or similar
        if echo "$czs_status" | grep -qE "scan: none requested"; then
            log_message "WARNING: No scrub has ever been run on '${czs_pool}'"
            log_message "Run: sudo zpool scrub ${czs_pool}"
            return 1
        fi
        log_message "Could not determine scrub status for '${czs_pool}'"
        return 1
    fi

    # Parse the scrub completion date
    # Format: "scan: scrub repaired 0B in 01:23:45 with 0 errors on Sun Jan 12 14:30:00 2025"
    local czs_scrub_date
    czs_scrub_date=$(echo "$czs_scrub_line" | grep -oE "[A-Z][a-z]{2} [A-Z][a-z]{2} +[0-9]+ [0-9:]+.* [0-9]{4}")

    if [ -z "$czs_scrub_date" ]; then
        log_message "Could not parse scrub date from: ${czs_scrub_line}"
        return 1
    fi

    # Convert to epoch and calculate age
    local czs_scrub_epoch
    czs_scrub_epoch=$(date -d "$czs_scrub_date" +%s 2>/dev/null)

    if [ -z "$czs_scrub_epoch" ]; then
        log_message "Could not parse date: ${czs_scrub_date}"
        return 1
    fi

    local czs_now_epoch
    czs_now_epoch=$(date +%s)
    local czs_age_days=$(( (czs_now_epoch - czs_scrub_epoch) / 86400 ))

    if [ "$czs_age_days" -gt "$czs_warn_days" ]; then
        log_message "WARNING: Last scrub on '${czs_pool}' was ${czs_age_days} days ago (threshold: ${czs_warn_days})"
        log_message "Run: sudo zpool scrub ${czs_pool}"
        return 1
    fi

    log_message "Last scrub on '${czs_pool}' was ${czs_age_days} days ago (OK)"
    return 0
}

# =============================================================================
#   SYSTEMD HEALTH CHECKS
# =============================================================================

function check_failed_services {
    # Check for failed systemd services
    #
    # Reports any services in failed state
    #
    # Returns:
    #   0 - No failed services
    #   1 - One or more services failed

    log_message "check_failed_services"

    local cfs_failed
    cfs_failed=$(systemctl --failed --no-legend --no-pager 2>/dev/null)

    if [ -z "$cfs_failed" ]; then
        log_message "No failed services"
        return 0
    fi

    local cfs_count
    cfs_count=$(echo "$cfs_failed" | wc -l)

    log_message "WARNING: ${cfs_count} failed service(s):"
    echo "$cfs_failed" | while read -r line; do
        >&2 echo "  - $line"
    done

    return 1
}

function check_journal_size {
    # Check systemd journal size and vacuum if over threshold
    #
    # Arguments:
    #   $1 - (optional) "dry-run" to show what would be done
    #
    # Returns:
    #   0 - Journal size is acceptable or was vacuumed
    #   1 - Error checking journal

    local cjs_dry_run="${1:-}"
    local cjs_warn_size="${JOURNAL_WARN_SIZE:-1G}"

    log_message "check_journal_size"

    # Check journalctl command exists
    if ! command -v journalctl &>/dev/null; then
        log_message "journalctl command not found"
        return 1
    fi

    # Get current journal disk usage
    local cjs_usage
    cjs_usage=$(journalctl --disk-usage 2>/dev/null | grep -oE "[0-9]+\.?[0-9]*[KMGTP]?")

    if [ -z "$cjs_usage" ]; then
        log_message "Could not determine journal size"
        return 1
    fi

    # Convert sizes to bytes for comparison
    local cjs_current_bytes
    local cjs_warn_bytes

    cjs_current_bytes=$(numfmt --from=iec "$cjs_usage" 2>/dev/null)
    cjs_warn_bytes=$(numfmt --from=iec "$cjs_warn_size" 2>/dev/null)

    if [ -z "$cjs_current_bytes" ] || [ -z "$cjs_warn_bytes" ]; then
        log_message "Could not parse journal sizes (current: ${cjs_usage}, threshold: ${cjs_warn_size})"
        return 1
    fi

    if [ "$cjs_current_bytes" -gt "$cjs_warn_bytes" ]; then
        log_message "Journal size ${cjs_usage} exceeds threshold ${cjs_warn_size}"
        if [ "$cjs_dry_run" = "dry-run" ]; then
            log_message "[DRY-RUN] would run: sudo journalctl --vacuum-size=${cjs_warn_size}"
        else
            log_message "Running vacuum to reduce journal size..."
            sudo journalctl --vacuum-size="${cjs_warn_size}" || {
                log_message "WARNING: Journal vacuum failed"
                return 1
            }
            log_message "Journal vacuum complete"
        fi
        return 0
    fi

    log_message "Journal size ${cjs_usage} is within limits"
    return 0
}

# =============================================================================
#   ARCH LINUX PACKAGE CHECKS
# =============================================================================

function check_pacnew_files {
    # Check for .pacnew and .pacsave files
    #
    # These indicate configuration files that need manual merging
    #
    # Returns:
    #   0 - No pacnew/pacsave files found
    #   1 - Files found (need manual attention)

    log_message "check_pacnew_files"

    local cpf_files
    cpf_files=$(sudo find /etc -name "*.pacnew" -o -name "*.pacsave" 2>/dev/null)

    if [ -z "$cpf_files" ]; then
        log_message "No .pacnew or .pacsave files found"
        return 0
    fi

    local cpf_count
    cpf_count=$(echo "$cpf_files" | wc -l)

    log_message "WARNING: Found ${cpf_count} .pacnew/.pacsave file(s):"
    echo "$cpf_files" | while read -r file; do
        >&2 echo "  - $file"
    done
    log_message "Review and merge these configuration files"

    return 1
}

function check_orphan_packages {
    # Check for orphan packages
    #
    # Orphan packages are installed as dependencies but no longer required
    #
    # Returns:
    #   0 - No orphan packages
    #   1 - Orphan packages found (informational only)

    log_message "check_orphan_packages"

    # Check pacman command exists
    if ! command -v pacman &>/dev/null; then
        log_message "pacman command not found (not Arch Linux?)"
        return 0
    fi

    local cop_orphans
    cop_orphans=$(pacman -Qtdq 2>/dev/null)

    if [ -z "$cop_orphans" ]; then
        log_message "No orphan packages found"
        return 0
    fi

    local cop_count
    cop_count=$(echo "$cop_orphans" | wc -l)

    log_message "Found ${cop_count} orphan package(s):"
    echo "$cop_orphans" | head -10 | while read -r pkg; do
        >&2 echo "  - $pkg"
    done

    if [ "$cop_count" -gt 10 ]; then
        >&2 echo "  ... and $((cop_count - 10)) more"
    fi

    log_message "To remove: sudo pacman -Rns \$(pacman -Qtdq)"

    return 1
}

# =============================================================================
#   THERMAL MANAGEMENT
# =============================================================================

function check_thermal_management {
    # Check CPU temperature and thermal management services
    #
    # Verifies:
    #   - CPU temperature is within acceptable limits
    #   - Thermal management services are running (throttled, thinkfan, tlp)
    #
    # Returns:
    #   0 - All checks passed
    #   1 - Warnings or issues found

    local ctm_warn="${TEMP_WARN_THRESHOLD:-85}"
    local ctm_crit="${TEMP_CRIT_THRESHOLD:-95}"
    local ctm_issues=0

    log_message "check_thermal_management"

    # Check CPU temperature
    if command -v sensors &>/dev/null; then
        local ctm_temp
        ctm_temp=$(sensors 2>/dev/null | grep "Package id 0:" | awk '{print $4}' | tr -d '+°C')

        if [ -n "$ctm_temp" ]; then
            # Convert to integer for comparison
            local ctm_temp_int="${ctm_temp%.*}"

            log_setting "CPU temperature" "${ctm_temp}°C"

            if [ "$ctm_temp_int" -ge "$ctm_crit" ]; then
                log_message "CRITICAL: CPU temperature ${ctm_temp}°C exceeds ${ctm_crit}°C"
                ctm_issues=$((ctm_issues + 1))
            elif [ "$ctm_temp_int" -ge "$ctm_warn" ]; then
                log_message "WARNING: CPU temperature ${ctm_temp}°C exceeds ${ctm_warn}°C"
                ctm_issues=$((ctm_issues + 1))
            else
                log_message "CPU temperature ${ctm_temp}°C is within limits"
            fi
        else
            log_message "WARNING: Could not read CPU temperature"
            ctm_issues=$((ctm_issues + 1))
        fi
    else
        log_message "WARNING: sensors command not available (install lm_sensors)"
        ctm_issues=$((ctm_issues + 1))
    fi

    # Check thermal management services
    if [ ${#THERMAL_SERVICES[@]} -gt 0 ]; then
        for ctm_svc in "${THERMAL_SERVICES[@]}"; do
            if systemctl is-active --quiet "$ctm_svc" 2>/dev/null; then
                log_message "${ctm_svc} is running"
            else
                log_message "WARNING: ${ctm_svc} is not running"
                ctm_issues=$((ctm_issues + 1))
            fi
        done
    fi

    # Check thinkfan configuration (if running)
    if systemctl is-active --quiet thinkfan.service 2>/dev/null; then
        if [ -f /proc/acpi/ibm/fan ]; then
            local ctm_fan_level
            ctm_fan_level=$(grep "^level:" /proc/acpi/ibm/fan 2>/dev/null | awk '{print $2}')
            if [ -n "$ctm_fan_level" ]; then
                log_setting "Fan level" "$ctm_fan_level"
            fi
        fi
    fi

    # Check tlp configuration (if running)
    if systemctl is-active --quiet tlp.service 2>/dev/null; then
        if command -v tlp-stat &>/dev/null; then
            local ctm_tlp_mode
            ctm_tlp_mode=$(tlp-stat -s 2>/dev/null | grep "Mode" | head -1 | awk -F'=' '{print $2}' | xargs)
            if [ -n "$ctm_tlp_mode" ]; then
                log_setting "TLP mode" "$ctm_tlp_mode"
            fi
        fi
    fi

    if [ "$ctm_issues" -gt 0 ]; then
        return 1
    fi

    return 0
}

# =============================================================================
#   SYNCTHING HEALTH CHECK
# =============================================================================

function check_syncthing {
    # Check syncthing service and sync health
    #
    # Checks:
    #   - syncthing.service user unit is active
    #   - No error-level messages in syncthing journal (last 24 hours)
    #   - No .sync-conflict-* files in configured sync folders
    #
    # Returns:
    #   0 - Syncthing is healthy
    #   1 - Issues found (warnings emitted)

    local cst_issues=0

    log_message "check_syncthing"

    # Check if syncthing is configured (folders set)
    if [ ${#SYNCTHING_FOLDERS[@]} -eq 0 ]; then
        log_message "No syncthing folders configured — skipping check"
        return 0
    fi

    # Check syncthing user service is active
    if systemctl --user is-active --quiet syncthing.service 2>/dev/null; then
        log_message "syncthing.service is active"
    else
        log_message "WARNING: syncthing.service is not active"
        cst_issues=$((cst_issues + 1))
    fi

    # Check syncthing journal for errors in the last 24 hours
    local cst_errors
    cst_errors=$(journalctl --user -u syncthing.service --since "24 hours ago" \
        --priority=err --no-pager 2>/dev/null)
    if [ -n "$cst_errors" ]; then
        local cst_error_count
        cst_error_count=$(echo "$cst_errors" | wc -l)
        log_message "WARNING: ${cst_error_count} error(s) in syncthing journal (last 24h)"
        cst_issues=$((cst_issues + 1))
    fi

    # Check for sync-conflict files in configured folders
    local cst_total_conflicts=0
    for cst_folder in "${SYNCTHING_FOLDERS[@]}"; do
        if [ ! -d "$cst_folder" ]; then
            log_message "WARNING: syncthing folder does not exist: ${cst_folder}"
            cst_issues=$((cst_issues + 1))
            continue
        fi
        local cst_conflicts
        cst_conflicts=$(find "$cst_folder" -name "*.sync-conflict-*" 2>/dev/null | wc -l)
        if [ "$cst_conflicts" -gt 0 ]; then
            log_message "WARNING: ${cst_conflicts} sync-conflict file(s) in ${cst_folder}"
            cst_total_conflicts=$((cst_total_conflicts + cst_conflicts))
        fi
    done

    if [ "$cst_total_conflicts" -gt 0 ]; then
        log_message "Total sync-conflict files: ${cst_total_conflicts}"
        cst_issues=$((cst_issues + 1))
    fi

    if [ "$cst_issues" -eq 0 ]; then
        log_message "Syncthing is healthy"
    fi

    return "$cst_issues"
}

# =============================================================================
#   MAIN HEALTH CHECK ENTRY POINT
# =============================================================================

function run_all_health_checks {
    # Run all system health checks
    #
    # Arguments:
    #   $1 - (optional) "dry-run" to preview changes without making them
    #
    # Runs each check independently - failures in one don't prevent others
    #
    # Returns:
    #   0 - All checks passed
    #   1 - One or more checks had warnings

    local rahc_dry_run="${1:-}"

    log_message "run_all_health_checks"

    local rahc_issues=0

    print_rule; print_error_rule

    # ZFS health
    if ! check_zfs_health; then
        rahc_issues=$((rahc_issues + 1))
    fi
    print_rule; print_error_rule

    # ZFS scrub status
    if ! check_zfs_scrub; then
        rahc_issues=$((rahc_issues + 1))
    fi
    print_rule; print_error_rule

    # Failed services
    if ! check_failed_services; then
        rahc_issues=$((rahc_issues + 1))
    fi
    print_rule; print_error_rule

    # Journal size (with optional vacuum)
    if ! check_journal_size "$rahc_dry_run"; then
        rahc_issues=$((rahc_issues + 1))
    fi
    print_rule; print_error_rule

    # Pacnew files
    if ! check_pacnew_files; then
        rahc_issues=$((rahc_issues + 1))
    fi
    print_rule; print_error_rule

    # Orphan packages
    if ! check_orphan_packages; then
        rahc_issues=$((rahc_issues + 1))
    fi
    print_rule; print_error_rule

    # Thermal management
    if ! check_thermal_management; then
        rahc_issues=$((rahc_issues + 1))
    fi
    print_rule; print_error_rule

    # Syncthing health
    if ! check_syncthing; then
        rahc_issues=$((rahc_issues + 1))
    fi
    print_rule; print_error_rule

    if [ "$rahc_issues" -gt 0 ]; then
        log_message "Health checks completed with ${rahc_issues} warning(s)"
        return 1
    fi

    log_message "All health checks passed"
    return 0
}
