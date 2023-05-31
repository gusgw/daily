#! /bin/bash

# Commands used here with sudo should
# run without a password.

# Access via ssh must be set up with no passphrase.

# Set a key file to decrypt the backup
# disk in the environment variable KEY_FILE.
# The default is $HOME/backup_key_file.

# Make sure the backup disk is set in 
# the environment variable BACKUP_DISK.
# The default is /dev/sda1

# Make sure the backup name is set in 
# the environment variable BACKUP_NAME.
# The default is /dev/sda1

# Warning!
# The local backup copies everything.
# That includes sensitive information including
# encryption keys stored by default in your home
# folder. The remote backup excludes a list of folders
# that contain keys, certificates, and passwords,
# but this list may not be complete on other machines.

function report {
    local rc=$1
    local task=$2
    local stop=$3
    >&2 echo "${task} exited with code $rc"
    if [ -z "$stop" ]; then
        >&2 echo "continuing . . ."
    else
        >&2 echo "$stop"
        cleanup $rc
    fi
    return $rc
}

function slow {
    # wait for processes which disappear slowly
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
    >&2 echo "exiting cleanly"
    # Get rid of lists of packages
    rm -f $HOME/package_list.txt
    rm -f $HOME/possible_orphan_packages.txt
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
    exit $rc
}

function run_package_maintenance {
    # Run regular package related tasks
    sudo pacman -Scc --noconfirm || report $? "cleaning package cache"
    sudo pacman -Syu --noconfirm || report $? "updating system"

    # Some pacman work taken from the Arch wiki:
    # https://wiki.archlinux.org/title/Pacman/Tips_and_tricks
    sudo pacman -Qtdq | sudo pacman -Rns - || report $? "remove orphan packages"
    sudo pacman -Qqd | sudo pacman -Rsu --print - 1> possible_orphan_packages.txt ||\
        report $? "finding packages that might not be needed"

    # Try a method of listing explicitly installed packages. Note recent update in the comments.
    # https://unix.stackexchange.com/questions/409895/pacman-get-list-of-packages-installed-by-user
    comm -23 <(sudo pacman -Qqett | sort | uniq) <(sudo pacman -Qqg base-devel | sort | uniq) >package_list.txt ||\
        report $? "create list of explicitly installed package"

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
    if [ -d "$BACKUP_DESTINATION" ]; then
        rsync   -av \
                --progress \
                --delete \
                --delete-excluded \
                --exclude=$LOCAL_EXCLUDES \
                "${HOME}/" \
                "${backup_destination}/" ||\
            report $? "local backup via rsync"
    else
        >&2 echo "local backup disk not found - continuing . . ."
    fi

    return 0
}

function run_remote_backup {
    # Remote backup skipping sensitive data
    local home_folder_name=$(basename $HOME)
    local backup_destination="$REMOTE_BACKUP/${home_folder_name}"
    
    rsync   -avz \
            --progress \
            --delete \
            --delete-excluded \
            --exclude="mnt" \
            --exclude="tmp" \
            --exclude=".ssh" \
            --exclude=".gnupg" \
            --exclude=".pki" \
            --exclude=".cert" \
            --exclude=".password-store" \
            "${HOME}/" \
            "${backup_destination}/" ||\
        report $? "remote backup via rsync"

    return 0
}

function handle_signal {
    >&2 echo "trapped signal during maintenance"
    cleanup 1000
}

trap handle_signal 1 2 3 6

cd || report $? "change to home folder" "script only works from home!"

run_package_maintenance

if [ -z "LOCAL_EXCLUDES" ]; then
    export LOCAL_EXCLUDES="{'gaol', 'mnt', 'opt', 'tmp'}"
fi
run_local_backup

run_remote_backup

cleanup 0
