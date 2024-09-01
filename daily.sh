#! /bin/bash

# Daily maintenance tasks

export cleanup_functions=()

# Set the folder where dependencies can be found.
# This is needed when the script is run via
# a symbolic link.
daily_path=$(dirname $(realpath  $0))

# Set return codes as used in general
. ${daily_path}/return_codes.sh

# Settings for this script
. ${daily_path}/settings.sh

# Load useful functions needed by this file and other includes
. ${daily_path}/useful.sh

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

# Routines to check network works and is configured correctly
. ${daily_path}/network.sh

# Routines to check some systemd units are active
. ${daily_path}/system.sh

# Package updates and checks
. ${daily_path}/package.sh

# Routine for mail synchronisation
. ${daily_path}/magpie.sh

 # Routines for backups
. ${daily_path}/backup.sh

# Load routine s
. ${daily_path}/sensitive.sh

. ${daily_path}/cloud.sh

function handle_signal {
    # cleanup and use error code if we trap a signal
    >&2 echo "${STAMP}: trapped signal during maintenance"
    cleanup "${TRAPPED_SIGNAL}"
}

# Start by setting a handler for signals that stop work
trap handle_signal 1 2 3 6 15

# Set a stamp for use in messages and file names
set_stamp

# Set the month for use in the encrypted folder to offload,
# and other occasional maintenance.
set_month

# Check the network
network_check   "$MAIN_WIRED" \
                "$MAIN_WIRELESS" \
                "$MAIN_TUNNEL" \
                "$DEFAULT_VPN"

# System checks
system_check

# Run package related maintenance tasks
run_package_maintenance

# Run organiser
magpie

# Run the backups
run_local_backup

# Unmount and send encrypted archive via rclone
# to standard S3 storage
run_archive '/mnt/data/clear' \
            '/mnt/data/archive' \
            'clovis-mnt-data-archive-std'

# If available prepare to offload files to
# glacier deep archive storage
if [ -n "${MONTH}" ]; then
    if [ -d "/mnt/data/${MONTH}" ]; then
        run_archive "/mnt/data/${MONTH}/clear" \
                    "/mnt/data/${MONTH}/offload" \
                    "clovis-mnt-data-${MONTH}-offload-gda"
    fi
fi

# Offload previous month if necessary
OLDMONTH="202408"
if [ -n "${OLDMONTH}" ]; then
    if [ -d "/mnt/data/${OLDMONTH}" ]; then
        run_archive "/mnt/data/${OLDMONTH}/clear" \
                    "/mnt/data/${OLDMONTH}/offload" \
                    "clovis-mnt-data-${OLDMONTH}-offload-gda"
    fi
fi

# Set up folders for sharing via commercial cloud
run_shared_preparation "${HOME}"

# Run at least one remote backup
# all_remote_backups "${REMOTE_BACKUP}"

# Cleanup and exit with code 0
cleanup 0
