#!/usr/bin/env bats
# Tests for resync.sh
#
# These tests verify the cloud resync standalone script.

load 'test_helper'

# =============================================================================
# Basic Loading Tests
# =============================================================================

@test "resync.sh has valid bash syntax" {
    run bash -n "${PROJECT_DIR}/resync.sh"
    assert_success
}

@test "resync.sh can be sourced" {
    source_project_file "resync.sh"
}

# =============================================================================
# Function Existence Tests
# =============================================================================

@test "show_usage function exists" {
    source_project_file "resync.sh"
    run type show_usage
    assert_success
    assert_output --partial "function"
}

@test "find_sync_entry function exists" {
    source_project_file "resync.sh"
    run type find_sync_entry
    assert_success
    assert_output --partial "function"
}

@test "run_resync function exists" {
    source_project_file "resync.sh"
    run type run_resync
    assert_success
    assert_output --partial "function"
}

@test "main function exists" {
    source_project_file "resync.sh"
    run type main
    assert_success
    assert_output --partial "function"
}

# =============================================================================
# find_sync_entry Tests
# =============================================================================

@test "find_sync_entry finds matching target" {
    source_project_file "resync.sh"

    CLOUD_SYNCS=("/home/user/cloud:google::bisync" "/home/user/docs:toby:docs:bisync")

    run find_sync_entry "google"
    assert_success
    assert_output "/home/user/cloud:google::bisync"
}

@test "find_sync_entry finds second target" {
    source_project_file "resync.sh"

    CLOUD_SYNCS=("/home/user/cloud:google::bisync" "/home/user/docs:toby:docs:bisync")

    run find_sync_entry "toby"
    assert_success
    assert_output "/home/user/docs:toby:docs:bisync"
}

@test "find_sync_entry returns failure for unknown target" {
    source_project_file "resync.sh"

    CLOUD_SYNCS=("/home/user/cloud:google::bisync")

    run find_sync_entry "nonexistent"
    assert_failure
}

@test "find_sync_entry handles empty CLOUD_SYNCS" {
    source_project_file "resync.sh"

    CLOUD_SYNCS=()

    run find_sync_entry "anything"
    assert_failure
}

# =============================================================================
# show_usage Tests
# =============================================================================

@test "show_usage lists available targets" {
    source_project_file "resync.sh"

    CLOUD_SYNCS=("/home/user/cloud:google::bisync" "/home/user/docs:toby:docs:sync")

    run show_usage
    assert_success
    assert_output --partial "google"
    assert_output --partial "toby"
    assert_output --partial "mode=bisync"
    assert_output --partial "mode=sync"
}

@test "show_usage handles empty config" {
    source_project_file "resync.sh"

    CLOUD_SYNCS=()

    run show_usage
    assert_success
    assert_output --partial "none configured"
}

@test "show_usage shows dry-run option" {
    source_project_file "resync.sh"

    CLOUD_SYNCS=()

    run show_usage
    assert_success
    assert_output --partial "--dry-run"
}

# =============================================================================
# run_resync Tests
# =============================================================================

@test "run_resync rejects invalid config" {
    source_project_file "resync.sh"
    set_stamp

    run run_resync "invalid" "no"
    assert_failure
    assert_output --partial "invalid sync config"
}

@test "run_resync rejects missing local path" {
    source_project_file "resync.sh"
    set_stamp

    # Mock cleanup to avoid exit
    cleanup() { return "${1:-0}"; }

    run run_resync "/nonexistent/path:remote::bisync" "no"
    assert_failure
    assert_output --partial "does not exist"
}

@test "run_resync reports unknown mode" {
    source_project_file "resync.sh"
    set_stamp

    local test_dir="${TEST_TEMP_DIR}/resync_test"
    mkdir -p "$test_dir"

    # Mock cleanup and rclone to avoid real operations
    cleanup() { return "${1:-0}"; }
    rclone() { return 0; }

    run run_resync "${test_dir}:remote::badmode" "no"
    assert_failure
    assert_output --partial "unknown sync mode"
}

@test "run_resync falls back to sync for sync mode" {
    source_project_file "resync.sh"
    set_stamp

    local test_dir="${TEST_TEMP_DIR}/resync_sync"
    mkdir -p "$test_dir"

    # Mock rclone to capture command
    rclone() {
        echo "rclone $*"
        return 0
    }

    run run_resync "${test_dir}:remote::sync" "no"
    assert_success
    assert_output --partial "mode is sync"
}

@test "run_resync falls back to copy for copy mode" {
    source_project_file "resync.sh"
    set_stamp

    local test_dir="${TEST_TEMP_DIR}/resync_copy"
    mkdir -p "$test_dir"

    # Mock rclone to capture command
    rclone() {
        echo "rclone $*"
        return 0
    }

    run run_resync "${test_dir}:remote::copy" "no"
    assert_success
    assert_output --partial "mode is copy"
}

@test "run_resync includes --resync for bisync mode" {
    source_project_file "resync.sh"
    set_stamp

    local test_dir="${TEST_TEMP_DIR}/resync_bisync"
    mkdir -p "$test_dir"

    # Mock rclone to capture the full command
    rclone() {
        echo "RCLONE_CMD: $*"
        return 0
    }

    run run_resync "${test_dir}:remote::bisync" "no"
    assert_success
    assert_output --partial "--resync"
}

@test "run_resync passes --dry-run for bisync mode" {
    source_project_file "resync.sh"
    set_stamp

    local test_dir="${TEST_TEMP_DIR}/resync_dryrun"
    mkdir -p "$test_dir"

    # Mock rclone
    rclone() {
        echo "RCLONE_CMD: $*"
        return 0
    }

    run run_resync "${test_dir}:remote::bisync" "yes"
    assert_success
    assert_output --partial "DRY RUN"
    assert_output --partial "--dry-run"
}

# =============================================================================
# Integration Tests (sourcing guard)
# =============================================================================

@test "resync.sh sourcing guard prevents main from running" {
    # Sourcing should not call main
    source_project_file "resync.sh"

    # If we get here without error, the guard worked
    assert [ "$(type -t main)" = "function" ]
}
