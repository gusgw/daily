##  Remove sensitive data before sharing
#   Use this to make sure critical files are
#   not accidentally uploaded.

##  Settings
#   STAMP               should be set by a call to set_stamp in useful.sh.
#   SECRET_FOLDERS      folders with keys, certificates, and passwords
#   SECRET_FILES        files containing keys, certificates, and passwords
#   SENSITIVE_FOLDERS   folders that are best not shared

##  Default
#   HOME
#   MNTDATA
#   GAOL

##  Dependencies
#   return_codes.sh
#   settings.sh
#   useful.sh

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
    local real_data=$(realpath "${MNTDATA}")
    local real_gaol=$(realpath "${GAOL}")

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