#!/usr/bin/env bats
# Tests for package.sh
#
# These tests verify package maintenance functions.

load 'test_helper'

# =============================================================================
# Basic Loading Tests
# =============================================================================

@test "package.sh can be sourced" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    run source_project_file "package.sh"
    assert_success
}

@test "package.sh has valid bash syntax" {
    run bash -n "${PROJECT_DIR}/package.sh"
    assert_success
}

# =============================================================================
# Function Existence Tests
# =============================================================================

@test "run_package_maintenance function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "package.sh"
    run type run_package_maintenance
    assert_success
    assert_output --partial "function"
}

@test "cleanup_package_maintenance function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "package.sh"
    run type cleanup_package_maintenance
    assert_success
    assert_output --partial "function"
}

# =============================================================================
# Phase 12 Bug Fix Tests
# =============================================================================

@test "run_package_maintenance includes AUR update with yay" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "package.sh"

    # Check that the function contains yay -Sua
    run declare -f run_package_maintenance
    assert_success
    assert_output --partial "yay"
    assert_output --partial "-Sua"
}
