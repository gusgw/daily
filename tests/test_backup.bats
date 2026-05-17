#!/usr/bin/env bats
# Tests for backup.sh
#
# These tests verify ZFS backup and syncoid replication functions.

load 'test_helper'

# =============================================================================
# Basic Loading Tests
# =============================================================================

@test "backup.sh can be sourced" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run source_project_file "backup.sh"
    assert_success
}

@test "backup.sh has valid bash syntax" {
    run bash -n "${PROJECT_DIR}/backup.sh"
    assert_success
}

# =============================================================================
# Function Existence Tests
# =============================================================================

@test "check_drive_connected function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type check_drive_connected
    assert_success
    assert_output --partial "function"
}

@test "run_zfs_local_backup function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type run_zfs_local_backup
    assert_success
    assert_output --partial "function"
}

@test "run_all_zfs_local_backups function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type run_all_zfs_local_backups
    assert_success
    assert_output --partial "function"
}

@test "run_syncoid_replication function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type run_syncoid_replication
    assert_success
    assert_output --partial "function"
}

@test "run_all_syncoid_backups function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type run_all_syncoid_backups
    assert_success
    assert_output --partial "function"
}

@test "run_root_backup function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type run_root_backup
    assert_success
    assert_output --partial "function"
}

@test "run_all_backups function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type run_all_backups
    assert_success
    assert_output --partial "function"
}

# =============================================================================
# Old Functions Removed
# =============================================================================

@test "run_local_backup function does not exist (removed)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type run_local_backup
    assert_failure
}

@test "cleanup_local_backup function does not exist (removed)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type cleanup_local_backup
    assert_failure
}

@test "run_remote_backup function does not exist (removed)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type run_remote_backup
    assert_failure
}

@test "cleanup_remote_backup function does not exist (removed)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type cleanup_remote_backup
    assert_failure
}

@test "all_remote_backups function does not exist (removed)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type all_remote_backups
    assert_failure
}

# =============================================================================
# Drive Detection Tests
# =============================================================================

@test "check_drive_connected returns failure with no argument" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    run check_drive_connected ""
    assert_failure
}

@test "check_drive_connected returns failure for non-existent drive" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    run check_drive_connected "nonexistent-drive-id-12345"
    assert_failure
}

@test "check_drive_connected finds existing drive" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Find a real drive ID on the system
    local real_drive
    real_drive=$(ls /dev/disk/by-id/ 2>/dev/null | grep -v 'part' | head -1)

    if [ -z "$real_drive" ]; then
        skip "No drives found in /dev/disk/by-id/"
    fi

    run check_drive_connected "$real_drive"
    assert_success
}

# =============================================================================
# ZFS Backup Target Parsing Tests
# =============================================================================

@test "run_all_zfs_local_backups handles empty targets array" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Explicitly set empty array for testing
    ZFS_BACKUP_TARGETS=()
    run run_all_zfs_local_backups
    assert_success
    assert_output --partial "no ZFS backup targets configured"
}

@test "ZFS_BACKUP_TARGETS array is accessible" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Verify the array exists (even if empty)
    declare -p ZFS_BACKUP_TARGETS &>/dev/null
}

# =============================================================================
# Syncoid Target Parsing Tests
# =============================================================================

@test "run_all_syncoid_backups handles empty targets array" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Explicitly set empty array for testing
    SYNCOID_TARGETS=()
    run run_all_syncoid_backups
    assert_success
    assert_output --partial "no syncoid targets configured"
}

@test "SYNCOID_TARGETS array is accessible" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    declare -p SYNCOID_TARGETS &>/dev/null
}

@test "run_all_syncoid_backups fails without SYNCOID_REMOTE_HOST" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    SYNCOID_TARGETS=("tank/test")
    SYNCOID_REMOTE_HOST=""
    SYNCOID_REMOTE_POOL="remotepool"

    run run_all_syncoid_backups
    assert_failure
    assert_output --partial "SYNCOID_REMOTE_HOST not configured"
}

@test "run_all_syncoid_backups fails without SYNCOID_REMOTE_POOL" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    SYNCOID_TARGETS=("tank/test")
    SYNCOID_REMOTE_HOST="remotehost"
    SYNCOID_REMOTE_POOL=""

    run run_all_syncoid_backups
    assert_failure
    assert_output --partial "SYNCOID_REMOTE_POOL not configured"
}

