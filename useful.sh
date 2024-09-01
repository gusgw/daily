##  Utility functions

##  Settings
#   STAMP   should be set by a call to set_stamp in this file.
#   WAIT    is the time to wait in seconds between repeted attempts.
#   RULE    is a separator to use in formatting outputs.

##  Dependencies
#   return_codes.sh
#   settings.h
#   useful.h

##  Notes
#   Run set_stamp and set_month before using the other routines.

. return_codes.sh

function set_stamp {
    # Store a stamp used to label files
    # and messages created in this script.
    export STAMP="$(date '+%Y%m%d'-$(hostnamectl hostname))"
    return 0
}

function set_month {
    # Set a global variable containing the year and month
    # for use in naming folders to offload
    export MONTH="$(date '+%Y%m')"
    return 0
}

function not_empty {
    # Ensure that an expression is not empty
    # then cleanup and quit if it is.
    # Generally this is used to check that parameters
    # have been provided so the return code when the
    # expression is empty is ${MISSING_INPUT}.
    local ne_description=$1
    local ne_check=$2
    if [ -z "$ne_check" ]; then
        >&2 echo "${STAMP}: cannot run without ${ne_description}"
        cleanup "${MISSING_INPUT}"
    fi
    return 0
}

function log_setting {
    # Make sure a setting is provided
    # and report it
    local ls_description=$1
    local ls_setting=$2
    not_empty "date stamp" "${STAMP}"
    not_empty "$ls_description" "$ls_setting"
    >&2 echo "${STAMP}: ${ls_description} is ${ls_setting}"
    return 0
}

function check_exists {
    # Make sure a file or folder or link exists
    # then cleanup and quit if not
    local ce_file_name=$1
    log_setting "file or directory name that must exist" "$ce_file_name"
    if ! [ -e "$ce_file_name" ]; then
        >&2 echo "${STAMP}: cannot find $ce_file_name"
        cleanup "$MISSING_FILE"
    fi
    return 0
}

function check_contains {
    # Make sure a file exists and contains
    # the given string.
    local cc_file_name=$1
    local cc_string=$2
    log_setting "file name to check" "$cc_file_name"
    log_setting "string to check for" "$cc_string"
    not_empty "date stamp" "$STAMP"
    if [ -e "$cc_file_name" ]; then
        if ! grep -qs "${cc_string}" "${cc_file_name}"; then
            >&2 echo "${STAMP}: ${cc_file_name} does not contain ${cc_string}"
            cleanup "$BAD_CONFIGURATION"
        fi
    else
        >&2 echo "${STAMP}: cannot find ${cc_file_name}"
        cleanup "$MISSING_FILE"
    fi
    return 0
}

function path_as_name {
    # Convert a path to a string that
    # can be used as a name. This is sometimes
    # useful for naming archives and so on.
    local pan_path=$1
    not_empty "path to convert to a name" "$pan_path"
    echo "$pan_path" |\
        sed 's:^/::' |\
        sed 's:/:-:g' |\
        sed 's/[[:space:]]/_/g'
    return 0
}

function report {
    # Inform the user of a non-zero return
    # code, and if an exit
    # message is provided as a third argument
    # also exit cleanly
    local r_rc=$1
    local r_description=$2
    local r_exit_message=$3
    >&2 echo "${STAMP}: ${r_description} exited with code $r_rc"
    if [ -z "$r_exit_message" ]; then
        >&2 echo "${STAMP}: continuing . . ."
    else
        >&2 echo "${STAMP}: $r_exit_message"
        cleanup $r_rc
    fi
    return $r_rc
}

function slow {
    # Wait for all processes with given name to disappear
    # rsync in particular seems to hang around

    ##########################################################
    # The number of seconds to wait is globally set as $WAIT #
    ##########################################################

    local s_pname=$1
    log_setting "program name to wait for" "$s_pname"
    for pid in $(pgrep $s_pname); do
        while kill -0 "$pid" 2> /dev/null; do
            >&2 echo "${STAMP}: ${s_pname} ${pid} is still running"
            sleep ${WAIT}
        done
    done
}

function print_rule {
    echo
    echo "$RULE"
    echo
}

function print_error_rule {
    >&2 echo
    >&2 echo "$RULE"
    >&2 echo
}

export cleanup_functions=()

function cleanup {

    ######################################
    # If using the report function here, #
    # make sure it has NO THIRD ARGUMENT #
    # or there will be an infinite loop! #
    # This function may be used to       #
    # handle trapped signals             #
    ######################################

    local c_rc=$1
    print_error_rule
    >&2 echo "${STAMP}: exiting cleanly with code ${c_rc}. . ."
    for cleanfn in "${cleanup_functions[@]}"
    do
        if [[ $cleanfn == cleanup_* ]]
        then
            $cleanfn
        else
            >&2 echo "${STAMP}: DBG not calling $cleanfn"
        fi
    done
    >&2 echo "${STAMP}: . . . all done with code ${c_rc}"
    exit $c_rc
}

function handle_signal {
    # cleanup and use error code if we trap a signal
    >&2 echo "${STAMP}: trapped signal"
    cleanup "${TRAPPED_SIGNAL}"
}
