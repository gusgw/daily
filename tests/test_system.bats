#!/usr/bin/env bats
# Tests for system.sh
#
# These tests verify system health check functions.

load 'test_helper'

# =============================================================================
# Basic Loading Tests
# =============================================================================

@test "system.sh can be sourced" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    run source_project_file "system.sh"
    assert_success
}

@test "system.sh has valid bash syntax" {
    run bash -n "${PROJECT_DIR}/system.sh"
    assert_success
}

# =============================================================================
# Function Existence Tests
# =============================================================================

@test "system_check function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"
    run type system_check
    assert_success
    assert_output --partial "function"
}

@test "make_active function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"
    run type make_active
    assert_success
    assert_output --partial "function"
}

@test "check_zfs_health function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"
    run type check_zfs_health
    assert_success
    assert_output --partial "function"
}

@test "check_zfs_scrub function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"
    run type check_zfs_scrub
    assert_success
    assert_output --partial "function"
}

@test "check_failed_services function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"
    run type check_failed_services
    assert_success
    assert_output --partial "function"
}

@test "check_journal_size function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"
    run type check_journal_size
    assert_success
    assert_output --partial "function"
}

@test "check_pacnew_files function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"
    run type check_pacnew_files
    assert_success
    assert_output --partial "function"
}

@test "check_orphan_packages function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"
    run type check_orphan_packages
    assert_success
    assert_output --partial "function"
}

@test "run_all_health_checks function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"
    run type run_all_health_checks
    assert_success
    assert_output --partial "function"
}

# =============================================================================
# ZFS Health Check Tests
# =============================================================================

@test "check_zfs_health checks for zpool command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    if ! command -v zpool &>/dev/null; then
        run check_zfs_health
        assert_failure
        assert_output --partial "zpool command not found"
    fi
}

@test "check_zfs_health uses ZFS_POOL setting" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    skip_if_no_command zpool

    run check_zfs_health
    # Should use the ZFS_POOL from settings
    assert_output --partial "${ZFS_POOL}"
}

@test "check_zfs_health reports pool capacity" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    skip_if_no_command zpool

    # Only test if pool exists
    if zpool list "${ZFS_POOL}" &>/dev/null; then
        run check_zfs_health
        # Should report capacity
        assert_output --partial "%"
    fi
}

@test "check_zfs_health returns failure for non-existent pool" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    skip_if_no_command zpool

    ZFS_POOL="nonexistent_pool_12345"
    run check_zfs_health
    assert_failure
    assert_output --partial "not found"
}

# =============================================================================
# ZFS Scrub Check Tests
# =============================================================================

@test "check_zfs_scrub checks for zpool command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    if ! command -v zpool &>/dev/null; then
        run check_zfs_scrub
        assert_failure
        assert_output --partial "zpool command not found"
    fi
}

@test "check_zfs_scrub uses ZFS_POOL setting" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    skip_if_no_command zpool

    run check_zfs_scrub
    assert_output --partial "${ZFS_POOL}"
}

@test "check_zfs_scrub uses SCRUB_WARN_DAYS setting" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    skip_if_no_command zpool

    # Only test if pool exists
    if zpool list "${ZFS_POOL}" &>/dev/null; then
        run check_zfs_scrub
        # Should either report days or "no scrub ever run"
        [[ "$output" == *"days"* ]] || [[ "$output" == *"scrub"* ]]
    fi
}

@test "check_zfs_scrub returns failure for non-existent pool" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    skip_if_no_command zpool

    ZFS_POOL="nonexistent_pool_12345"
    run check_zfs_scrub
    assert_failure
    assert_output --partial "not found"
}

# =============================================================================
# Failed Services Check Tests
# =============================================================================

@test "check_failed_services runs without error" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    run check_failed_services
    # Success or failure depends on system state
    # Just verify it runs
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "check_failed_services reports status" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    run check_failed_services
    # Should report either "No failed" or "failed service(s)"
    [[ "$output" == *"failed"* ]]
}

# =============================================================================
# Journal Size Check Tests
# =============================================================================

@test "check_journal_size checks for journalctl command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    # journalctl should exist on systemd systems
    if command -v journalctl &>/dev/null; then
        run check_journal_size
        # Should run and report size
        [[ "$output" == *"Journal size"* ]] || [[ "$output" == *"journal"* ]]
    fi
}

@test "check_journal_size uses JOURNAL_WARN_SIZE setting" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    skip_if_no_command journalctl

    # Set a very high threshold so it passes
    JOURNAL_WARN_SIZE="100G"
    run check_journal_size
    assert_success
    assert_output --partial "within limits"
}

