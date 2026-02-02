#!/usr/bin/env bats
# Tests for settings.sh
#
# These tests verify all required settings are defined
# and properly formatted.

load 'test_helper'

@test "settings.sh can be sourced" {
    run source_project_file "settings.sh"
    assert_success
}

@test "settings.sh has valid bash syntax" {
    run bash -n "${PROJECT_DIR}/settings.sh"
    assert_success
}

# =============================================================================
# Process Limits and Timing
# =============================================================================

@test "MAX_SUBPROCESSES is defined and numeric" {
    source_project_file "settings.sh"
    assert [ -n "$MAX_SUBPROCESSES" ]
    [[ "$MAX_SUBPROCESSES" =~ ^[0-9]+$ ]]
}

@test "SIMULTANEOUS_TRANSFERS is defined and numeric" {
    source_project_file "settings.sh"
    assert [ -n "$SIMULTANEOUS_TRANSFERS" ]
    [[ "$SIMULTANEOUS_TRANSFERS" =~ ^[0-9]+$ ]]
}

@test "WAIT is defined and numeric" {
    source_project_file "settings.sh"
    assert [ -n "$WAIT" ]
    [[ "$WAIT" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "ATTEMPTS is defined and numeric" {
    source_project_file "settings.sh"
    assert [ -n "$ATTEMPTS" ]
    [[ "$ATTEMPTS" =~ ^[0-9]+$ ]]
}

@test "SSH_TIMEOUT is defined and numeric" {
    source_project_file "settings.sh"
    assert [ -n "$SSH_TIMEOUT" ]
    [[ "$SSH_TIMEOUT" =~ ^[0-9]+$ ]]
}

# =============================================================================
# Network Configuration
# =============================================================================

@test "WIREGUARD_INTERFACE is defined" {
    source_project_file "settings.sh"
    assert [ -n "$WIREGUARD_INTERFACE" ]
}

@test "VPN_DNS is defined and looks like an IP" {
    source_project_file "settings.sh"
    assert [ -n "$VPN_DNS" ]
    [[ "$VPN_DNS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# =============================================================================
# ZFS Configuration
# =============================================================================

@test "ZFS_POOL is defined" {
    source_project_file "settings.sh"
    assert [ -n "$ZFS_POOL" ]
}

@test "SCRUB_WARN_DAYS is defined and numeric" {
    source_project_file "settings.sh"
    assert [ -n "$SCRUB_WARN_DAYS" ]
    [[ "$SCRUB_WARN_DAYS" =~ ^[0-9]+$ ]]
}

@test "POOL_CAPACITY_WARN is defined and in valid percentage range" {
    source_project_file "settings.sh"
    assert [ -n "$POOL_CAPACITY_WARN" ]
    [[ "$POOL_CAPACITY_WARN" =~ ^[0-9]+$ ]]
    assert [ "$POOL_CAPACITY_WARN" -ge 1 ]
    assert [ "$POOL_CAPACITY_WARN" -le 100 ]
}

# =============================================================================
# System Health
# =============================================================================

@test "JOURNAL_WARN_SIZE is defined" {
    source_project_file "settings.sh"
    assert [ -n "$JOURNAL_WARN_SIZE" ]
}

@test "UNITS_TO_CHECK array is defined" {
    source_project_file "settings.sh"
    # Check array is declared
    declare -p UNITS_TO_CHECK &>/dev/null
}

# Note: syncthing and sshd removed from UNITS_TO_CHECK - only sanoid.timer remains

@test "UNITS_TO_CHECK contains sanoid timer" {
    source_project_file "settings.sh"
    local found=false
    for unit in "${UNITS_TO_CHECK[@]}"; do
        if [[ "$unit" == "sanoid.timer" ]]; then
            found=true
            break
        fi
    done
    assert [ "$found" = "true" ]
}

# =============================================================================
# Backup Configuration
# =============================================================================

@test "BACKUP_CONFIGS_DIR is defined" {
    source_project_file "settings.sh"
    assert [ -n "$BACKUP_CONFIGS_DIR" ]
}

@test "ZFS_BACKUP_TARGETS array is defined" {
    source_project_file "settings.sh"
    declare -p ZFS_BACKUP_TARGETS &>/dev/null
}

@test "SYNCOID_TARGETS array is defined" {
    source_project_file "settings.sh"
    declare -p SYNCOID_TARGETS &>/dev/null
}

@test "SYNCOID_REMOTE_HOST is defined" {
    source_project_file "settings.sh"
    assert [ -n "$SYNCOID_REMOTE_HOST" ]
}

@test "SYNCOID_REMOTE_POOL is defined" {
    source_project_file "settings.sh"
    assert [ -n "$SYNCOID_REMOTE_POOL" ]
}

# =============================================================================
# Cloud Sync Configuration
# =============================================================================

@test "CLOUD_SYNCS array is defined" {
    source_project_file "settings.sh"
    declare -p CLOUD_SYNCS &>/dev/null
}

# =============================================================================
# Security Settings
# =============================================================================

@test "SECRET_FOLDERS array is defined and non-empty" {
    source_project_file "settings.sh"
    declare -p SECRET_FOLDERS &>/dev/null
    assert [ "${#SECRET_FOLDERS[@]}" -gt 0 ]
}

@test "SECRET_FOLDERS contains .ssh" {
    source_project_file "settings.sh"
    local found=false
    for folder in "${SECRET_FOLDERS[@]}"; do
        if [[ "$folder" == ".ssh" ]]; then
            found=true
            break
        fi
    done
    assert [ "$found" = "true" ]
}

@test "SECRET_FOLDERS contains .gnupg" {
    source_project_file "settings.sh"
    local found=false
    for folder in "${SECRET_FOLDERS[@]}"; do
        if [[ "$folder" == ".gnupg" ]]; then
            found=true
            break
        fi
    done
    assert [ "$found" = "true" ]
}

@test "SECRET_FILES array is defined and non-empty" {
    source_project_file "settings.sh"
    declare -p SECRET_FILES &>/dev/null
    assert [ "${#SECRET_FILES[@]}" -gt 0 ]
}

@test "SENSITIVE_FOLDERS array is defined and non-empty" {
    source_project_file "settings.sh"
    declare -p SENSITIVE_FOLDERS &>/dev/null
    assert [ "${#SENSITIVE_FOLDERS[@]}" -gt 0 ]
}

# =============================================================================
# Output Formatting
# =============================================================================

@test "RULE is defined" {
    source_project_file "settings.sh"
    assert [ -n "$RULE" ]
}
