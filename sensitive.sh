#!/bin/bash
##  Detect and handle sensitive data before cloud sync
#   Use this to make sure critical files are not accidentally uploaded.

##  Settings
#   STAMP               should be set by a call to set_stamp in bump.sh
#   SECRET_FOLDERS      folders with keys, certificates, and passwords
#   SECRET_FILES        files containing keys, certificates, and passwords
#   SENSITIVE_FOLDERS   folders that are best not shared

##  Dependencies
#   return_codes.sh
#   settings.sh
#   bump.sh

# =============================================================================
#   SENSITIVE FILE DETECTION
# =============================================================================

function check_sensitive_files {
    # Check a directory for sensitive files and folders
    # Does NOT delete anything - only reports findings
    #
    # Arguments:
    #   $1 - Directory to scan
    #
    # Returns:
    #   0 - No sensitive files found
    #   1 - Sensitive files found (details in stderr)
    #
    # Example:
    #   if ! check_sensitive_files "/path/to/sync"; then
    #       echo "Sensitive files detected, aborting sync"
    #   fi

    local csf_dir=$1
    local csf_found=0

    log_message "check_sensitive_files ${csf_dir}"

    not_empty "directory to scan" "$csf_dir"

    if [ ! -d "$csf_dir" ]; then
        log_message "check_sensitive_files: invalid directory"
        return 1
    fi

    # Check for secret folders
    for pattern in "${SECRET_FOLDERS[@]}"; do
        local matches
        matches=$(find "$csf_dir" -type d -name "$pattern" 2>/dev/null | head -5)
        if [ -n "$matches" ]; then
            log_message "WARNING: Secret folder '$pattern' found:"
            echo "$matches" | while read -r match; do
                >&2 echo "  - $match"
            done
            csf_found=1
        fi
    done

    # Check for secret files
    for pattern in "${SECRET_FILES[@]}"; do
        local matches
        matches=$(find "$csf_dir" -type f -name "$pattern" 2>/dev/null | head -5)
        if [ -n "$matches" ]; then
            log_message "WARNING: Secret file pattern '$pattern' found:"
            echo "$matches" | while read -r match; do
                >&2 echo "  - $match"
            done
            csf_found=1
        fi
    done

    # Check for sensitive folders
    for pattern in "${SENSITIVE_FOLDERS[@]}"; do
        local matches
        matches=$(find "$csf_dir" -type d -name "$pattern" 2>/dev/null | head -5)
        if [ -n "$matches" ]; then
            log_message "WARNING: Sensitive folder '$pattern' found:"
            echo "$matches" | while read -r match; do
                >&2 echo "  - $match"
            done
            csf_found=1
        fi
    done

    if [ "$csf_found" -eq 0 ]; then
        log_message "No sensitive files found in ${csf_dir}"
        return 0
    else
        log_message "Sensitive files detected - sync should use exclusions"
        return 1
    fi
}

# =============================================================================
#   RCLONE EXCLUSION GENERATION
# =============================================================================

function build_rclone_excludes {
    # Generate rclone --exclude arguments for sensitive files/folders
    # Outputs exclude arguments to stdout for use in command construction
    #
    # Usage:
    #   local excludes
    #   excludes=$(build_rclone_excludes)
    #   rclone sync $excludes source: dest:

    local bre_excludes=""

    # Exclude secret folders
    for pattern in "${SECRET_FOLDERS[@]}"; do
        bre_excludes="${bre_excludes} --exclude ${pattern}/ --exclude **/${pattern}/"
    done

    # Exclude secret files
    for pattern in "${SECRET_FILES[@]}"; do
        bre_excludes="${bre_excludes} --exclude ${pattern} --exclude **/${pattern}"
    done

    # Exclude sensitive folders
    for pattern in "${SENSITIVE_FOLDERS[@]}"; do
        bre_excludes="${bre_excludes} --exclude ${pattern}/ --exclude **/${pattern}/"
    done

    # Exclude syncthing working files
    for pattern in "${SYNCTHING_FILES[@]}"; do
        bre_excludes="${bre_excludes} --exclude ${pattern} --exclude **/${pattern}"
    done

    # Output the exclude string (trimmed)
    echo "${bre_excludes# }"
}

