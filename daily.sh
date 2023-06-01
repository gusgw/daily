#! /bin/bash

# Commands used here with sudo should
# run without a password.

# Access via ssh must be set up with no passphrase.

# Set a key file to decrypt the backup
# disk in the environment variable KEY_FILE.

# Make sure the backup disk is set in 
# the environment variable BACKUP_DISK.

# Make sure the backup name is set in 
# the environment variable BACKUP_NAME.
# This will be used as the device name
# for the unlocked 

# Warning!
# The local backup copies everything.
# That includes sensitive information including
# encryption keys stored by default in your home
# folder. The remote backup excludes a list of folders
# that contain keys, certificates, and passwords,
# but this list may not be complete on other machines.

function set_stamp {
    # Store a stamp used to label files
    # and messages created in this script.
    export STAMP="$(date '+%Y%m%d'-$(hostnamectl hostname))"
    return 0
}

function report {
    # Inform the user of a non-zero return
    # code, cleanup and exit if an exit
    # message is provided as a third argument
    local rc=$1
    local description=$2
    local exit_message=$3
    >&2 echo "${STAMP}: ${description} exited with code $rc"
    if [ -z "$exit_message" ]; then
        >&2 echo "${STAMP}: continuing . . ."
    else
        >&2 echo "${STAMP}: $exit_message"
        cleanup $rc
    fi
    return $rc
}

function slow {
    # Wait for processes which disappear slowly
    local pname=$1
    for pid in $(pgrep $pname); do
        while kill -0 "$pid" 2> /dev/null; do
            sleep 1.0
        done
    done
}

function cleanup {
    # If using the report function here,
    # make sure it has NO THIRD ARGUMENT
    # or there will be an infinite loop!
    # Cleanup can be quite slow.
    local rc=$1
    >&2 echo "${STAMP}: exiting cleanly . . ."
    cleanup_package_maintenance
    cleanup_remote_backup
    cleanup_local_backup
    >&2 echo "${STAMP}: . . . all done"
    exit $rc
}

function run_package_maintenance {
    # Run regular package related tasks
    sudo pacman -Scc --noconfirm || report $? "cleaning package cache"
    sudo pacman -Syu --noconfirm || report $? "updating system"

    # Some pacman work taken from the Arch wiki:
    # https://wiki.archlinux.org/title/Pacman/Tips_and_tricks
    sudo pacman -Qtdq | sudo pacman -Rns - || report $? "remove orphan packages"
    sudo pacman -Qqd | sudo pacman -Rsu --print - 1> ${STAMP}-possible_orphan_packages.txt ||\
        report $? "finding packages that might not be needed"

    # Try a method of listing explicitly installed packages. Note recent update in the comments.
    # https://unix.stackexchange.com/questions/409895/pacman-get-list-of-packages-installed-by-user
    comm -23 <(sudo pacman -Qqett | sort | uniq) <(sudo pacman -Qqg base-devel | sort | uniq) 1>\
        ${STAMP}-package_list.txt ||\
        report $? "create list of explicitly installed package"

    # Get optional dependencies
    # https://wiki.archlinux.org/title/Pacman/Tips_and_tricks
    comm -13 <(pacman -Qqdt | sort) <(pacman -Qqdtt | sort) > ${STAMP}-optional_list.txt

    # Get a list of AUR and other foreign packages
    # https://wiki.archlinux.org/title/Pacman/Tips_and_tricks
    pacman -Qqem > ${STAMP}-foreign_list.txt

    # Check for unowned files
    sudo pacreport --unowned-files 1>\
        ${STAMP}-unowned_list.txt ||\
        report $? "finding unowned files"

    # Archive the pacman database
    sudo tar -cjf "${STAMP}-pacman_database.tar.bz2" /var/lib/pacman/local ||\
        report $? "saving pacman database"

    return 0
}

