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

    # With empty target arrays, should complete successfully
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
        # syncoid exists - will fail on unreachable host
        run run_syncoid_replication "test/dataset" "user@192.0.2.1:test/dest"
        assert_success  # Returns 0 when host not reachable (skipped)
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
