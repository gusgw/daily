#! /bin/bash

# Daily maintenance tasks

# Set return codes as used in general
. return_codes.sh

# Settings for this script
. settings.sh

# Load useful functions needed by this file and other includes
. useful.sh

#################################
# Functions that run daily tasks

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
    cleanup_package_maintenance
    cleanup_run_archive
    cleanup_remote_backup
    cleanup_local_backup
    cleanup_shared_preparation
    >&2 echo "${STAMP}: . . . all done with code ${c_rc}"
    exit $c_rc
}

# Routines to check network works and is configured correctly
. network.sh

# Routines to check some systemd units are active
. system.sh

# Package updates and checks
. package.sh

# Routine for mail synchronisation
. magpie.sh

 # Routines for backups
. backup.sh

# Load routine s
. sensitive.sh

. cloud.sh

# Start by setting a handler for signals that stop work
trap handle_signal 1 2 3 6 15

# Set a stamp for use in messages and file names
set_stamp

echo $STAMP

# Set the month for use in the encrypted folder to offload,
# and other occasional maintenance.
set_month

echo $MONTH

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
OLDMONTH=""
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