@test "run_all_syncoid_backups constructs correct destination" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    SYNCOID_TARGETS=("tank/user/src")
    SYNCOID_REMOTE_HOST="testhost"
    SYNCOID_REMOTE_POOL="testpool"

    # Run in dry-run mode to see the constructed destination
    run run_all_syncoid_backups "dry-run"
    # Should show the constructed destination path
    assert_output --partial "testhost:testpool/tank/user/src"
}

# =============================================================================
# Root Backup Tests
# =============================================================================

@test "run_root_backup checks for rbackup command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    if command -v rbackup &>/dev/null; then
        # rbackup exists - function should work (may skip if /mnt/root not mounted)
        run run_root_backup
        # Should either succeed or skip gracefully
        [[ "$status" -eq 0 ]] || [[ "$output" == *"not mounted"* ]]
    else
        # rbackup doesn't exist - function should report error
        run run_root_backup
        assert_failure
    fi
}

@test "run_root_backup skips when /mnt/root not mounted" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Only run if rbackup exists but /mnt/root is not mounted
    if ! command -v rbackup &>/dev/null; then
        skip "rbackup command not available"
    fi

    if mountpoint -q /mnt/root 2>/dev/null; then
        skip "/mnt/root is mounted - cannot test skip behavior"
    fi

    run run_root_backup
    assert_success
    assert_output --partial "not mounted"
}

# =============================================================================
# Main Entry Point Tests
# =============================================================================

@test "run_all_backups executes without error with empty config" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # CRITICAL: the test harness sources env.sh in setup(), which
    # populates ZFS_BACKUP_TARGETS and (via SYNCOID_DATASETS)
    # SYNCOID_TARGETS with the operator's REAL targets pointing at
    # the real remote host. This test previously did not clear them,
    # so `run run_all_backups` launched a real multi-hour syncoid
    # replication to toby and a real zbackup - the suite would hang
    # indefinitely here. Clear the arrays so only the empty-config
    # early-return paths run, matching the test's stated intent.
    ZFS_BACKUP_TARGETS=()
    SYNCOID_TARGETS=()

    run run_all_backups
    assert_success
}

@test "run_all_backups runs all backup types" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Set empty arrays to test structure without running actual backups
    ZFS_BACKUP_TARGETS=()
    SYNCOID_TARGETS=()

    run run_all_backups
    assert_success
    assert_output --partial "Local ZFS backups"
    assert_output --partial "Root backup"
    assert_output --partial "Syncoid replication"
}

# =============================================================================
# Dry-Run Tests (verify correct command would be called)
# =============================================================================

@test "run_zfs_local_backup checks for zbackup command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Test with non-existent config to verify command check happens first
    if ! command -v zbackup &>/dev/null; then
        run run_zfs_local_backup "nonexistent.conf"
        assert_failure
        assert_output --partial "zbackup command not found"
    else
        # zbackup exists - will fail on missing config (zbackup reports error)
        run run_zfs_local_backup "nonexistent.conf"
        assert_failure
        assert_output --partial "not found"
    fi
}

@test "run_syncoid_replication checks for syncoid command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    if ! command -v syncoid &>/dev/null; then
        run run_syncoid_replication "test/dataset" "user@unreachable:test/dest"
        assert_failure
        assert_output --partial "syncoid command not found"
    else
        # syncoid exists - host unreachable. Under the skip/fail
        # classification an unreachable host is a SKIP outcome
        # (BACKUP_SKIPPED), not plain success, so the run summary can
        # report ok/skipped/failed accurately. (192.0.2.1 is TEST-NET;
        # check_host_reachable fails fast against it.)
        run run_syncoid_replication "test/dataset" "user@192.0.2.1:test/dest"
        [ "$status" -eq "$BACKUP_SKIPPED" ]
        assert_output --partial "not reachable"
    fi
}

# =============================================================================
# Settings Integration Tests
# =============================================================================

@test "backup functions use BACKUP_CONFIGS_DIR from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    assert [ -n "$BACKUP_CONFIGS_DIR" ]
}

# =============================================================================
# Phase 12 Bug Fix Tests
# =============================================================================

