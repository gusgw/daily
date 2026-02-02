#!/usr/bin/env bats
# Test that the test framework itself works correctly

load 'test_helper'

@test "test helper loads successfully" {
    # If we get here, the helper loaded
    assert [ -n "$PROJECT_DIR" ]
}

@test "PROJECT_DIR points to correct location" {
    assert [ -d "$PROJECT_DIR" ]
    assert [ -f "$PROJECT_DIR/daily.sh" ]
}

@test "TEST_TEMP_DIR is created in setup" {
    assert [ -d "$TEST_TEMP_DIR" ]
}

@test "STAMP is set to test value" {
    assert_equal "$STAMP" "20260125T120000-test"
}

@test "source_project_file works with existing file" {
    # settings.sh should exist
    run source_project_file "settings.sh"
    assert_success
}

@test "source_project_file fails with non-existent file" {
    run source_project_file "nonexistent_file.sh"
    assert_failure
}

@test "capture_output captures stdout correctly" {
    test_func() {
        echo "hello stdout"
    }

    local out err
    capture_output out err test_func

    assert_equal "$out" "hello stdout"
}

@test "capture_output captures stderr correctly" {
    test_func() {
        echo "hello stderr" >&2
    }

    local out err
    capture_output out err test_func

    assert_equal "$err" "hello stderr"
}

@test "capture_output returns correct exit code for success" {
    test_func_success() {
        return 0
    }

    local out err
    capture_output out err test_func_success
    assert_equal $? 0
}

@test "capture_output returns correct exit code for failure" {
    test_func_failure() {
        return 42
    }

    local out err
    # Capture the exit code without causing bats to fail
    local rc=0
    capture_output out err test_func_failure || rc=$?
    assert_equal "$rc" "42"
}

@test "create_mock creates callable function" {
    create_mock "my_test_command" 0 "mock output"

    run my_test_command arg1 arg2
    assert_success
    assert_output "mock output"
}

@test "mock_call_count tracks calls" {
    create_mock "tracked_command" 0

    tracked_command first
    tracked_command second
    tracked_command third

    local count
    count=$(mock_call_count "tracked_command")
    assert_equal "$count" "3"
}

@test "command_exists returns true for existing command" {
    run command_exists "bash"
    assert_success
}

@test "command_exists returns false for non-existent command" {
    run command_exists "nonexistent_command_xyz"
    assert_failure
}

@test "assert_var_defined passes for defined variable" {
    TEST_VAR="some value"
    run assert_var_defined "TEST_VAR"
    assert_success
}

@test "assert_var_defined fails for undefined variable" {
    unset UNDEFINED_VAR
    run assert_var_defined "UNDEFINED_VAR"
    assert_failure
}