function get_rclone_exclude_array {
    # Generate rclone exclude patterns as an array
    # Useful when building commands with proper quoting
    #
    # Usage:
    #   local -a excludes
    #   mapfile -t excludes < <(get_rclone_exclude_array)
    #   rclone sync "${excludes[@]}" source: dest:

    # Secret folders
    for pattern in "${SECRET_FOLDERS[@]}"; do
        echo "--exclude"
        echo "${pattern}/"
        echo "--exclude"
        echo "**/${pattern}/"
    done

    # Secret files
    for pattern in "${SECRET_FILES[@]}"; do
        echo "--exclude"
        echo "${pattern}"
        echo "--exclude"
        echo "**/${pattern}"
    done

    # Sensitive folders
    for pattern in "${SENSITIVE_FOLDERS[@]}"; do
        echo "--exclude"
        echo "${pattern}/"
        echo "--exclude"
        echo "**/${pattern}/"
    done

    # Syncthing working files
    for pattern in "${SYNCTHING_FILES[@]}"; do
        echo "--exclude"
        echo "${pattern}"
        echo "--exclude"
        echo "**/${pattern}"
    done
}

# =============================================================================
#   LEGACY FUNCTION (DEPRECATED)
# =============================================================================

function remove_sensitive_data {
    # DEPRECATED: This function deletes sensitive files from a directory
    # Prefer using check_sensitive_files() + build_rclone_excludes() instead
    #
    # This function is kept for backwards compatibility but will emit a warning.
    #
    # Arguments:
    #   $1 - Directory to clean (must be in GAOL or /mnt/data subdirectory)
    #
    # Returns:
    #   0 - Success
    #   UNSAFE - If attempting to clean unsafe directory

    log_message "WARNING: remove_sensitive_data is deprecated"
    log_message "Consider using check_sensitive_files + rclone exclusions instead"

    local staging
    staging=$(realpath "$1")
    local real_home
    real_home=$(realpath "${HOME}")
    local real_data
    real_data=$(realpath "${MNTDATA:-/mnt/data}")
    local real_gaol
    real_gaol=$(realpath "${GAOL:-/mnt/data/gaol}")

    local lrc=0

    log_setting "path to remove sensitive data" "$staging"
    log_setting "path to home folder" "$real_home"

    log_setting "first in list of secret folders" "${SECRET_FOLDERS[0]}"
    log_setting "first in list of secret files" "${SECRET_FILES[0]}"
    log_setting "first in list of sensitive folders" "${SENSITIVE_FOLDERS[0]}"

    # Do not apply this function to home
    if [ "$staging" == "$real_home" ]; then
        log_message "unsafe to remove sensitive data from home"
        return "$UNSAFE"
    fi

    # Do not apply to the whole of the data partition
    if [ "$staging" == "$real_data" ]; then
        log_message "unsafe to remove sensitive data from all of /mnt/data"
        return "$UNSAFE"
    fi

    # Only apply this to subfolders of the gaol folder or of the data partition
    if [[ "$staging" != "${real_gaol}"* ]]; then
        if [[ "$staging" != "${real_data}"* ]]; then
            log_message "unsafe to remove sensitive data from ${staging}"
            return "$UNSAFE"
        fi
    fi

    # Delete secret folders
    for f in "${SECRET_FOLDERS[@]}"; do
        log_setting "secret folder to remove" "$f"
        find "${staging}/" -type l -name "$f" -exec rm -f {} \; 2>/dev/null
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing secret folders (links)"

        find "${staging}/" -type d -name "$f" -exec rm -rf {} \; 2>/dev/null
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing secret folders recursively"
    done

    # Delete sensitive folders
    for f in "${SENSITIVE_FOLDERS[@]}"; do
        log_setting "sensitive folder to remove" "$f"
        find "${staging}/" -type l -name "$f" -exec rm -f {} \; 2>/dev/null
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing sensitive folders (links)"

        find "${staging}/" -type d -name "$f" -exec rm -rf {} \; 2>/dev/null
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing sensitive folders recursively"
    done

    # Delete secret files
    for f in "${SECRET_FILES[@]}"; do
        log_setting "secret file to remove" "$f"
        find "${staging}/" -type l -name "$f" -exec rm -f {} \; 2>/dev/null
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing secret files (links)"

        find "${staging}/" -type f -name "$f" -exec rm -f {} \; 2>/dev/null
        lrc=$?
        [ "$lrc" -gt 0 ] && report "$lrc" "removing secret files"
    done

    return 0
}
