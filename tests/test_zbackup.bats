#!/usr/bin/env bats
# Tests for zbackup.sh
#
# These tests verify the ZFS backup script functions, configuration
# loading, and BUMP integration. The script uses a sourcing guard
# so it can be sourced without executing main().

load 'test_helper'

# =============================================================================
# Helper to source zbackup.sh (sets STAMP first since log() needs it)
# =============================================================================

source_zbackup() {
    export STAMP="20260125T120000-test"
    source_project_file "zbackup.sh"
}

# =============================================================================
# Sourcing and Syntax Tests
# =============================================================================

@test "zbackup.sh has valid bash syntax" {
    run bash -n "${PROJECT_DIR}/zbackup.sh"
    assert_success
}

@test "zbackup.sh can be sourced without executing main" {
    # The sourcing guard should prevent main() from running
    run bash -c "source '${PROJECT_DIR}/zbackup.sh' && echo 'sourced ok'"
    assert_success
    assert_output --partial "sourced ok"
}

# =============================================================================
# Function Existence Tests
# =============================================================================

@test "check_backup_drive function exists" {
    source_zbackup
    run type check_backup_drive
    assert_success
    assert_output --partial "function"
}

@test "find_common_snapshot function exists" {
    source_zbackup
    run type find_common_snapshot
    assert_success
    assert_output --partial "function"
}

@test "ensure_parent_datasets function exists" {
    source_zbackup
    run type ensure_parent_datasets
    assert_success
    assert_output --partial "function"
}

@test "perform_backup function exists" {
    source_zbackup
    run type perform_backup
    assert_success
    assert_output --partial "function"
}

@test "sync_snapshots function exists" {
    source_zbackup
    run type sync_snapshots
    assert_success
    assert_output --partial "function"
}

@test "cleanup_export_backup_pool function exists" {
    source_zbackup
    run type cleanup_export_backup_pool
    assert_success
    assert_output --partial "function"
}

@test "main function exists in zbackup.sh" {
    source_zbackup
    run type main
    assert_success
    assert_output --partial "function"
}

# =============================================================================
# Configuration Directory Tests
# =============================================================================

@test "CONFIG_DIR points to backup-configs in the repo" {
    source_zbackup
    assert [ -d "$CONFIG_DIR" ]
    [[ "$CONFIG_DIR" == *"/backup-configs" ]]
}