@test "cleanup_export_backup_pools function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type cleanup_export_backup_pools
    assert_success
    assert_output --partial "function"
}

@test "cleanup_export_backup_pools is registered in cleanup_functions" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    local found=false
    for fn in "${cleanup_functions[@]}"; do
        if [ "$fn" = "cleanup_export_backup_pools" ]; then
            found=true
            break
        fi
    done
    assert [ "$found" = "true" ]
}

@test "cleanup_export_backup_pools skips pools that are not imported" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Mock zpool list to always fail (pool not imported)
    zpool() { return 1; }
    export -f zpool

    ROOT_BACKUP_POOL="testpool"
    ZFS_BACKUP_TARGETS=()
    BACKUP_CONFIGS_DIR="/nonexistent"

    # Should complete without error (nothing to export)
    run cleanup_export_backup_pools
    assert_success
    refute_output --partial "exporting"
}

@test "cleanup_export_backup_pools exports imported pool" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Track calls
    local export_calls_file="${BATS_TMPDIR}/export_calls"
    echo -n "" > "$export_calls_file"

    # Mock zpool list to succeed (pool is imported)
    zpool() {
        if [ "$1" = "list" ]; then
            return 0
        fi
        if [ "$1" = "export" ]; then
            echo "$2" >> "${BATS_TMPDIR}/export_calls"
            return 0
        fi
    }
    export -f zpool

    # Mock sudo to just run the command
    sudo() { "$@"; }
    export -f sudo

    # Mock sync
    sync() { return 0; }
    export -f sync

    ROOT_BACKUP_POOL="testpool"
    ZFS_BACKUP_TARGETS=()
    BACKUP_CONFIGS_DIR="/nonexistent"

    run cleanup_export_backup_pools
    assert_success
    assert_output --partial "exporting backup pool testpool"
}

@test "cleanup_export_backup_pools deduplicates pool names" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Create a temp config dir with a config that uses the same pool as ROOT_BACKUP_POOL
    local config_dir="${BATS_TMPDIR}/backup-configs"
    mkdir -p "$config_dir"
    echo 'BACKUP_POOL="mypool"' > "$config_dir/mypool.conf"

    # Count export attempts
    local export_count_file="${BATS_TMPDIR}/export_count"
    echo "0" > "$export_count_file"

    zpool() {
        if [ "$1" = "list" ]; then return 0; fi
        if [ "$1" = "export" ]; then
            local count
            count=$(cat "${BATS_TMPDIR}/export_count")
            echo $((count + 1)) > "${BATS_TMPDIR}/export_count"
            return 0
        fi
    }
    export -f zpool

    sudo() { "$@"; }
    export -f sudo

    sync() { return 0; }
    export -f sync

    ROOT_BACKUP_POOL="mypool"
    ZFS_BACKUP_TARGETS=("mypool")
    BACKUP_CONFIGS_DIR="$config_dir"

    run cleanup_export_backup_pools
    assert_success

    # Should only export once despite appearing twice
    local count
    count=$(cat "$export_count_file")
    assert [ "$count" -eq 1 ]
}

@test "run_root_backup treats rsync exit code 23 as warning not error" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Create a mock rbackup that exits with 23 (partial transfer)
    rbackup() {
        return 23
    }
    export -f rbackup

    # Mock mountpoint to say /mnt/root is mounted
    mountpoint() {
        return 0
    }
    export -f mountpoint

    run run_root_backup
    # Should succeed (warning) not fail
    assert_success
    assert_output --partial "partial transfer"
}

# =============================================================================
# Syncoid hardening tests (pool health, stale resume token, --no-sync-snap)
#
# These verify that a failed replication run does NOT require manual
# intervention: a sick pool is refused, a stale resume token is
# auto-cleared, and the destructive sync-snap fallback is removed.
# =============================================================================

@test "check_remote_pool_health function exists" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type check_remote_pool_health
    assert_success
}

@test "clear_stale_resume_token function exists" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type clear_stale_resume_token
    assert_success
}

@test "syncoid_progress_heartbeat function exists" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"
    run type syncoid_progress_heartbeat
    assert_success
}

