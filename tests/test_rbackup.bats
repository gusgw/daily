#!/usr/bin/env bats
# Tests for rbackup.sh
#
# These tests verify the root filesystem backup script functions,
# mountpoint checking, rsync exit code handling, and BUMP integration.

load 'test_helper'

# =============================================================================
# Helper to source rbackup.sh (sets STAMP first since log_message needs it)
# =============================================================================

source_rbackup() {
    export STAMP="20260125T120000-test"
    source_project_file "rbackup.sh"
}

# =============================================================================
# Sourcing and Syntax Tests
# =============================================================================

@test "rbackup.sh has valid bash syntax" {
    run bash -n "${PROJECT_DIR}/rbackup.sh"
    assert_success
}

@test "rbackup.sh can be sourced without executing main" {
    # The sourcing guard should prevent main() from running
    run bash -c "source '${PROJECT_DIR}/rbackup.sh' && echo 'sourced ok'"
    assert_success
    assert_output --partial "sourced ok"
}

# =============================================================================
# Function Existence Tests
# =============================================================================

@test "run_root_rsync function exists" {
    source_rbackup
    run type run_root_rsync
    assert_success
    assert_output --partial "function"
}

@test "main function exists in rbackup.sh" {
    source_rbackup
    run type main
    assert_success
    assert_output --partial "function"
}

# =============================================================================
# Mountpoint Check Tests
# =============================================================================

@test "main exits with MISSING_MOUNT when /mnt/root is not mounted" {
    source_rbackup

    # Mock mountpoint to return failure
    mountpoint() {
        return 1
    }
    export -f mountpoint

    run main
    assert_failure
    [ "$status" -eq "$MISSING_MOUNT" ]
    assert_output --partial "/mnt/root is not mounted"
}

# =============================================================================
# Rsync Exit Code Handling Tests
# =============================================================================

@test "main returns 0 on successful rsync" {
    source_rbackup

    # Mock mountpoint to succeed
    mountpoint() { return 0; }
    export -f mountpoint

    # Mock run_root_rsync to succeed
    run_root_rsync() { return 0; }
    export -f run_root_rsync

    run main
    assert_success
    assert_output --partial "backup completed"
}

@test "main returns 0 on rsync exit 23 (partial transfer)" {
    source_rbackup

    # Mock mountpoint to succeed
    mountpoint() { return 0; }
    export -f mountpoint

    # Mock run_root_rsync to exit with 23
    run_root_rsync() { return 23; }
    export -f run_root_rsync

    run main
    assert_success
    assert_output --partial "partial transfer"
}

@test "main returns failure on other rsync exit codes" {
    source_rbackup

    # Mock mountpoint to succeed
    mountpoint() { return 0; }
    export -f mountpoint

    # Mock run_root_rsync to exit with error
    run_root_rsync() { return 12; }
    export -f run_root_rsync

    run main
    assert_failure
    assert_output --partial "rsync failed"
}

# =============================================================================
# BUMP Integration Tests
# =============================================================================

@test "BUMP exit codes are available after sourcing rbackup.sh" {
    source_rbackup
    assert [ -n "$MISSING_MOUNT" ]
    assert [ -n "$MISSING_FILE" ]
    assert [ -n "$TRAPPED_SIGNAL" ]
}

@test "log_message is available after sourcing rbackup.sh" {
    source_rbackup
    run type log_message
    assert_success
    assert_output --partial "function"
}

@test "cleanup function is available after sourcing rbackup.sh" {
    source_rbackup
    run type cleanup
    assert_success
    assert_output --partial "function"
}

@test "handle_signal is available after sourcing rbackup.sh" {
    source_rbackup
    run type handle_signal
    assert_success
    assert_output --partial "function"
}