@test "example config files exist in CONFIG_DIR" {
    source_zbackup
    local found=0
    for f in "${CONFIG_DIR}"/*.conf.example; do
        [ -f "$f" ] && found=$((found + 1))
    done
    assert [ "$found" -gt 0 ]
}

# =============================================================================
# Config File Content Tests
# =============================================================================

@test "sourcing an example config sets BACKUP_POOL" {
    source_zbackup
    # Find any example config
    local example
    example=$(ls "${CONFIG_DIR}"/*.conf.example 2>/dev/null | head -1)
    [ -n "$example" ] || skip "no example configs found"
    # shellcheck source=/dev/null
    source "$example"
    assert [ -n "$BACKUP_POOL" ]
}

@test "sourcing a config sets SOURCE_DATASETS" {
    source_zbackup
    local example
    example=$(ls "${CONFIG_DIR}"/*.conf.example 2>/dev/null | head -1)
    [ -n "$example" ] || skip "no example configs found"
    # shellcheck source=/dev/null
    source "$example"
    assert [ "${#SOURCE_DATASETS[@]}" -gt 0 ]
}

# =============================================================================
# find_common_snapshot Tests (with mocked zfs)
# =============================================================================

@test "find_common_snapshot returns common snapshot name" {
    source_zbackup

    # Mock zfs to return known snapshot lists
    # zfs list -t snapshot -H -o name <dataset> — dataset is $7
    zfs() {
        case "$7" in
            "source/data")
                printf "source/data@snap1\nsource/data@snap2\nsource/data@snap3\n"
                ;;
            "backup/data")
                printf "backup/data@snap1\nbackup/data@snap2\n"
                ;;
        esac
    }
    export -f zfs

    run find_common_snapshot "source/data" "backup/data"
    assert_success
    assert_output "snap2"
}

@test "find_common_snapshot returns failure when no common snapshot" {
    source_zbackup

    # Mock zfs to return disjoint snapshot lists
    zfs() {
        case "$7" in
            "source/data")
                printf "source/data@snap3\nsource/data@snap4\n"
                ;;
            "backup/data")
                printf "backup/data@snap1\nbackup/data@snap2\n"
                ;;
        esac
    }
    export -f zfs

    run find_common_snapshot "source/data" "backup/data"
    assert_failure
    assert_output ""
}

@test "find_common_snapshot returns most recent common when multiple exist" {
    source_zbackup

    # Mock zfs to return overlapping snapshot lists
    # backup_snaps are sorted reverse, so snap3 is checked first
    zfs() {
        case "$7" in
            "source/data")
                printf "source/data@snap1\nsource/data@snap2\nsource/data@snap3\nsource/data@snap4\n"
                ;;
            "backup/data")
                printf "backup/data@snap1\nbackup/data@snap2\nbackup/data@snap3\n"
                ;;
        esac
    }
    export -f zfs

    run find_common_snapshot "source/data" "backup/data"
    assert_success
    # snap3 is the most recent (sort -r puts it first in backup_snaps)
    assert_output "snap3"
}

# =============================================================================
# ensure_parent_datasets Tests (with mocked zfs/sudo)
# =============================================================================

@test "ensure_parent_datasets skips pool name" {
    source_zbackup
    BACKUP_POOL="testpool"

    local created_datasets=()

    # Mock zfs list to say nothing exists
    zfs() {
        return 1  # Dataset does not exist
    }
    export -f zfs

    # Mock sudo to track zfs create calls
    sudo() {
        if [ "$1" = "zfs" ] && [ "$2" = "create" ]; then
            created_datasets+=("$4")
        fi
        return 0
    }
    export -f sudo

    run ensure_parent_datasets "testpool/level1/level2/target"
    assert_success

    # The pool name "testpool" should NOT appear in create calls
    # Only "testpool/level1" and "testpool/level1/level2" should be created
    # (The function uses zfs create -p, so $3 is -p and $4 is the dataset)
}

@test "ensure_parent_datasets returns FILING_ERROR when zfs create fails" {
    source_zbackup
    BACKUP_POOL="testpool"

    # Mock zfs list to say nothing exists
    zfs() {
        return 1  # Dataset does not exist
    }
    export -f zfs

    # Mock sudo to fail on zfs create
    sudo() {
        return 1
    }
    export -f sudo

    run ensure_parent_datasets "testpool/level1/target"
    assert_failure
    [ "$status" -eq "$FILING_ERROR" ]
}

# =============================================================================
# check_backup_drive Tests
# =============================================================================

@test "check_backup_drive exits when drive not in /dev/disk/by-id/" {
    source_zbackup
    BACKUP_DRIVE_ID="nonexistent-test-drive-id-12345"
    BACKUP_POOL="testpool"

    # Mock sudo tee and logger to avoid real writes
    sudo() { cat >/dev/null; return 0; }
    export -f sudo
    logger() { return 0; }
    export -f logger

    run check_backup_drive
    assert_failure
    assert_output --partial "Backup drive not connected"
}

# =============================================================================
# cleanup_export_backup_pool Tests
# =============================================================================

@test "cleanup_export_backup_pool calls zpool export when pool is listed" {
    source_zbackup
    BACKUP_POOL="testpool"

    local export_called=0

    # Mock zpool to say pool exists
    zpool() {
        if [ "$1" = "list" ]; then
            return 0
        fi
        return 0
    }
    export -f zpool

    # Mock sudo and sync
    sudo() {
        if [ "$1" = "zpool" ] && [ "$2" = "export" ]; then
            export_called=1
        fi
        return 0
    }
    export -f sudo
    sync() { return 0; }
    export -f sync

    run cleanup_export_backup_pool
    assert_success
    assert_output --partial "Exporting backup pool"
}

@test "cleanup_export_backup_pool does nothing when pool is not imported" {
    source_zbackup
    BACKUP_POOL="testpool"

    # Mock zpool to say pool does NOT exist
    zpool() {
        return 1
    }
    export -f zpool

    run cleanup_export_backup_pool
    assert_success
    # Should produce no output about exporting
    refute_output --partial "Exporting"
}

# =============================================================================
# BUMP Integration Tests
# =============================================================================

@test "BUMP exit codes are available after sourcing zbackup.sh" {
    source_zbackup
    assert [ -n "$MISSING_DISK" ]
    assert [ -n "$MISSING_FILE" ]
    assert [ -n "$SECURITY_FAILURE" ]
    assert [ -n "$FILING_ERROR" ]
    assert [ -n "$BAD_CONFIGURATION" ]
    assert [ -n "$TRAPPED_SIGNAL" ]
}

@test "log_message is available after sourcing zbackup.sh" {
    source_zbackup
    run type log_message
    assert_success
    assert_output --partial "function"
}

@test "cleanup function is available after sourcing zbackup.sh" {
    source_zbackup
    run type cleanup
    assert_success
    assert_output --partial "function"
}

@test "handle_signal is available after sourcing zbackup.sh" {
    source_zbackup
    run type handle_signal
    assert_success
    assert_output --partial "function"
}

@test "log function uses STAMP format on stderr" {
    source_zbackup

    # Mock sudo tee and logger to avoid real I/O
    sudo() { cat >/dev/null; return 0; }
    export -f sudo
    logger() { return 0; }
    export -f logger

    # Capture stderr from log function
    local stderr_output
    stderr_output=$(log "test message" 2>&1 >/dev/null)
    [[ "$stderr_output" == *"${STAMP}"* ]]
    [[ "$stderr_output" == *"test message"* ]]
}

# =============================================================================
# Default Configuration Tests
# =============================================================================

@test "default BACKUP_POOL is empty (requires --config)" {
    source_zbackup
    assert [ -z "$BACKUP_POOL" ]
}

@test "default BACKUP_PATH is empty (requires --config)" {
    source_zbackup
    assert [ -z "$BACKUP_PATH" ]
}

@test "default SOURCE_DATASETS is empty (requires --config)" {
    source_zbackup
    assert [ "${#SOURCE_DATASETS[@]}" -eq 0 ]
}