@test "check_remote_pool_health succeeds when pool is ONLINE" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ssh() { echo "ONLINE"; return 0; }

    run check_remote_pool_health testhost testpool
    assert_success
}

@test "check_remote_pool_health fails when pool is not ONLINE" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ssh() { echo "SUSPENDED"; return 0; }

    run check_remote_pool_health testhost testpool
    assert_failure
    assert_output --partial "expected ONLINE"
}

@test "clear_stale_resume_token is a no-op when no token present" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # zfs reports "-" when there is no pending resumable receive.
    ssh() {
        if [[ "$*" == *receive_resume_token* ]]; then echo "-"; fi
        return 0
    }
    sudo() { echo "SUDO_SHOULD_NOT_RUN" >>"$TEST_TEMP_DIR/calls"; return 0; }

    run clear_stale_resume_token testhost testpool/ds
    assert_success
    [ ! -f "$TEST_TEMP_DIR/calls" ]
}

@test "clear_stale_resume_token clears a stale token automatically" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ssh() {
        if [[ "$*" == *receive_resume_token* ]]; then
            echo "1-fake-stale-token"
        elif [[ "$*" == *"receive -A"* ]]; then
            echo "RECEIVE_A_CALLED" >>"$TEST_TEMP_DIR/calls"
        fi
        return 0
    }
    # `zfs send -nvt <token>` dry-run fails => token is stale.
    sudo() {
        if [[ "$*" == *"zfs send -nvt"* ]]; then return 1; fi
        return 0
    }

    run clear_stale_resume_token testhost testpool/ds
    assert_success
    assert_output --partial "stale"
    [ -f "$TEST_TEMP_DIR/calls" ]
    grep -q RECEIVE_A_CALLED "$TEST_TEMP_DIR/calls"
}

@test "clear_stale_resume_token keeps a still-valid token" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ssh() {
        if [[ "$*" == *receive_resume_token* ]]; then
            echo "1-fake-valid-token"
        elif [[ "$*" == *"receive -A"* ]]; then
            echo "RECEIVE_A_CALLED" >>"$TEST_TEMP_DIR/calls"
        fi
        return 0
    }
    # `zfs send -nvt <token>` dry-run succeeds => token still valid.
    sudo() {
        if [[ "$*" == *"zfs send -nvt"* ]]; then return 0; fi
        return 0
    }

    run clear_stale_resume_token testhost testpool/ds
    assert_success
    assert_output --partial "still valid"
    [ ! -f "$TEST_TEMP_DIR/calls" ]
}

@test "run_syncoid_replication refuses a destination pool that is not ONLINE" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    check_host_reachable() { return 0; }
    syncoid() { echo "SYNCOID_SHOULD_NOT_RUN" >>"$TEST_TEMP_DIR/calls"; return 0; }
    ssh() { echo "SUSPENDED"; return 0; }

    run run_syncoid_replication "tank/src" "testhost:testpool/tank/src"
    assert_failure
    assert_output --partial "not ONLINE"
    [ ! -f "$TEST_TEMP_DIR/calls" ]
}

@test "run_syncoid_replication dry-run uses --no-sync-snap" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    check_host_reachable() { return 0; }
    syncoid() { return 0; }

    run run_syncoid_replication "tank/src" "testhost:testpool/tank/src" "dry-run"
    assert_success
    assert_output --partial "no-sync-snap"
}

# =============================================================================
# Additional coverage of correct behaviour (these pass against current code)
# =============================================================================

@test "clear_stale_resume_token reports when 'zfs receive -A' itself fails" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ssh() {
        if [[ "$*" == *receive_resume_token* ]]; then
            echo "1-fake-stale-token"
            return 0
        elif [[ "$*" == *"receive -A"* ]]; then
            return 1   # clearing the token fails
        fi
        return 0
    }
    sudo() {
        if [[ "$*" == *"zfs send -nvt"* ]]; then return 1; fi  # stale
        return 0
    }

    run clear_stale_resume_token testhost testpool/ds
    assert_failure
    assert_output --partial "could not clear stale resume token"
}

