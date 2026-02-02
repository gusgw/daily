#!/bin/bash
##  Root filesystem backup via rsync
#
#   Usage:
#     rbackup
#
#   Backs up the root filesystem to /mnt/root using rsync.
#   Excludes virtual filesystems, caches, logs, and user data.
#   Requires /mnt/root to be mounted (typically a ZFS dataset).

set -uo pipefail

# Resolve the actual script location, following symbolic links
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"

# Source machine-specific environment variables if env.sh exists
if [[ -f "${SCRIPT_DIR}/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/env.sh"
fi

# Source BUMP library
# shellcheck source=bump/bump.sh
source "${SCRIPT_DIR}/bump/bump.sh"

# Run the root filesystem rsync
run_root_rsync() {
    sudo rsync -aAXHxvP --numeric-ids --info=progress2 --delete \
        --exclude='/dev/*' \
        --exclude='/proc/*' \
        --exclude='/sys/*' \
        --exclude='/run/*' \
        --exclude='/tmp/*' \
        --exclude='/mnt/*' \
        --exclude='/media/*' \
        --exclude='/lost+found' \
        --exclude='/home/*' \
        --exclude='/opt/*' \
        --exclude='/var/tmp/*' \
        --exclude='/var/cache/*' \
        --exclude='/var/log/*' \
        --exclude='/swapfile' \
        --exclude='/.snapshots/*' \
        --exclude='/var/lib/docker/*' \
        --exclude='/var/lib/lxd/*' \
        --exclude='/var/lib/libvirt/images/*' \
        --exclude='/var/lib/zfs/zpool.cache' \
        --exclude='/etc/zfs/zpool.cache' \
        / /mnt/root/
}

main() {
    set_stamp

    log_message "rbackup: starting root filesystem backup"

    # Check that /mnt/root is mounted
    if ! mountpoint -q /mnt/root 2>/dev/null; then
        log_message "rbackup: /mnt/root is not mounted"
        exit "$MISSING_MOUNT"
    fi

    run_root_rsync
    local rc=$?

    if [ "$rc" -eq 0 ]; then
        log_message "rbackup: root filesystem backup completed"
    elif [ "$rc" -eq 23 ]; then
        log_message "rbackup: partial transfer (exit 23) - some files may have been skipped"
        rc=0
    else
        log_message "rbackup: rsync failed with exit code $rc"
    fi

    exit "$rc"
}

# Only run main when executed directly (not when sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
