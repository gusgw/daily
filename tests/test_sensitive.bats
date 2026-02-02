#!/usr/bin/env bats
# Tests for sensitive.sh
#
# These tests verify sensitive file detection and exclusion functions.

load 'test_helper'

# =============================================================================
# Basic Loading Tests
# =============================================================================

@test "sensitive.sh can be sourced" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    run source_project_file "sensitive.sh"
    assert_success
}

@test "sensitive.sh has valid bash syntax" {
    run bash -n "${PROJECT_DIR}/sensitive.sh"
    assert_success
}

# =============================================================================
# Function Existence Tests
# =============================================================================

@test "check_sensitive_files function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    run type check_sensitive_files
    assert_success
    assert_output --partial "function"
}

@test "build_rclone_excludes function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    run type build_rclone_excludes
    assert_success
    assert_output --partial "function"
}

@test "get_rclone_exclude_array function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    run type get_rclone_exclude_array
    assert_success
    assert_output --partial "function"
}

@test "remove_sensitive_data function exists (legacy)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"
    run type remove_sensitive_data
    assert_success
    assert_output --partial "function"
}

# =============================================================================
# Old Functions Removed
# =============================================================================

# No old functions were removed from sensitive.sh - all kept or enhanced

# =============================================================================
# Sensitive File Detection Tests
# =============================================================================

@test "check_sensitive_files returns failure with no argument" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    run check_sensitive_files ""
    assert_failure
}

@test "check_sensitive_files returns failure for non-existent directory" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    run check_sensitive_files "/nonexistent/path/12345"
    assert_failure
}

@test "check_sensitive_files returns success for clean directory" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    # Create a clean temp directory
    local clean_dir="${TEST_TEMP_DIR}/clean_test"
    mkdir -p "$clean_dir"
    touch "$clean_dir/safe_file.txt"

    run check_sensitive_files "$clean_dir"
    assert_success
    assert_output --partial "No sensitive files found"
}

@test "check_sensitive_files detects .ssh folder" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    # Create a directory with .ssh
    local test_dir="${TEST_TEMP_DIR}/ssh_test"
    mkdir -p "$test_dir/.ssh"

    run check_sensitive_files "$test_dir"
    assert_failure
    assert_output --partial ".ssh"
}

@test "check_sensitive_files detects .gnupg folder" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    local test_dir="${TEST_TEMP_DIR}/gnupg_test"
    mkdir -p "$test_dir/.gnupg"

    run check_sensitive_files "$test_dir"
    assert_failure
    assert_output --partial ".gnupg"
}

@test "check_sensitive_files detects key files" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    local test_dir="${TEST_TEMP_DIR}/key_test"
    mkdir -p "$test_dir"
    touch "$test_dir/secret.key"

    run check_sensitive_files "$test_dir"
    assert_failure
    assert_output --partial "*.key"
}

@test "check_sensitive_files detects .git folder" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    local test_dir="${TEST_TEMP_DIR}/git_test"
    mkdir -p "$test_dir/.git"

    run check_sensitive_files "$test_dir"
    assert_failure
    assert_output --partial ".git"
}

# =============================================================================
# Exclusion Generation Tests
# =============================================================================

@test "build_rclone_excludes generates exclude patterns" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    local excludes
    excludes=$(build_rclone_excludes)

    # Should contain patterns for secret folders
    [[ "$excludes" == *"--exclude .ssh/"* ]]
    [[ "$excludes" == *"--exclude .gnupg/"* ]]
}

@test "build_rclone_excludes includes file patterns" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    local excludes
    excludes=$(build_rclone_excludes)

    # Should contain patterns for secret files
    [[ "$excludes" == *"--exclude *.key"* ]]
    [[ "$excludes" == *"--exclude *.pem"* ]]
}

@test "get_rclone_exclude_array generates array output" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    local -a excludes
    mapfile -t excludes < <(get_rclone_exclude_array)

    # Array should have entries
    assert [ "${#excludes[@]}" -gt 0 ]

    # Should contain --exclude entries
    local found_exclude=false
    for item in "${excludes[@]}"; do
        if [[ "$item" == "--exclude" ]]; then
            found_exclude=true
            break
        fi
    done
    assert [ "$found_exclude" = "true" ]
}

# =============================================================================
# Legacy Function Tests
# =============================================================================

@test "remove_sensitive_data emits deprecation warning" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    # This will fail because path is not in allowed directories
    # but should still emit warning
    run remove_sensitive_data "/tmp/test_$$"
    assert_output --partial "deprecated"
}

@test "remove_sensitive_data returns UNSAFE for home directory" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    run remove_sensitive_data "$HOME"
    assert_failure
    assert_output --partial "unsafe"
}

# =============================================================================
# Settings Integration Tests
# =============================================================================

@test "sensitive functions use SECRET_FOLDERS from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    assert [ "${#SECRET_FOLDERS[@]}" -gt 0 ]
}

@test "sensitive functions use SECRET_FILES from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    assert [ "${#SECRET_FILES[@]}" -gt 0 ]
}

@test "sensitive functions use SENSITIVE_FOLDERS from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    assert [ "${#SENSITIVE_FOLDERS[@]}" -gt 0 ]
}

# =============================================================================
# Phase 12 Bug Fix Tests
# =============================================================================

@test "SENSITIVE_FOLDERS includes venv for Python virtual environments" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    # venv should be in SENSITIVE_FOLDERS
    local found_venv=false
    for folder in "${SENSITIVE_FOLDERS[@]}"; do
        if [[ "$folder" == "venv" ]]; then
            found_venv=true
            break
        fi
    done
    assert [ "$found_venv" = "true" ]
}

@test "get_rclone_exclude_array includes venv exclusion pattern" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "sensitive.sh"

    local -a excludes
    mapfile -t excludes < <(get_rclone_exclude_array)

    # Should contain venv pattern
    local found_venv=false
    for item in "${excludes[@]}"; do
        if [[ "$item" == "venv/" ]] || [[ "$item" == "**/venv/" ]]; then
            found_venv=true
            break
        fi
    done
    assert [ "$found_venv" = "true" ]
}