@test "run_syncoid_replication skips when host is unreachable" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    syncoid() { echo "SYNCOID_RAN" >>"$TEST_TEMP_DIR/calls"; return 0; }
    check_host_reachable() { return 1; }

    run run_syncoid_replication "tank/src" "testhost:testpool/tank/src"
    # Updated for the skip/fail classification: an unreachable host is
    # now a distinct SKIP outcome (BACKUP_SKIPPED), not plain success,
    # so the run summary can report ok/skipped/failed accurately. The
    # run still does not invoke syncoid and still continues.
    [ "$status" -eq "$BACKUP_SKIPPED" ]
    assert_output --partial "not reachable"
    [ ! -f "$TEST_TEMP_DIR/calls" ]
}

@test "run_syncoid_replication aborts if destination cannot be prepared" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    check_host_reachable() { return 0; }
    syncoid() { echo "SYNCOID_RAN" >>"$TEST_TEMP_DIR/calls"; return 0; }
    # Pool query => ONLINE; token query => a token; receive -A => fails.
    ssh() {
        if [[ "$*" == *"zpool list"* ]]; then echo "ONLINE"; return 0; fi
        if [[ "$*" == *receive_resume_token* ]]; then echo "1-tok"; return 0; fi
        if [[ "$*" == *"receive -A"* ]]; then return 1; fi
        return 0
    }
    sudo() {
        if [[ "$*" == *"zfs send -nvt"* ]]; then return 1; fi  # stale token
        return 0
    }

    run run_syncoid_replication "tank/src" "testhost:testpool/tank/src"
    assert_failure
    assert_output --partial "could not prepare destination"
    [ ! -f "$TEST_TEMP_DIR/calls" ]
}

# =============================================================================
# Bug-documenting tests.
#
# These assert the CORRECT behaviour and are EXPECTED TO FAIL against the
# current backup.sh. They are landed first (this commit) so the defect is
# on the record; the follow-up commit fixes backup.sh and turns them green.
#
#   BUG 1  clear_stale_resume_token: an ssh failure while querying the
#          token is silently treated as "no token" and the function
#          returns success, so a real stale token is never cleared and
#          the recurring replication failure is not healed.
#
#   BUG 2  syncoid_progress_heartbeat: the MiB/min rate is wrong for any
#          interval < 60s (divisor clamps to 1), and a decrease in
#          `used` (snapshot pruning mid-transfer) is logged as negative
#          "progress" instead of being floored to zero.
# =============================================================================

@test "BUG1: clear_stale_resume_token fails (not silent success) when ssh query fails" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # ssh cannot reach the host to read the token: non-zero, no output.
    ssh() { return 255; }
    sudo() { return 0; }

    run clear_stale_resume_token testhost testpool/ds
    # Correct behaviour: cannot determine token state => do NOT claim
    # success; signal the caller to skip this dataset this run.
    assert_failure
}

@test "BUG2a: syncoid_progress_heartbeat reports correct MiB/min for a 30s interval" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Make the loop iterate fast while still passing interval=30 to the
    # rate maths: override sleep so iterations are sub-second.
    sleep() { command sleep 0.3; }

    # Two readings 0 -> 60 MiB; with interval=30 the correct rate is
    # 60 MiB / 30s = 120 MiB/min.
    local counter="$TEST_TEMP_DIR/n"
    echo 0 >"$counter"
    ssh() {
        local n; n=$(cat "$counter"); echo $((n + 1)) >"$counter"
        if [ "$n" -eq 0 ]; then echo 0; else echo $((60 * 1024 * 1024)); fi
        return 0
    }

    syncoid_progress_heartbeat testhost testpool/ds 30 \
        >"$TEST_TEMP_DIR/hb.log" 2>&1 &
    local hb=$!
    command sleep 2
    kill "$hb" 2>/dev/null || true
    wait "$hb" 2>/dev/null || true

    run cat "$TEST_TEMP_DIR/hb.log"
    assert_output --partial "120 MiB/min"
}

