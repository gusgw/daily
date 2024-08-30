##  Copy or archive to cloud storage services

##  Settings
#   STAMP                   should be set by a call to set_stamp in useful.sh.
#   SHARED_STAGING          store a copy of shared folders ready for upload to a cloud drive
#   SIMULTANEOUS_TRANSFERS  number of simultaneous transfers for rclone
#   WAIT                    seconds between tries

##  Dependencies
#   return_codes.sh
#   settings.sh
#   useful.sh


##  Notes
#   Remote archives are copies files and folders to S3
#   style object storage, as opposed to disk storage.
#   Folders archived are encrypted and sent via `rclone`.
#   If the encrypted folder is mounted,
#   make sure there is no harm in sending it
#   to S3. If the test passes, unmount
#   and clone to S3. This is done for a general
#   archive as well as monthly sets.
#   File lists are saved.
#   rclone does not use the default configuration, instead it reads
#   the more prominent ${HOME}/$(hostnamectl hostname)-rclone.conf.
#
#   The shared preparation routine sets up a copy of
#   the folder tree with sensitive or secret files and
#   folders removed so that it can be uploaded to
#   a cloud file sharing system. The location for staging
#   folders ready for upload is set as `$SHARED_STAGING`,
#   an environment variable set in `.zshrc` or similar.
#   Setup a folder full of usefully shared files,
#   with anything sensitive automatically removed.


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