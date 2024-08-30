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

. network.sh

. system.sh

. package.sh

. magpie.sh

function run_local_backup {
    # Local backup

    ##########################################################################
    # USES GLOBAL VARIABLES THAT SHOULD BE SET IN .bashrc OR .zshrc OR . . . #
    ##########################################################################

    >&2 echo "${STAMP}: run_local_backup"

    local home_folder_name=$(basename $HOME)
    local backup_destination="/mnt/${BACKUP_NAME}/${home_folder_name}"
    local extra_backup_destination="/mnt/${EXTRA_BACKUP_NAME}/${home_folder_name}"

    not_empty "date stamp" "$STAMP"
    log_setting "name of the file with encryption key for local backup" \
                "$KEY_FILE"
    log_setting "device path for local encrypted backup" "$BACKUP_DISK"
    log_setting "name of the backup" "$BACKUP_NAME"
    log_setting "device path for extra local encrypted backup" "$EXTRA_BACKUP_DISK"
    log_setting "name of extra backup" "$EXTRA_BACKUP_NAME"

    check_exists "${HOME}/.exclude_local"

    if [ -e "$BACKUP_DISK" ]; then
        sudo cryptsetup open --key-file="$KEY_FILE"\
                             "$BACKUP_DISK" \
                             "$BACKUP_NAME" ||\
            report $? "unlock backup disk"
        sudo fsck -a "/dev/mapper/$BACKUP_NAME" ||\
            report $? "running file system check on /dev/mapper/$BACKUP_NAME"
        sudo mount "/dev/mapper/$BACKUP_NAME" "/mnt/$BACKUP_NAME" ||\
            report $? "mount backup disk"
        if [ -d "$backup_destination" ]; then
            sudo rsync  -av \
                        --links \
                        --progress \
                        --delete \
                        --delete-excluded \
                        --exclude-from="${HOME}/.exclude_local" \
                        "${HOME}/" \
                        "${backup_destination}/" ||\
                    report $? "local backup via rsync"
        else
            >&2 echo "${STAMP}: local backup destination not found"
        fi
    else
        >&2 echo "${STAMP}:  local backup device not found"
    fi

    if [ -e "$EXTRA_BACKUP_DISK" ]; then
        sudo cryptsetup open --key-file="$KEY_FILE"\
                             "$EXTRA_BACKUP_DISK" \
                             "$EXTRA_BACKUP_NAME" ||\
            report $? "unlock extra backup disk"
        sudo fsck -a "/dev/mapper/$EXTRA_BACKUP_NAME" ||\
            report $? "running file system check on /dev/mapper/$EXTRA_BACKUP_NAME"
        sudo mount "/dev/mapper/$EXTRA_BACKUP_NAME" "/mnt/$EXTRA_BACKUP_NAME" ||\
            report $? "mount extra backup disk"
        if [ -d "$extra_backup_destination" ]; then
            sudo rsync  -av \
                        --links \
                        --progress \
                        --delete \
                        --delete-excluded \
                        --exclude-from="${HOME}/.exclude_local" \
                        "${HOME}/" \
                        "${extra_backup_destination}/" ||\
                    report $? "extra local backup via rsync"
        else
            >&2 echo "${STAMP}: extra local backup destination not found"
        fi
    else
        >&2 echo "${STAMP}: extra local backup device not found"
    fi

    return 0
}

function cleanup_local_backup {
    # Clean up after local backup
    # Make sure rsync is done

    ######################################
    # If using the report function here, #
    # make sure it has NO THIRD ARGUMENT #
    # or there will be an infinite loop! #
    # This function may be used to       #
    # handle trapped signals             #
    ######################################

    ##########################################################################
    # USES GLOBAL VARIABLES THAT SHOULD BE SET IN .bashrc OR .zshrc OR . . . #
    ##########################################################################

    killall rsync || report $? "kill the rsync processes"
    slow rsync

    # If the local backup is mounted, unmount
    if grep -qs "/mnt/${BACKUP_NAME}" /proc/mounts; then
        sudo umount /dev/mapper/${BACKUP_NAME} ||\
            report $? "unmounting backup"
    fi

    # Do not leave the encrypted backup unlocked
    if sudo cryptsetup status ${BACKUP_NAME} 1> /dev/null; then
        sudo cryptsetup close ${BACKUP_NAME} ||\
            report $? "locking backup drive"
    fi

    # If the local backup is mounted, unmount
    if grep -qs "/mnt/${EXTRA_BACKUP_NAME}" /proc/mounts; then
        sudo umount /dev/mapper/${EXTRA_BACKUP_NAME} ||\
            report $? "unmounting extra backup"
    fi

    # Do not leave the encrypted backup unlocked
    if sudo cryptsetup status ${EXTRA_BACKUP_NAME} 1> /dev/null; then
        sudo cryptsetup close ${EXTRA_BACKUP_NAME} ||\
            report $? "locking extra backup drive"
    fi

    return 0
}