@test "BUG2b: syncoid_progress_heartbeat does not report negative progress" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    sleep() { command sleep 0.3; }

    # used decreases (snapshots pruned mid-transfer): 100 MiB -> 50 MiB.
    local counter="$TEST_TEMP_DIR/n"
    echo 0 >"$counter"
    ssh() {
        local n; n=$(cat "$counter"); echo $((n + 1)) >"$counter"
        if [ "$n" -eq 0 ]; then echo $((100 * 1024 * 1024)); else echo $((50 * 1024 * 1024)); fi
        return 0
    }

    syncoid_progress_heartbeat testhost testpool/ds 1 \
        >"$TEST_TEMP_DIR/hb.log" 2>&1 &
    local hb=$!
    command sleep 2
    kill "$hb" 2>/dev/null || true
    wait "$hb" 2>/dev/null || true

    run cat "$TEST_TEMP_DIR/hb.log"
    # Must not log a negative delta like "+-50 MiB".
    refute_output --partial "+-"
}

# =============================================================================
# prepare_root_mount coverage (kcov: 0/48 lines - entirely untested).
# The suite never gets past the drive-not-connected early return; these
# exercise the early-return branches and, via the "pool already
# imported" path, the keystatus / mount / final-check body.
# These pass against the current code.
# =============================================================================

@test "prepare_root_mount fails when root backup is not configured" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ROOT_BACKUP_POOL=""
    ROOT_BACKUP_DATASET=""

    run prepare_root_mount
    assert_failure
    assert_output --partial "not configured"
}

@test "prepare_root_mount is a no-op when the CORRECT dataset is already mounted" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ROOT_BACKUP_POOL="silver"
    ROOT_BACKUP_DATASET="silver/clovis/root"
    mountpoint() { return 0; }                          # already mounted
    findmnt() { echo "silver/clovis/root"; return 0; }  # ...the right dataset

    run prepare_root_mount
    assert_success
    assert_output --partial "already mounted"
}

@test "prepare_root_mount fails when pool config file is missing" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ROOT_BACKUP_POOL="silver"
    ROOT_BACKUP_DATASET="silver/clovis/root"
    ROOT_BACKUP_CONFIG="doesnotexist"
    BACKUP_CONFIGS_DIR="$TEST_TEMP_DIR"
    mountpoint() { return 1; }   # not mounted
    zpool() { return 1; }        # pool not imported

    run prepare_root_mount
    assert_failure
    assert_output --partial "config file not found"
}

@test "prepare_root_mount fails when config has no BACKUP_DRIVE_ID" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ROOT_BACKUP_POOL="silver"
    ROOT_BACKUP_DATASET="silver/clovis/root"
    ROOT_BACKUP_CONFIG="silver"
    BACKUP_CONFIGS_DIR="$TEST_TEMP_DIR"
    echo 'SOME_OTHER_SETTING="x"' > "$TEST_TEMP_DIR/silver.conf"
    mountpoint() { return 1; }
    zpool() { return 1; }

    run prepare_root_mount
    assert_failure
    assert_output --partial "no BACKUP_DRIVE_ID"
}

@test "prepare_root_mount fails when the backup drive is not connected" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ROOT_BACKUP_POOL="silver"
    ROOT_BACKUP_DATASET="silver/clovis/root"
    ROOT_BACKUP_CONFIG="silver"
    BACKUP_CONFIGS_DIR="$TEST_TEMP_DIR"
    echo 'BACKUP_DRIVE_ID="usb-NoSuchDrive_000-0:0"' > "$TEST_TEMP_DIR/silver.conf"
    mountpoint() { return 1; }
    zpool() { return 1; }

    run prepare_root_mount
    assert_failure
    assert_output --partial "drive not connected"
}

@test "prepare_root_mount mounts via the already-imported-pool path" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ROOT_BACKUP_POOL="silver"
    ROOT_BACKUP_DATASET="silver/clovis/root"

    # mountpoint: not mounted, not mounted, then mounted (after zfs mount)
    local mpc="$TEST_TEMP_DIR/mpc"; echo 0 > "$mpc"
    mountpoint() {
        local n; n=$(cat "$mpc"); echo $((n + 1)) > "$mpc"
        [ "$n" -ge 2 ] && return 0 || return 1
    }
    zpool() { return 0; }   # pool already imported -> skips drive block
    sudo() {
        if [[ "$*" == *"keystatus"* ]]; then echo "available"; return 0; fi
        if [[ "$*" == *"zfs mount"* ]]; then return 0; fi
        return 0
    }

    run prepare_root_mount
    assert_success
    assert_output --partial "SUCCESS"
}