@test "check_journal_size vacuums when threshold exceeded" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    skip_if_no_command journalctl

    # Set a very low threshold so vacuum triggers
    JOURNAL_WARN_SIZE="1K"
    run check_journal_size
    # Now returns success after vacuum (or shows vacuum message)
    assert_output --partial "exceeds"
    [[ "$output" == *"vacuum"* ]]
}

# =============================================================================
# Pacnew Files Check Tests
# =============================================================================

@test "check_pacnew_files runs without error" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    # This requires sudo but should not error
    run check_pacnew_files
    # Either finds files or not
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "check_pacnew_files reports status" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    run check_pacnew_files
    # Should report either "No .pacnew" or "Found"
    [[ "$output" == *"pacnew"* ]] || [[ "$output" == *"pacsave"* ]]
}

# =============================================================================
# Orphan Packages Check Tests
# =============================================================================

@test "check_orphan_packages checks for pacman command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    run check_orphan_packages
    # On Arch, pacman exists; on other systems, should gracefully skip
    if command -v pacman &>/dev/null; then
        [[ "$output" == *"orphan"* ]]
    else
        assert_success
        assert_output --partial "pacman command not found"
    fi
}

@test "check_orphan_packages reports count" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    skip_if_no_command pacman

    run check_orphan_packages
    # Should report either "No orphan" or count
    [[ "$output" == *"orphan"* ]]
}

# =============================================================================
# Main Health Check Tests
# =============================================================================

@test "run_all_health_checks runs all checks" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    run run_all_health_checks
    # Should run all checks - verify key functions were called
    [[ "$output" == *"check_zfs_health"* ]] || [[ "$output" == *"zpool"* ]] || [[ "$output" == *"ZFS"* ]]
    [[ "$output" == *"check_failed_services"* ]] || [[ "$output" == *"failed"* ]]
    [[ "$output" == *"check_journal_size"* ]] || [[ "$output" == *"Journal"* ]] || [[ "$output" == *"journal"* ]]
}

@test "run_all_health_checks continues on individual failures" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    # Even with a non-existent pool, should run other checks
    ZFS_POOL="nonexistent_pool_12345"
    run run_all_health_checks

    # Should still check other things
    [[ "$output" == *"failed"* ]] || [[ "$output" == *"journal"* ]] || [[ "$output" == *"orphan"* ]]
}

@test "run_all_health_checks reports warning count" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    run run_all_health_checks
    # Should report summary
    [[ "$output" == *"Health checks"* ]] || [[ "$output" == *"health checks"* ]]
}

# =============================================================================
# Settings Integration Tests
# =============================================================================

@test "system functions use ZFS_POOL from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"

    assert [ -n "$ZFS_POOL" ]
}

@test "system functions use SCRUB_WARN_DAYS from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"

    assert [ -n "$SCRUB_WARN_DAYS" ]
}

@test "system functions use POOL_CAPACITY_WARN from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"

    assert [ -n "$POOL_CAPACITY_WARN" ]
}

@test "system functions use JOURNAL_WARN_SIZE from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"

    assert [ -n "$JOURNAL_WARN_SIZE" ]
}

@test "system functions use UNITS_TO_CHECK from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"

    assert [ "${#UNITS_TO_CHECK[@]}" -gt 0 ]
}

# =============================================================================
# Phase 12 Bug Fix Tests
# =============================================================================

@test "check_journal_size accepts dry-run parameter" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    # Function should accept dry-run parameter without error
    run check_journal_size "dry-run"
    # Should not fail due to unexpected argument
    [[ "$output" != *"unexpected"* ]] && [[ "$output" != *"too many arguments"* ]]
}

@test "check_journal_size shows vacuum message when journal exceeds threshold" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    # Set a very low threshold to trigger vacuum
    JOURNAL_WARN_SIZE="1K"

    run check_journal_size
    # Should mention vacuum when over threshold
    if [[ "$output" == *"exceeds"* ]]; then
        [[ "$output" == *"vacuum"* ]]
    fi
}

@test "check_journal_size in dry-run skips actual vacuum" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    JOURNAL_WARN_SIZE="1K"

    run check_journal_size "dry-run"
    # In dry-run, should show what would be done
    if [[ "$output" == *"exceeds"* ]]; then
        [[ "$output" == *"DRY-RUN"* ]] || [[ "$output" == *"would"* ]]
    fi
}

@test "run_all_health_checks accepts dry-run parameter" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    # Function should accept dry-run parameter
    run run_all_health_checks "dry-run"
    # Should complete without argument error
    [[ "$output" != *"unexpected"* ]] && [[ "$output" != *"too many arguments"* ]]
}

