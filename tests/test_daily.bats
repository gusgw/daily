#!/usr/bin/env bats
# Tests for daily.sh
#
# These tests verify the main orchestrator sources modules correctly
# and has the correct execution flow.

load 'test_helper'

# =============================================================================
# Basic Syntax Tests
# =============================================================================

@test "daily.sh has valid bash syntax" {
    run bash -n "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh has shebang" {
    local first_line
    first_line=$(head -1 "${PROJECT_DIR}/daily.sh")
    [[ "$first_line" == "#!/bin/bash" ]]
}

# =============================================================================
# Module Source Tests
# =============================================================================

@test "daily.sh sources bump.sh" {
    run grep -q 'safe_source.*bump/bump.sh' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh sources settings.sh" {
    run grep -q 'safe_source.*settings.sh' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh sources network.sh" {
    run grep -q 'safe_source.*network.sh' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh sources system.sh" {
    run grep -q 'safe_source.*system.sh' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh sources package.sh" {
    run grep -q 'safe_source.*package.sh' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh sources backup.sh" {
    run grep -q 'safe_source.*backup.sh' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh sources sensitive.sh" {
    run grep -q 'safe_source.*sensitive.sh' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh sources cloud.sh" {
    run grep -q 'safe_source.*cloud.sh' "${PROJECT_DIR}/daily.sh"
    assert_success
}

# =============================================================================
# Obsolete Module Removal Tests
# =============================================================================

@test "daily.sh does not source magpie.sh (removed)" {
    run grep -q 'magpie.sh' "${PROJECT_DIR}/daily.sh"
    assert_failure
}

@test "daily.sh does not source bug.sh (removed)" {
    run grep -q 'bug.sh' "${PROJECT_DIR}/daily.sh"
    assert_failure
}

# =============================================================================
# New Function Call Tests
# =============================================================================

@test "daily.sh calls network_check" {
    run grep -q 'network_check' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh calls system_check" {
    run grep -q 'system_check' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh calls run_all_health_checks" {
    run grep -q 'run_all_health_checks' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh calls run_package_maintenance" {
    run grep -q 'run_package_maintenance' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh calls run_all_backups" {
    run grep -q 'run_all_backups' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh calls run_all_cloud_syncs" {
    run grep -q 'run_all_cloud_syncs' "${PROJECT_DIR}/daily.sh"
    assert_success
}

# =============================================================================
# Obsolete Function Removal Tests
# =============================================================================

@test "daily.sh does not call run_local_backup (removed)" {
    run grep -q 'run_local_backup' "${PROJECT_DIR}/daily.sh"
    assert_failure
}

@test "daily.sh does not call run_archive (removed)" {
    run grep -q 'run_archive' "${PROJECT_DIR}/daily.sh"
    assert_failure
}

@test "daily.sh does not call run_shared_preparation (removed)" {
    run grep -q 'run_shared_preparation' "${PROJECT_DIR}/daily.sh"
    assert_failure
}

@test "daily.sh does not call all_remote_backups (removed)" {
    run grep -q 'all_remote_backups' "${PROJECT_DIR}/daily.sh"
    assert_failure
}

@test "daily.sh does not call set_month (no longer needed)" {
    run grep -q 'set_month' "${PROJECT_DIR}/daily.sh"
    assert_failure
}

# =============================================================================
# Execution Order Tests
# =============================================================================

@test "daily.sh calls network_check before system_check" {
    local network_line system_line
    network_line=$(grep -n 'network_check' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    system_line=$(grep -n 'system_check' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    [ "$network_line" -lt "$system_line" ]
}

@test "daily.sh calls system_check before run_all_health_checks" {
    local system_line health_line
    system_line=$(grep -n 'system_check' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    health_line=$(grep -n 'run_all_health_checks' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    [ "$system_line" -lt "$health_line" ]
}

@test "daily.sh calls run_all_health_checks before run_package_maintenance" {
    local health_line package_line
    health_line=$(grep -n 'run_all_health_checks' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    package_line=$(grep -n 'run_package_maintenance' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    [ "$health_line" -lt "$package_line" ]
}

@test "daily.sh calls run_package_maintenance before run_all_backups" {
    local package_line backup_line
    package_line=$(grep -n 'run_package_maintenance' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    backup_line=$(grep -n 'run_all_backups' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    [ "$package_line" -lt "$backup_line" ]
}

@test "daily.sh calls run_all_backups before run_all_cloud_syncs" {
    local backup_line cloud_line
    backup_line=$(grep -n 'run_all_backups' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    cloud_line=$(grep -n 'run_all_cloud_syncs' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    [ "$backup_line" -lt "$cloud_line" ]
}

@test "daily.sh calls cleanup at the end" {
    local cloud_line cleanup_line
    cloud_line=$(grep -n 'run_all_cloud_syncs' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    cleanup_line=$(grep -n 'cleanup 0' "${PROJECT_DIR}/daily.sh" | head -1 | cut -d: -f1)
    [ "$cloud_line" -lt "$cleanup_line" ]
}

# =============================================================================
# Lock File Tests
# =============================================================================

@test "daily.sh uses lock file for concurrency control" {
    run grep -q 'LOCKFILE=' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh uses flock for locking" {
    run grep -q 'flock' "${PROJECT_DIR}/daily.sh"
    assert_success
}

# =============================================================================
# Signal Handling Tests
# =============================================================================

@test "daily.sh sets up signal trap" {
    run grep -q 'trap handle_signal' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh calls set_stamp for timestamp" {
    run grep -q 'set_stamp' "${PROJECT_DIR}/daily.sh"
    assert_success
}

# =============================================================================
# Safe Source Function Tests
# =============================================================================

@test "daily.sh defines safe_source function" {
    run grep -q 'safe_source()' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "safe_source checks file exists" {
    run grep -q '\-f.*file' "${PROJECT_DIR}/daily.sh"
    assert_success
}

# =============================================================================
# Integration Tests
# =============================================================================

@test "all modules can be sourced together without error" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "system.sh"
    source_project_file "package.sh"
    source_project_file "backup.sh"
    source_project_file "sensitive.sh"
    run source_project_file "cloud.sh"
    assert_success
}

@test "all required functions exist after sourcing modules" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "system.sh"
    source_project_file "package.sh"
    source_project_file "backup.sh"
    source_project_file "sensitive.sh"
    source_project_file "cloud.sh"

    # Check key functions exist
    type network_check &>/dev/null
    type system_check &>/dev/null
    type run_all_health_checks &>/dev/null
    type run_package_maintenance &>/dev/null
    type run_all_backups &>/dev/null
    type run_all_cloud_syncs &>/dev/null
    type cleanup &>/dev/null
}

# =============================================================================
# Command Line Argument Tests
# =============================================================================

@test "daily.sh --help shows usage information" {
    run "${PROJECT_DIR}/daily.sh" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "--dry-run"
}

@test "daily.sh -h shows usage information" {
    run "${PROJECT_DIR}/daily.sh" -h
    assert_success
    assert_output --partial "Usage:"
}

@test "daily.sh supports --dry-run flag" {
    run grep -q '\-\-dry-run' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh supports -n short flag for dry-run" {
    run grep -q '\-n|--dry-run' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh passes DRY_RUN to run_all_backups" {
    run grep -q 'run_all_backups.*DRY_RUN' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh passes DRY_RUN to run_all_cloud_syncs" {
    run grep -q 'run_all_cloud_syncs.*DRY_RUN' "${PROJECT_DIR}/daily.sh"
    assert_success
}

@test "daily.sh rejects unknown options" {
    run "${PROJECT_DIR}/daily.sh" --invalid-option
    assert_failure
    assert_output --partial "Unknown option"
}

# =============================================================================
# Backup Dry-Run Tests
# =============================================================================

@test "run_all_backups accepts dry-run parameter" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    run run_all_backups "dry-run"
    assert_success
    assert_output --partial "DRY-RUN"
}

@test "run_syncoid_replication supports dry-run" {
    # Check that dry-run mode is handled (syncoid has no --dryrun option,
    # so we skip calling it and print what would be done)
    run grep -q 'DRY-RUN.*would run.*syncoid' "${PROJECT_DIR}/backup.sh"
    assert_success
}