@test "prepare_root_mount fails when zfs load-key fails" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ROOT_BACKUP_POOL="silver"
    ROOT_BACKUP_DATASET="silver/clovis/root"
    mountpoint() { return 1; }
    zpool() { return 0; }
    sudo() {
        if [[ "$*" == *"keystatus"* ]]; then echo "unavailable"; return 0; fi
        if [[ "$*" == *"load-key"* ]]; then return 1; fi
        return 0
    }

    run prepare_root_mount
    assert_failure
    assert_output --partial "load-key"
}

@test "prepare_root_mount fails when zfs mount fails" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ROOT_BACKUP_POOL="silver"
    ROOT_BACKUP_DATASET="silver/clovis/root"
    mountpoint() { return 1; }   # never becomes mounted
    zpool() { return 0; }
    sudo() {
        if [[ "$*" == *"keystatus"* ]]; then echo "available"; return 0; fi
        if [[ "$*" == *"zfs mount"* ]]; then return 1; fi
        return 0
    }

    run prepare_root_mount
    assert_failure
    assert_output --partial "zfs mount"
}

# =============================================================================
# Bug-documenting test (EXPECTED TO FAIL against current code; fixed in
# the follow-up commit).
#
#   BUG-C  prepare_root_mount treats ANY filesystem mounted at /mnt/root
#          as success. It never verifies the mounted source is
#          ROOT_BACKUP_DATASET, so a stale/wrong dataset mounted there
#          causes run_root_backup to rsync the system root into the
#          wrong destination - a silent wrong-target backup.
# =============================================================================

@test "BUG-C: prepare_root_mount must reject a wrong dataset mounted at /mnt/root" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ROOT_BACKUP_POOL="silver"
    ROOT_BACKUP_DATASET="silver/clovis/root"

    mountpoint() { return 0; }                       # something IS mounted
    findmnt() { echo "georg/clovis/root"; return 0; } # ...but the WRONG dataset

    run prepare_root_mount
    # Correct behaviour: the mounted source is not ROOT_BACKUP_DATASET,
    # so this must NOT report success.
    assert_failure
}

# =============================================================================
# run_zfs_local_backup / run_all_zfs_local_backups / run_root_backup /
# run_all_backups coverage. These pass against the current code.
# =============================================================================

@test "run_zfs_local_backup dry-run does not invoke zbackup" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    zbackup() { echo "ZBACKUP_RAN" >>"$TEST_TEMP_DIR/calls"; return 0; }

    run run_zfs_local_backup "silver" "dry-run"
    assert_success
    assert_output --partial "would run: zbackup --config silver"
    [ ! -f "$TEST_TEMP_DIR/calls" ]
}

@test "run_all_zfs_local_backups dry-run iterates targets without running zbackup" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ZFS_BACKUP_TARGETS=("silver")
    zbackup() { echo "ZBACKUP_RAN" >>"$TEST_TEMP_DIR/calls"; return 0; }

    run run_all_zfs_local_backups "dry-run"
    assert_success
    assert_output --partial "[DRY-RUN]"
    assert_output --partial "processing ZFS backup target: silver"
    [ ! -f "$TEST_TEMP_DIR/calls" ]
}

@test "run_root_backup reports failure when rbackup fails with a non-23 code" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    rbackup() { return 5; }
    mountpoint() { return 0; }            # /mnt/root mounted -> proceeds

    run run_root_backup
    assert_failure
    assert_output --partial "rbackup failed"
}

# =============================================================================
#   BUG-E (EXPECTED TO FAIL against current code; fixed in follow-up).
#
#   bump's log_message uses only "$1" (echo "${STAMP}: ${lm_message}").
#   Every `log_message "msg" "detail"` call therefore discards the
#   detail. run_root_backup computes a pool diagnostic (keystatus,
#   mountpoint, mounted) and passes it as the SECOND argument, so it is
#   never actually logged - exactly the information needed to see why a
#   root backup was skipped is silently dropped.
#
#   Fix is scoped to backup.sh call sites (combine into one string);
#   bump is a shared submodule and is not changed here.
# =============================================================================

