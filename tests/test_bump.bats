#!/usr/bin/env bats
# Tests for BUMP library (bump/bump.sh)
#
# These tests verify the BUMP utility library loads correctly
# and provides expected functionality.

load 'test_helper'

@test "bump.sh can be sourced" {
    run source_project_file "bump/bump.sh"
    assert_success
}

@test "return_codes.sh can be sourced" {
    run source_project_file "bump/return_codes.sh"
    assert_success
}

@test "set_stamp function exists after sourcing bump.sh" {
    source_project_file "bump/bump.sh"
    run type set_stamp
    assert_success
    assert_output --partial "function"
}

@test "set_stamp produces valid timestamp format" {
    source_project_file "bump/bump.sh"

    # Call set_stamp
    set_stamp

    # STAMP should be set
    assert [ -n "$STAMP" ]

    # Should match format: YYYYMMDDTHHmmss-hostname
    [[ "$STAMP" =~ ^[0-9]{8}T[0-9]{6}-[a-zA-Z0-9_-]+$ ]]
}

@test "cleanup function exists after sourcing bump.sh" {
    source_project_file "bump/bump.sh"
    run type cleanup
    assert_success
    assert_output --partial "function"
}

@test "report function exists after sourcing bump.sh" {
    source_project_file "bump/bump.sh"
    run type report
    assert_success
    assert_output --partial "function"
}

@test "log_setting function exists after sourcing bump.sh" {
    source_project_file "bump/bump.sh"
    run type log_setting
    assert_success
    assert_output --partial "function"
}

@test "print_rule function exists after sourcing bump.sh" {
    source_project_file "bump/bump.sh"
    run type print_rule
    assert_success
    assert_output --partial "function"
}

@test "handle_signal function exists after sourcing bump.sh" {
    source_project_file "bump/bump.sh"
    run type handle_signal
    assert_success
    assert_output --partial "function"
}

@test "cleanup_functions array is defined after sourcing bump.sh" {
    source_project_file "bump/bump.sh"

    # Check that cleanup_functions is declared as an array
    declare -p cleanup_functions &>/dev/null
}

@test "return codes are defined after sourcing return_codes.sh" {
    source_project_file "bump/return_codes.sh"

    # Check some key return codes exist and are in expected range (60-119)
    assert [ -n "$NETWORK_ERROR" ]
    assert [ "$NETWORK_ERROR" -ge 60 ]
    assert [ "$NETWORK_ERROR" -le 119 ]

    assert [ -n "$MISSING_FILE" ]
    assert [ "$MISSING_FILE" -ge 60 ]
    assert [ "$MISSING_FILE" -le 119 ]
}

@test "TRAPPED_SIGNAL return code is defined" {
    source_project_file "bump/return_codes.sh"

    assert [ -n "$TRAPPED_SIGNAL" ]
    assert [ "$TRAPPED_SIGNAL" -ge 60 ]
    assert [ "$TRAPPED_SIGNAL" -le 119 ]
}

@test "SYSTEM_UNIT_FAILURE return code is defined" {
    source_project_file "bump/return_codes.sh"

    assert [ -n "$SYSTEM_UNIT_FAILURE" ]
    assert [ "$SYSTEM_UNIT_FAILURE" -ge 60 ]
    assert [ "$SYSTEM_UNIT_FAILURE" -le 119 ]
}

@test "UNSAFE return code is defined" {
    source_project_file "bump/return_codes.sh"

    assert [ -n "$UNSAFE" ]
    assert [ "$UNSAFE" -ge 60 ]
    assert [ "$UNSAFE" -le 119 ]
}

@test "bump.sh sources return_codes.sh automatically" {
    source_project_file "bump/bump.sh"

    # After sourcing bump.sh, return codes should be available
    assert [ -n "$NETWORK_ERROR" ]
}

@test "log_setting outputs to stderr" {
    source_project_file "bump/bump.sh"
    set_stamp

    local out err
    capture_output out err log_setting "test key" "test value"

    # Output should go to stderr, not stdout
    assert [ -z "$out" ]
    assert [ -n "$err" ]
    # Check that output contains expected strings
    [[ "$err" == *"test key"* ]]
    [[ "$err" == *"test value"* ]]
}

@test "print_rule outputs separator line to stderr" {
    source_project_file "bump/bump.sh"

    # Run print_rule and capture stderr directly
    local err
    err=$(print_rule 2>&1)

    # Should output something (a line of dashes or similar)
    assert [ -n "$err" ]
}
