#!/bin/bash
# Test helper functions for daily maintenance system tests
#
# This file provides common setup, teardown, and utility functions
# for all bats test files.

# Get the directory containing the test files
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get the project root directory
PROJECT_DIR="$(dirname "$TEST_DIR")"

# Load bats helper libraries
load '/usr/lib/bats/bats-support/load.bash'
load '/usr/lib/bats/bats-assert/load.bash'

# Common setup function - called before each test
setup() {
    # Change to project directory
    cd "$PROJECT_DIR"

    # Source env.sh if it exists (provides required variables for settings.sh)
    if [[ -f "${PROJECT_DIR}/env.sh" ]]; then
        # shellcheck disable=SC1091
        source "${PROJECT_DIR}/env.sh"
    fi

    # --- CRITICAL: test-isolation safety net ---
    #
    # env.sh exports the OPERATOR'S REAL backup targets (real datasets,
    # the real remote host, real drive configs). settings.sh, sourced
    # later by each test, builds the live SYNCOID_TARGETS /
    # ZFS_BACKUP_TARGETS from these strings. A test that then calls a
    # high-level entry point (e.g. run_all_backups) without explicitly
    # isolating itself would perform a REAL multi-gigabyte replication
    # to the real host, bypassing daily.sh's lock - which has corrupted
    # production backups and saturated the network.
    #
    # Neutralise the target-defining strings AFTER env.sh is sourced
    # and BEFORE any test sources settings.sh. settings.sh then builds
    # EMPTY/placeholder targets, so a forgotten isolation step
    # exercises safe early-return paths instead of a real backup. Tests
    # that need specific values set them explicitly and so override
    # these. This makes "forgot to isolate" harmless instead of
    # catastrophic.
    export SYNCOID_DATASETS=""
    export ZFS_BACKUP_TARGETS=""
    export CLOUD_SYNCS=""
    export SYNCOID_REMOTE_HOST="invalid.test"
    export SYNCOID_REMOTE_POOL="testpool"
    export ROOT_BACKUP_POOL="testpool"
    export ROOT_BACKUP_CONFIG="testconfig"
    export ROOT_BACKUP_DATASET="testpool/test/root"

    # Set a predictable timestamp for testing
    export STAMP="20260125T120000-test"

    # Create a temporary directory for test artifacts
    TEST_TEMP_DIR=$(mktemp -d)
    export TEST_TEMP_DIR
}

# Common teardown function - called after each test
teardown() {
    # Clean up temporary directory
    if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

##
# Source a project file under bash
#
# This ensures the file is sourced in a bash context,
# not the interactive shell (which may be zsh).
#
# Arguments:
#   $1 - File path relative to project root
#
# Usage:
#   source_project_file "bump/bump.sh"
##
source_project_file() {
    local file="$1"
    local full_path="${PROJECT_DIR}/${file}"

    if [[ ! -f "$full_path" ]]; then
        echo "ERROR: File not found: $full_path" >&2
        return 1
    fi

    # shellcheck disable=SC1090
    source "$full_path"
}

##
# Source all required project files for a full environment
#
# This sources files in the correct order to set up
# the complete daily maintenance environment.
##
source_all_project_files() {
    source_project_file "bump/bump.sh" || return 1
    # Source env.sh if it exists (provides required variables for settings.sh)
    if [[ -f "${PROJECT_DIR}/env.sh" ]]; then
        source_project_file "env.sh" || return 1
    fi
    source_project_file "settings.sh" || return 1
    source_project_file "sensitive.sh" || return 1
    source_project_file "network.sh" || return 1
    source_project_file "system.sh" || return 1
    source_project_file "backup.sh" || return 1
    source_project_file "cloud.sh" || return 1
}

##
# Run a function and capture stdout and stderr separately
#
# Arguments:
#   $1 - Variable name to store stdout
#   $2 - Variable name to store stderr
#   $3... - Command and arguments to run
#
# Returns:
#   The exit code of the command
#
# Usage:
#   capture_output stdout_var stderr_var my_function arg1 arg2
#   echo "stdout: $stdout_var"
#   echo "stderr: $stderr_var"
##
capture_output() {
    local stdout_var=$1
    local stderr_var=$2
    shift 2

    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)

    # Run command, capturing stdout and stderr separately
    "$@" >"$stdout_file" 2>"$stderr_file"
    local rc=$?

    # Read output into variables using printf to handle special characters
    printf -v "$stdout_var" '%s' "$(cat "$stdout_file")"
    printf -v "$stderr_var" '%s' "$(cat "$stderr_file")"

    # Clean up
    rm -f "$stdout_file" "$stderr_file"

    return $rc
}