function cleanup_package_maintenance {
    # Clean up after package maintenance
    # This function may be used to handle trapped signals
    # Get rid of lists of packages
    rm -f ${STAMP}-package_list.txt
    rm -f ${STAMP}-possible_orphan_packages.txt
    rm -f ${STAMP}-optional_list.txt
    rm -f ${STAMP}-foreign_list.txt
    rm -f ${STAMP}-unowned_list.txt
    rm -f ${STAMP}-pacman_database.tar.bz2
    return 0
}

function run_local_backup {
    # Local backup
    local home_folder_name=$(basename $HOME)
    local backup_destination="/mnt/${BACKUP_NAME}/${home_folder_name}"

    sudo cryptsetup open --key-file="$KEY_FILE" "$BACKUP_DISK" "$BACKUP_NAME" ||\
        report $? "unlock backup disk"
    sudo mount "/dev/mapper/$BACKUP_NAME" "/mnt/$BACKUP_NAME" ||\
        report $? "mount backup disk"
    if [ -d "$backup_destination" ]; then
        rsync   -av \
                --links \
                --progress \
                --delete \
                --delete-excluded \
                --exclude=$LOCAL_EXCLUDES \
                "${HOME}/" \
                "${backup_destination}/" ||\
            report $? "local backup via rsync"
    else
        >&2 echo "${STAMP}: local backup disk not found - continuing . . ."
    fi

    return 0
}

function cleanup_local_backup {
    # Clean up after local backup
    # This function may be used to handle trapped signals
    # Make sure rsync is done
    killall rsync || report $? "kill the rsync processes"
    slow rsync

    # If the local backup is mounted, unmount
    if grep -qs "mnt/${BACKUP_NAME}" /proc/mounts; then
        sudo umount /dev/mapper/${BACKUP_NAME} || report $? "unmounting backup"
    fi
    # Do not leave the encrypted backup unlocked
    if sudo cryptsetup status ${BACKUP_NAME} 1> /dev/null; then
        sudo cryptsetup close ${BACKUP_NAME} || report $? "locking backup drive"
    fi

    return 0
}

function run_remote_backup {
    # Remote backup skipping sensitive data
    local home_folder_name=$(basename $HOME)
    local backup_destination="$REMOTE_BACKUP/${home_folder_name}"

    rsync   -avz \
            --links \
            --progress \
            --delete \
            --delete-excluded \
            --exclude=$REMOTE_EXCLUDES \
            "${HOME}/" \
            "${backup_destination}/" ||\
        report $? "remote backup via rsync"

    return 0
}

function cleanup_remote_backup {
    # Clean up after remove backup
    # This function may be used to handle trapped signals
    # Make sure rsync is done
    killall rsync || report $? "kill the rsync processes"
    slow rsync
    return 0
}

function system_check {
    # Check services are running
    sudo systemctl status --no-pager --lines=0 syncthing@${USER}.service ||\
        report $? "get status of syncthing"
}

function handle_signal {
    # cleanup and use error code 113 if we trap a signal
    >&2 echo "${STAMP}: trapped signal during maintenance"
    cleanup 113
}

# Start by setting a handler for signals that stop work
trap handle_signal 1 2 3 6

# Set a stamp for use in messages and file names
set_stamp

# Try not to assume a particular current directory,
# but always set it anyway
cd || report $? "change to home folder" "script only works from ${HOME}!"

# Run package related maintenance tasks
run_package_maintenance

# Make sure excludes are set and run local backup
if [ -z "$LOCAL_EXCLUDES" ]; then
    export LOCAL_EXCLUDES="{'.key','.cache','.local','mnt',tmp','gaol','opt'}"
fi
run_local_backup

# Make sure excludes are set and run remote backup
if [ -z "$REMOTE_EXCLUDES" ]; then
    export REMOTE_EXCLUDES="{'.key','.ssh','.gnupg','.pki','.cert','.password-store','.cache','.local','mnt',tmp'}"
fi
run_remote_backup

# System checks
system_check

# Cleanup and exit with code 0
cleanup 0