function run_remote_backup {
    # Remote backup skipping sensitive data

    ##########################################################################
    # USES GLOBAL VARIABLES THAT SHOULD BE SET IN .bashrc OR .zshrc OR . . . #
    ##########################################################################

    >&2 echo "${STAMP}: run_remote_backup"

    local src=$1
    local dst=$2
    local src_folder_name="$(basename $src)"
    local backup_destination="${dst}/${src_folder_name}"

    log_setting "directory to backup" "$src"
    log_setting "address and path of remote backups" "$dst"
    check_exists "${src}/.exclude_remote"

    for f in ${SECRET_FOLDERS[@]}; do
        if [ -d "${src}/$f" ]; then
            check_contains "${src}/.exclude_remote" "$f"
        fi
    done

    sudo rsync  -avz \
                --links \
                --progress \
                --delete \
                --delete-excluded \
                --exclude-from="${src}/.exclude_remote" \
                "${src}/" \
                "${backup_destination}/" ||\
            report "$?" "remote backup via rsync"

    return 0
}

function cleanup_remote_backup {
    # Clean up after remote backup
    # Make sure rsync is done

    ######################################
    # If using the report function here, #
    # make sure it has NO THIRD ARGUMENT #
    # or there will be an infinite loop! #
    # This function may be used to       #
    # handle trapped signals             #
    ######################################

    killall rsync || report "$?" "kill the rsync processes"
    slow rsync
    return 0
}

function all_remote_backups {
    # Run all desired remote backups to a
    # a given destination. This does not
    # include archive to object storage.

    ##########################################################################
    # USES GLOBAL VARIABLES THAT SHOULD BE SET IN .bashrc OR .zshrc OR . . . #
    ##########################################################################

    >&2 echo "${STAMP}: all_remote_backups"

    local destination=$1

    log_setting "destination for a $(hostnamectl hostname) backup set" \
                "${destination}"

    # Make sure we're excluding sensitive files
    # from networked backups
    for f in ${secret_folders[@]}; do
        check_contains "${HOME}/.exclude_remote" "$f"
    done

    # Run remote backups over the wired connection only
    if check_intfc "$MAIN_WIRED"; then
        if ! check_intfc "$MAIN_WIRELESS"; then

            run_remote_backup "${HOME}" "${destination}"

            run_remote_backup '/mnt/data/archive' "${destination}"

            if [ -n "${MONTH}" ]; then
                if [ -d "/mnt/data/${MONTH}" ]; then
                    run_remote_backup "/mnt/data/${MONTH}" "${destination}"
                fi
            fi

            run_remote_backup '/mnt/data/wire' "${destination}"

        fi
    fi
}

