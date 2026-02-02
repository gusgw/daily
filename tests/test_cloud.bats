#!/usr/bin/env bats
# Tests for cloud.sh
#
# These tests verify rclone sync functions.

load 'test_helper'

# =============================================================================
# Basic Loading Tests
# =============================================================================

@test "cloud.sh can be sourced" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    run source_project_file "cloud.sh"
    assert_success
}

@test "cloud.sh has valid bash syntax" {
    run bash -n "${PROJECT_DIR}/cloud.sh"
    assert_success
}

# =============================================================================
# Function Existence Tests
# =============================================================================

@test "run_rclone_bisync function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"
    run type run_rclone_bisync
    assert_success
    assert_output --partial "function"
}

@test "run_rclone_sync function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"
    run type run_rclone_sync
    assert_success
    assert_output --partial "function"
}

@test "run_rclone_copy function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"
    run type run_rclone_copy
    assert_success
    assert_output --partial "function"
}

@test "run_cloud_sync function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"
    run type run_cloud_sync
    assert_success
    assert_output --partial "function"
}

@test "run_all_cloud_syncs function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"
    run type run_all_cloud_syncs
    assert_success
    assert_output --partial "function"
}

# =============================================================================
# Old Functions Removed
# =============================================================================

@test "run_archive function does not exist (removed)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"
    run type run_archive
    assert_failure
}

@test "cleanup_run_archive function does not exist (removed)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"
    run type cleanup_run_archive
    assert_failure
}

@test "run_shared_preparation function does not exist (removed)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"
    run type run_shared_preparation
    assert_failure
}

@test "cleanup_shared_preparation function does not exist (removed)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"
    run type cleanup_shared_preparation
    assert_failure
}

# =============================================================================
# Cloud Sync Configuration Tests
# =============================================================================

@test "run_all_cloud_syncs handles empty config array" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    # Explicitly set empty array for testing
    CLOUD_SYNCS=()
    run run_all_cloud_syncs
    assert_success
    assert_output --partial "no cloud syncs configured"
}

@test "CLOUD_SYNCS array is accessible" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    declare -p CLOUD_SYNCS &>/dev/null
}

@test "run_cloud_sync rejects invalid config format" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    run run_cloud_sync "invalid"
    assert_failure
    assert_output --partial "invalid sync config"
}

@test "run_cloud_sync rejects config with missing path" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    run run_cloud_sync "/nonexistent:remote:path"
    assert_failure
    assert_output --partial "does not exist"
}

# =============================================================================
# Rclone Command Tests
# =============================================================================

@test "run_rclone_bisync checks for rclone command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    if ! command -v rclone &>/dev/null; then
        run run_rclone_bisync "/tmp" "remote:path"
        assert_failure
        assert_output --partial "rclone command not found"
    else
        # rclone exists - will fail on non-existent remote
        run run_rclone_bisync "/nonexistent" "remote:path"
        assert_failure
    fi
}

@test "run_rclone_sync checks for rclone command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    if ! command -v rclone &>/dev/null; then
        run run_rclone_sync "/tmp" "remote:path"
        assert_failure
        assert_output --partial "rclone command not found"
    fi
}

@test "run_rclone_copy checks for rclone command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    if ! command -v rclone &>/dev/null; then
        run run_rclone_copy "/tmp" "remote:path"
        assert_failure
        assert_output --partial "rclone command not found"
    fi
}

# =============================================================================
# Sync Mode Tests
# =============================================================================

@test "run_cloud_sync supports bisync mode" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    # Create a temp directory to pass path check
    local test_dir="${TEST_TEMP_DIR}/sync_test"
    mkdir -p "$test_dir"

    # Will fail on remote, but should recognize mode
    run run_cloud_sync "${test_dir}:remote:path:bisync"
    # Either succeeds (if rclone works) or fails with rclone error (not mode error)
    [[ "$output" != *"unknown sync mode"* ]]
}

@test "run_cloud_sync supports sync mode" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    local test_dir="${TEST_TEMP_DIR}/sync_test2"
    mkdir -p "$test_dir"

    run run_cloud_sync "${test_dir}:remote:path:sync"
    [[ "$output" != *"unknown sync mode"* ]]
}

@test "run_cloud_sync supports copy mode" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    local test_dir="${TEST_TEMP_DIR}/sync_test3"
    mkdir -p "$test_dir"

    run run_cloud_sync "${test_dir}:remote:path:copy"
    [[ "$output" != *"unknown sync mode"* ]]
}

@test "run_cloud_sync rejects invalid mode" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    local test_dir="${TEST_TEMP_DIR}/sync_test4"
    mkdir -p "$test_dir"

    run run_cloud_sync "${test_dir}:remote:path:invalid_mode"
    assert_failure
    assert_output --partial "unknown sync mode"
}

# =============================================================================
# Dry-Run Tests
# =============================================================================

@test "run_rclone_bisync supports dry-run parameter" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    skip_if_no_command rclone

    local test_dir="${TEST_TEMP_DIR}/dryrun_test"
    mkdir -p "$test_dir"

    run run_rclone_bisync "$test_dir" "nonexistent:path" "dry-run"
    assert_output --partial "DRY RUN"
}

@test "run_all_cloud_syncs passes dry-run to individual syncs" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    # With empty array, just verify function accepts parameter
    run run_all_cloud_syncs "dry-run"
    assert_success
}

# =============================================================================
# Settings Integration Tests
# =============================================================================

@test "cloud functions use SIMULTANEOUS_TRANSFERS from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    assert [ -n "$SIMULTANEOUS_TRANSFERS" ]
}