##
# Assert that a command succeeds (exit code 0)
#
# Arguments:
#   $@ - Command and arguments
##
assert_success_with_stderr() {
    local stderr_file
    stderr_file=$(mktemp)

    run "$@" 2>"$stderr_file"

    if [[ $status -ne 0 ]]; then
        echo "Command failed with status $status"
        echo "stderr: $(cat "$stderr_file")"
        rm -f "$stderr_file"
        return 1
    fi

    rm -f "$stderr_file"
    return 0
}

##
# Create a mock function that records calls and returns specified value
#
# Arguments:
#   $1 - Function name to mock
#   $2 - Return value (default: 0)
#   $3 - Output to stdout (optional)
#
# Usage:
#   create_mock "sudo" 0 ""
#   # Now 'sudo' calls will succeed and record to MOCK_CALLS_sudo
##
create_mock() {
    local func_name=$1
    local return_value=${2:-0}
    local output=${3:-}

    # Create array to track calls
    eval "MOCK_CALLS_${func_name}=()"

    # Create the mock function
    eval "${func_name}() {
        MOCK_CALLS_${func_name}+=(\"\$*\")
        if [[ -n \"$output\" ]]; then
            echo \"$output\"
        fi
        return $return_value
    }"
}

##
# Get the number of times a mock was called
#
# Arguments:
#   $1 - Function name
##
mock_call_count() {
    local func_name=$1
    local array_name="MOCK_CALLS_${func_name}[@]"
    local -a calls=("${!array_name}")
    echo "${#calls[@]}"
}

##
# Get the arguments from a specific mock call
#
# Arguments:
#   $1 - Function name
#   $2 - Call index (0-based)
##
mock_call_args() {
    local func_name=$1
    local index=$2
    local array_name="MOCK_CALLS_${func_name}[$index]"
    echo "${!array_name}"
}

##
# Assert that a variable is defined and not empty
#
# Arguments:
#   $1 - Variable name
##
assert_var_defined() {
    local var_name=$1
    local var_value="${!var_name}"

    if [[ -z "$var_value" ]]; then
        echo "Variable $var_name is not defined or is empty"
        return 1
    fi
    return 0
}

##
# Assert that an array has expected number of elements
#
# Arguments:
#   $1 - Array name (without [@])
#   $2 - Expected count
##
assert_array_count() {
    local array_name=$1
    local expected=$2
    local array_ref="${array_name}[@]"
    local -a array=("${!array_ref}")
    local actual=${#array[@]}

    if [[ $actual -ne $expected ]]; then
        echo "Array $array_name has $actual elements, expected $expected"
        return 1
    fi
    return 0
}

##
# Check if a command exists
#
# Arguments:
#   $1 - Command name
##
command_exists() {
    command -v "$1" &>/dev/null
}

##
# Skip test if a command is not available
#
# Arguments:
#   $1 - Command name
#   $2 - Skip message (optional)
##
skip_if_no_command() {
    local cmd=$1
    local msg=${2:-"Command '$cmd' not available"}

    if ! command_exists "$cmd"; then
        skip "$msg"
    fi
}

##
# Skip test if not running as root
##
skip_if_not_root() {
    if [[ $EUID -ne 0 ]]; then
        skip "Test requires root privileges"
    fi
}

##
# Skip test if running as root
##
skip_if_root() {
    if [[ $EUID -eq 0 ]]; then
        skip "Test should not run as root"
    fi
}