@test "run_all_health_checks passes dry-run to check_journal_size" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    JOURNAL_WARN_SIZE="1K"

    run run_all_health_checks "dry-run"
    # If journal check runs in dry-run, should show DRY-RUN message
    if [[ "$output" == *"journal"* ]] && [[ "$output" == *"exceeds"* ]]; then
        [[ "$output" == *"DRY-RUN"* ]] || [[ "$output" == *"would"* ]]
    fi
}

# =============================================================================
# Thermal Management Tests
# =============================================================================

@test "check_thermal_management function exists" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    run type check_thermal_management
    assert_success
    assert_output --partial "function"
}

@test "check_thermal_management checks CPU temperature" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    run check_thermal_management
    # Should mention temperature in output
    assert_output --partial "temperature"
}

@test "check_thermal_management checks thermal services" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "system.sh"

    run check_thermal_management
    # Should check at least one thermal service
    [[ "$output" == *"throttled"* ]] || [[ "$output" == *"thinkfan"* ]] || [[ "$output" == *"tlp"* ]]
}

@test "THERMAL_SERVICES array is accessible" {
    source_project_file "settings.sh"

    assert [ ${#THERMAL_SERVICES[@]} -gt 0 ]
}

@test "TEMP_WARN_THRESHOLD is set" {
    source_project_file "settings.sh"

    assert [ -n "$TEMP_WARN_THRESHOLD" ]
}

@test "TEMP_CRIT_THRESHOLD is set" {
    source_project_file "settings.sh"

    assert [ -n "$TEMP_CRIT_THRESHOLD" ]
}

# =============================================================================
# Syncthing Health Check Tests
# =============================================================================

@test "check_syncthing function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "system.sh"
    run type check_syncthing
    assert_success
    assert_output --partial "function"
}

@test "check_syncthing skips when no folders configured" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "system.sh"
    SYNCTHING_FOLDERS=()

    run check_syncthing
    assert_success
    assert_output --partial "No syncthing folders configured"
}

@test "check_syncthing warns when service is not active" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "system.sh"

    local tmpdir
    tmpdir=$(mktemp -d)
    SYNCTHING_FOLDERS=("$tmpdir")

    # Mock systemctl --user to return failure
    systemctl() {
        if [[ "$1" == "--user" && "$2" == "is-active" ]]; then
            return 1
        fi
    }
    export -f systemctl

    # Mock journalctl to return nothing
    journalctl() { echo ""; }
    export -f journalctl

    # Mock find to return nothing
    find() { :; }
    export -f find

    run check_syncthing
    assert_failure
    assert_output --partial "syncthing.service is not active"

    rm -rf "$tmpdir"
}

@test "check_syncthing warns on missing folder" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "system.sh"
    SYNCTHING_FOLDERS=("/nonexistent/path/for/test")

    # Mock systemctl --user to return success
    systemctl() {
        if [[ "$1" == "--user" && "$2" == "is-active" ]]; then
            return 0
        fi
    }
    export -f systemctl

    # Mock journalctl to return nothing
    journalctl() { :; }
    export -f journalctl

    run check_syncthing
    assert_failure
    assert_output --partial "syncthing folder does not exist"
}

@test "check_syncthing reports sync-conflict files" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "system.sh"

    local tmpdir
    tmpdir=$(mktemp -d)
    SYNCTHING_FOLDERS=("$tmpdir")

    # Create a sync-conflict file
    touch "${tmpdir}/file.sync-conflict-20260213-123456-ABCDEFG"

    # Mock systemctl --user to return success
    systemctl() {
        if [[ "$1" == "--user" && "$2" == "is-active" ]]; then
            return 0
        fi
    }
    export -f systemctl

    # Mock journalctl to return nothing
    journalctl() { :; }
    export -f journalctl

    run check_syncthing
    assert_failure
    assert_output --partial "1 sync-conflict file(s)"

    rm -rf "$tmpdir"
}

@test "check_syncthing passes when healthy" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "system.sh"

    local tmpdir
    tmpdir=$(mktemp -d)
    SYNCTHING_FOLDERS=("$tmpdir")

    # Mock systemctl --user to return success
    systemctl() {
        if [[ "$1" == "--user" && "$2" == "is-active" ]]; then
            return 0
        fi
    }
    export -f systemctl

    # Mock journalctl to return nothing
    journalctl() { :; }
    export -f journalctl

    run check_syncthing
    assert_success
    assert_output --partial "Syncthing is healthy"

    rm -rf "$tmpdir"
}

@test "SYNCTHING_FOLDERS array is built from env var" {
    SYNCTHING_FOLDERS="/home/test/a /home/test/b"
    source_project_file "settings.sh"

    assert [ ${#SYNCTHING_FOLDERS[@]} -eq 2 ]
}