@test "BUG-E: run_root_backup actually logs pool diagnostics when /mnt/root not mounted" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ROOT_BACKUP_POOL="silver"
    ROOT_BACKUP_DATASET="silver/clovis/root"
    rbackup() { return 0; }
    mountpoint() { return 1; }            # not mounted
    zpool() { return 0; }                 # pool imported -> diagnostic branch
    sudo() {
        if [[ "$*" == *"keystatus"* ]]; then echo "available"; return 0; fi
        if [[ "$*" == *"mountpoint"* ]]; then echo "/mnt/root"; return 0; fi
        if [[ "$*" == *"mounted"* ]]; then echo "no"; return 0; fi
        return 0
    }

    run run_root_backup
    assert_success
    assert_output --partial "SKIPPED"
    # The pool diagnostic must reach the log, not be dropped as $2.
    assert_output --partial "keystatus="
}

@test "run_all_backups dry-run runs all phases and reports clean" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    run_root_backup() { return 0; }
    run_all_zfs_local_backups() { return 0; }
    run_all_syncoid_backups() { return 0; }

    run run_all_backups "dry-run"
    assert_success
    assert_output --partial "[DRY-RUN] run_all_backups"
    assert_output --partial "=== Root backup ==="
    assert_output --partial "=== Local ZFS backups ==="
    assert_output --partial "=== Syncoid replication ==="
    assert_output --partial "backup checks complete"
}

# =============================================================================
# Bug-documenting tests (EXPECTED TO FAIL against current code; fixed in
# the follow-up commit).
#
#   BUG-D  run_all_zfs_local_backups and run_all_syncoid_backups return 0
#          unconditionally, even when every sub-backup failed. As a
#          result run_all_backups' error counter never increments for
#          those phases and the run summary logs "backup checks
#          complete" while local ZFS and syncoid backups have silently
#          failed.
# =============================================================================

@test "BUG-D1: run_all_zfs_local_backups returns non-zero when a target fails" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ZFS_BACKUP_TARGETS=("silver")
    zbackup() { return 1; }   # the backup fails

    run run_all_zfs_local_backups
    # A failed sub-backup must be visible to the caller as non-zero,
    # so the run summary can report it (the run still continues).
    assert_failure
}

@test "BUG-D2: run_all_backups summary reports errors when a phase fails" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # Only the local-ZFS phase fails; the real run_all_zfs_local_backups
    # is exercised (a failing zbackup) so the bug is reproduced
    # end-to-end rather than stubbed away.
    run_root_backup() { return 0; }
    run_all_syncoid_backups() { return 0; }
    ZFS_BACKUP_TARGETS=("silver")
    zbackup() { return 1; }

    run run_all_backups
    assert_success    # run_all_backups itself never aborts
    assert_output --partial "error(s)"
}

# =============================================================================
# SKIP-vs-FAIL classification (EXPECTED TO FAIL against current code;
# implemented in the follow-up commit).
#
# A destination that is simply absent (drive not plugged in, mount
# missing, host down) is NOT a failure. It must be logged as SKIPPED,
# not counted as an error, and the routine must keep going. Only a
# genuine failure (a backup that should have worked) counts as an
# error in the summary. zbackup exits MISSING_DISK (63) when the
# external drive is not connected.
# =============================================================================

@test "SKIP1: run_zfs_local_backup treats a not-connected drive as skipped" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    zbackup() { return 63; }   # MISSING_DISK: drive not connected

    run run_zfs_local_backup "silver"
    # Must be reported as skipped, not as a backup failure.
    assert_output --partial "skipped"
    refute_output --partial "zbackup failed"
}

@test "SKIP2: run_all_zfs_local_backups does not count a skipped drive as failed" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    ZFS_BACKUP_TARGETS=("silver")
    zbackup() { return 63; }   # MISSING_DISK

    run run_all_zfs_local_backups
    assert_success   # a skip is not an error -> helper returns 0
    assert_output --partial "skipped"
    refute_output --partial "ZFS backup(s) failed"
}

@test "SKIP3: run_all_backups summary distinguishes skipped from failed" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    run_root_backup() { return 0; }
    run_all_syncoid_backups() { return 0; }
    ZFS_BACKUP_TARGETS=("silver")
    zbackup() { return 63; }   # MISSING_DISK -> skipped, not an error

    run run_all_backups
    assert_success
    assert_output --partial "skip"
    refute_output --partial "error(s)"
}
