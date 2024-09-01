##  System check

##  Settings
#   UNITS_TO_CHECK  is list of systemd units to check.

##  Dependencies
#   return_codes.sh
#   settings.sh
#   useful.sh

##  Notes
#   This just checks that units listed in `${UNITS_TO_CHECK[@]}`
#   are active, and if not attempts to start them,
#   usually `syncthing` and `sshd`.
#   Exit cleanly if these units have failed or are not running.

function system_check {
    # Check services are running

    ##################################################################
    # System units to check are set globally in ${UNITS_TO_CHECK[@]} #
    ##################################################################

    >&2 echo "${STAMP}: system_check"

    print_rule
    for svc in "${UNITS_TO_CHECK[@]}"; do
        make_active "${svc}"
        print_rule
    done
    return 0
}

function make_active {
    # Make sure a systemd unit is active
    local ma_unit=$1
    log_setting "unit to activate" "$ma_unit"

    if ! sudo systemctl is-active --quiet "$ma_unit"; then
        sudo systemctl start "$ma_unit" ||\
            report $? "starting $ma_unit"
        if sudo systemctl is-failed --quiet "$ma_unit"; then
            sudo systemctl status --no-pager --lines=10 "$ma_unit" ||\
                report $? "get status of $ma_unit"
            cleanup "$SYSTEM_UNIT_FAILURE"
        fi
    fi
    sudo systemctl status --no-pager --lines=0 "$ma_unit" ||\
        report $? "get status of $ma_unit"
    return 0
}