function remove_sensitive_data {
    # This function has been carefully tested.
    # BE VERY CAREFUL WITH IT!

    ########################################
    # Do not use the cleanup function here #
    # because it calls this function       #
    ########################################

    ##########################################################
    # It is OK to use the report function here, but it must  #
    # not have a third argument, for that case calls cleanup #
    # which in turn calls this function.                     #
    ##########################################################

    >&2 echo "${STAMP}: remove_sensitive_data"

    local staging=$(realpath "$1")
    local real_home=$(realpath "${HOME}")
    local real_data="/mnt/data"
    local real_gaol="${real_home}/gaol"

    local lrc=0

    log_setting "path to remove sensitive data" "$staging"
    log_setting "path to home folder" "$real_home"

    log_setting "first in list of secret folders" "${SECRET_FOLDERS[0]}"
    log_setting "first in list of secret files" "${SECRET_FILES[0]}"
    log_setting "first in list of sensitive folders" "${SENSITIVE_FOLDERS[0]}"

    # Do not apply this function to home
    if [ "$staging" == "$real_home" ]; then
        # Do not use the cleanup function here because it calls this function
        >&2 echo "${STAMP}: unsafe to remove sensitive data from home"
        return "$UNSAFE"
    fi

    # Do not apply to the whole of the data partition
    if [ "$staging" == "$real_data" ]; then
        # Do not use the cleanup function here because it calls this function
        >&2 echo "${STAMP}: unsafe to remove sensitive data from all of /mnt/data"
        return "$UNSAFE"
    fi

    # Only apply this subfolders of the gaol folder or of the data partition
    if [[ "$staging" != "${real_gaol}"* ]]; then
        if [[ "$staging" != "${real_data}"* ]]; then
            # Do not use the cleanup function here because it calls this function
            >&2 echo "${STAMP}: unsafe to remove sensitive data from ${staging}"
            return "$UNSAFE"
        fi
    fi

    # Deleting using the find command like this leads to
    # lots of not found error messages. For this reason
    # stderr is dumped, but non-zero exit is reported.
    # Links handled separately as a reminder.
    for f in ${SECRET_FOLDERS[@]}; do
        log_setting "secret folder to remove" "$f"

        find "${staging}/" -type l -name "$f" -exec rm -f {} \;
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing secret folders (links)"

        find "${staging}/" -type d -name "$f" -exec rm -rf {} \;
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing secret folders recursively"

    done
    for f in ${SENSITIVE_FOLDERS[@]}; do
        log_setting "sensitive folder to remove" "$f"

        find "${staging}/" -type l -name "$f"  -exec rm -f {} \;
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing sensitive folders (links)"

        find "${staging}/" -type d -name "$f"  -exec rm -rf {} \;
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing sensitive folders recursively"

    done
    for f in ${SECRET_FILES[@]}; do
        log_setting "secret file to remove" "$f"

        find "${staging}/" -type l -name "$f"  -exec rm -f {} \;
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing secret files (links)"

        find "${staging}/" -type f -name "$f"  -exec rm -f {} \;
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing secret files"
    done

    return 0
}

function run_archive {
    # Run an encrypted archive to S3

    ##########################################################
    # The number of seconds to wait is globally set as $WAIT #
    ##########################################################

    ###################################################
    # The number of transfers at once is globally set #
    # as $SIMULTANEOUS_TRANSFERS                      #
    ###################################################

    >&2 echo "${STAMP}: run_archive"

    local clear=$(realpath "$1")
    local src=$(realpath "$2")
    local remote=$3
    local conf="${HOME}/$(hostnamectl hostname)-rclone.conf"

    log_setting "cleartext to archive" "$clear"
    log_setting "folder to archive" "$src"
    log_setting "remote" "$remote"
    log_setting "remote configuration" "$conf"

    check_contains "$conf" "$remote"

    if [ ! -d "${clear}" ]; then
        >&2 echo "${STAMP}: cannot find ${clear}"
        return "${MISSING_FOLDER}"
    fi

    if [ ! -d "${src}" ]; then
        >&2 echo "${STAMP}: cannot find ${src}"
        return "${MISSING_FOLDER}"
    fi

    if grep -qs "cryfs@${src} ${clear}" /proc/mounts; then
        if remove_sensitive_data "${clear}"; then

            listing=$(path_as_name ${src}) ||\
                report $? "construct filename"
            contents="${HOME}/${STAMP}-${listing}.txt"

            echo "cryfs@${src} ${clear}" >> ${contents}
            tree "${clear}" 1>> ${contents} ||\
                report $? "save the tree of archived folders"

            cryfs-unmount "${clear}" ||\
                report $? "unmounting encrypted archive" \
                          "no sync if archive is mounted"

            while grep -qs "cryfs@${src} ${clear}" /proc/mounts; do
                >&2 echo "${STAMP}: ${src} is mounted"
                sleep "${WAIT}"
            done
            until [ -z "$(ls -A ${clear})" ]; do
                >&2 echo "${STAMP}: ${clear} is not empty"
                sleep "${WAIT}"
            done

            rclone sync --config  "$conf" \
                        --progress \
                        --transfers "${SIMULTANEOUS_TRANSFERS}" \
                        --delete-excluded \
                        --exclude cryfs.config \
                        "${src}/" \
                        "${remote}:" ||\
                report $? "sync archive to remote"
        else
            >&2 echo "${STAMP}: failed to remove sensitive data"
        fi
    else
        >&2 echo "${STAMP}: ${src} not mounted, cannot check security"
        return "${MISSING_MOUNT}"
    fi

    return 0
}

