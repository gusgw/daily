#!/usr/bin/env bats
# Test-isolation safety net.
#
# Regression guard for a critical defect: the test harness sourced the
# operator's real env.sh, so a test that called a high-level backup
# entry point without isolating itself performed a REAL replication to
# the real remote host - bypassing daily.sh's lock, corrupting
# production backup state, and saturating the network for hours.
#
# These tests deliberately do NOT clear arrays and do NOT stub
# anything. They assert that, thanks to setup() neutralising the
# target-defining strings, an un-isolated run touches no real targets.
# If setup()'s safety net regresses, these fail fast (they do not hang,
# because the neutralised config yields empty-target early returns).

load 'test_helper'

@test "harness neutralises production backup targets in setup()" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # settings.sh built these from the (now neutralised) env strings.
    [ "${#SYNCOID_TARGETS[@]}" -eq 0 ]
    [ "${#ZFS_BACKUP_TARGETS[@]}" -eq 0 ]
    [ "$SYNCOID_REMOTE_HOST" = "invalid.test" ]
    [ "$ROOT_BACKUP_POOL" = "testpool" ]
}

@test "un-isolated run_all_backups performs NO real replication" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    # No arrays cleared, no stubs - exactly the mistake that caused the
    # incident. With the safety net this must be a fast, harmless,
    # empty-config run.
    run run_all_backups

    assert_success
    assert_output --partial "no syncoid targets configured"
    # Must NOT have iterated the operator's real datasets / host.
    refute_output --partial "processing syncoid target: clovis/gusgw"
    refute_output --partial "toby:znaeym"
}

@test "un-isolated run_all_syncoid_backups does not reach a real host" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"
    source_project_file "backup.sh"

    run run_all_syncoid_backups

    assert_success
    assert_output --partial "no syncoid targets configured"
    refute_output --partial "toby"
}
