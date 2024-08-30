##  Run local and remote backups

##  Settings
#   STAMP               should be set by a call to set_stamp in useful.sh.
#   KEY_FILE            decrypt local backup destination
#   BACKUP_DISK         path to backup disk device by-uuid
#   BACKUP_NAME         name to use in mount
#   EXTRA_BACKUP_DISK   add a second backup disk by-uuid
#   EXTRA_BACKUP_NAME   name of mount for second backup disk
#   MAIN_WIRED          expected wired interface
#   MAIN_WIRELESS       expected wireless interface
#   SECRET_FOLDERS      make sure these folders are in .exclude_remote
#   ~/.exclude_local    list of files and folders to exclude from local backup
#   ~/.exclude_remote   list of files and folders to exclude from remote backup

##  Default
#   HOME

##  Dependencies
#   return_codes.sh
#   settings.sh
#   useful.sh

##  Notes
#   Backup everything not in `~/.exclude_local` to
#   a key drive or similar. Controlled using
#   global settings.
#   Set a key file to decrypt the backup disk in the
#   environment variable `KEY_FILE`.
#   Make sure the backup device is set in the environment
#   variable `BACKUP_DISK`.
#   Make sure the backup name is set in the environment
#   variable `BACKUP_NAME`. This will be used as the device
#   name for the unlocked drive.
#   Files to be excluded from the local backup are listed
#   in `~/.exclude_local`, which is passed to `rsync`.
#
#   Send everything not in `~/.exclude_remote`
#   to a remote destination after making sure
#   secret folders are in the excludes.
#   These routines copy to machines administered by me.
#   See cloud.sh for archiving to S3 or the use of Proton
#   and Google drives.
#   Paths to remote backup should be `$REMOTE_BACKUP` and
#   `$REMOTE_BACKUP_EXTRA`. The remote backup routine is
#   applied to the home folder, and so includes a check that
#   `${SECRET_FOLDERS[@]}` are included in the
#   `~/.exclude_remote` list, which is passed to `rsync`.
#   Usual remote backup destinations are set globally.
#   Remote backups are run over MAIN_WIRED but not MAIN_WIRELESS.

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
    for f in ${SECRET_FOLDERS[@]}; do
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