function cleanup_run_archive {
    # Clean up after remote backup
    # Make sure rsync is done

    ######################################
    # If using the report function here, #
    # make sure it has NO THIRD ARGUMENT #
    # or there will be an infinite loop! #
    # This function may be used to       #
    # handle trapped signals             #
    ######################################

    killall rclone || report "$?" "kill the rclone processes"
    slow rclone
    return 0
}

function run_shared_preparation {
    # Prepare some files for sharing via SHARED_STAGING

    ##########################################################################
    # USES GLOBAL VARIABLES THAT SHOULD BE SET IN .bashrc OR .zshrc OR . . . #
    ##########################################################################

    >&2 echo "${STAMP}: run_shared_preparation"

    local src=$(realpath "$1")
    local src_folder_name=$(basename $src)
    local staging_area=$(realpath "${SHARED_STAGING}/${src_folder_name}")

    log_setting "directory to backup" "$src"
    log_setting "path to staging areas" "$staging_area"
    check_exists "${src}/.include_shared"

    # Clean out all folders from the staging area
    for f in ${staging_area}/*; do
        if [ -d "$f" ]; then
            rm -rf $f
        fi
    done

    # Synchroinuse to staging
    while read f; do
        echo $f
        if [ -n "$f" ]; then
            check_exists "${src}/${f}"
            if [[ "$staging_area" != "${src}/${f}"* ]]; then
                mkdir -p "${staging_area}/${f}"
                rsync  -av \
                       --links \
                       --progress \
                       --delete \
                       "${src}/${f}/" \
                       "${staging_area}/${f}/" ||\
                    report "$?" "staging files via rsync"
            else
                >&2  echo "${STAMP}: $staging_area is in ${src}/${f}"
                cleanup "$BAD_CONFIGURATION"
            fi
        fi
    done < "${src}/.include_shared"

    # Remove anything we do not share via cloud
    remove_sensitive_data "${SHARED_STAGING}"

    return 0
}

function cleanup_shared_preparation {
    # Clean up after preparation of shared folders

    ##########################################################################
    # USES GLOBAL VARIABLES THAT SHOULD BE SET IN .bashrc OR .zshrc OR . . . #
    ##########################################################################

    killall rsync || report "$?" "kill the rsync processes"
    slow rsync
    remove_sensitive_data "${SHARED_STAGING}"
    echo $(find "${SHARED_STAGING}" -type f | wc -l)  >\
        "${SHARED_STAGING}/FILE_COUNT"
    return 0
}

function handle_signal {
    # cleanup and use error code if we trap a signal
    >&2 echo "${STAMP}: trapped signal during maintenance"
    cleanup "${TRAPPED_SIGNAL}"
}

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
# run_package_maintenance

# Run organiser
# magpie

# Run the backups
# run_local_backup

# Unmount and send encrypted archive via rclone
# to standard S3 storage
# run_archive '/mnt/data/clear' \
#             '/mnt/data/archive' \
#             'clovis-mnt-data-archive-std'

# If available prepare to offload files to
# glacier deep archive storage
# if [ -n "${MONTH}" ]; then
#     if [ -d "/mnt/data/${MONTH}" ]; then
#         run_archive "/mnt/data/${MONTH}/clear" \
#                     "/mnt/data/${MONTH}/offload" \
#                     "clovis-mnt-data-${MONTH}-offload-gda"
#     fi
# fi

# Offload previous month if necessary
# OLDMONTH=""
# if [ -n "${OLDMONTH}" ]; then
#     if [ -d "/mnt/data/${OLDMONTH}" ]; then
#         run_archive "/mnt/data/${OLDMONTH}/clear" \
#                     "/mnt/data/${OLDMONTH}/offload" \
#                     "clovis-mnt-data-${OLDMONTH}-offload-gda"
#     fi
# fi

# Set up folders for sharing via commercial cloud
# run_shared_preparation "${HOME}"

# Run at least one remote backup
## all_remote_backups "${REMOTE_BACKUP}"

# Cleanup and exit with code 0
# cleanup 0
