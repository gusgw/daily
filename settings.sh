#!/bin/bash
##  Settings for daily.sh
##  Machine-specific values come from environment variables (set in env.sh)

##  Default
#   USER is inherited from environment

# =============================================================================
#   PROCESS LIMITS AND TIMING
# =============================================================================

#   Limits for parallel work
#   rclone parallel transfers. Was 32, which saturated the single NVMe and
#   all CPU cores and starved the Wayland session into unresponsiveness when
#   daily.sh ran next to an interactive session (2026-06-05). rclone's own
#   default is 4.
SIMULTANEOUS_TRANSFERS=4

#   throttle: run a heavy maintenance command at low priority so it yields
#   to anything interactive (the Wayland session, a shell). `nice -n 19`
#   lowers CPU priority and is effective on every I/O scheduler. `ionice
#   -c 3` (idle) lowers disk priority but only takes effect under the BFQ
#   scheduler; nvme0n1 currently uses `none`, where it is a harmless no-op,
#   so the real disk relief comes from the lower SIMULTANEOUS_TRANSFERS
#   above. The wrapper passes the wrapped command's exit status straight
#   through (verified: `nice -n 19 ionice -c 3 true` returns 0).
throttle() {
    nice -n 19 ionice -c 3 "$@"
}

#   Set a wait time in seconds for any task that is attempted repeatedly
WAIT=5.0

#   Number of attempts for checks that repeat on fail
ATTEMPTS=10

#   SSH connection timeout (seconds)
SSH_TIMEOUT=5

# =============================================================================
#   NETWORK CONFIGURATION
# =============================================================================

#   Network interfaces (must be set in env.sh)
MAIN_WIRED="${MAIN_WIRED:?MAIN_WIRED must be set in env.sh}"
MAIN_WIRELESS="${MAIN_WIRELESS:?MAIN_WIRELESS must be set in env.sh}"

#   WireGuard VPN interface name
WIREGUARD_INTERFACE="wg0"

#   Expected DNS server when VPN is connected
VPN_DNS="${VPN_DNS:?VPN_DNS must be set in env.sh}"

# =============================================================================
#   ZFS CONFIGURATION
# =============================================================================

#   ZFS pool name (must be set in env.sh)
ZFS_POOL="${ZFS_POOL:?ZFS_POOL must be set in env.sh}"

#   Warn if last scrub was more than this many days ago
SCRUB_WARN_DAYS=30

#   Warn if pool capacity exceeds this percentage
POOL_CAPACITY_WARN=80

# =============================================================================
#   SYSTEM HEALTH
# =============================================================================

#   Warn if systemd journal exceeds this size
JOURNAL_WARN_SIZE="1G"

#   Thermal management settings
#   Warn if CPU package temperature exceeds this (Celsius)
TEMP_WARN_THRESHOLD=85
#   Critical if CPU package temperature exceeds this (Celsius)
TEMP_CRIT_THRESHOLD=95
#   Thermal management services that should be running
THERMAL_SERVICES=( 'throttled.service' 'thinkfan.service' 'tlp.service' )

#   Make sure these units are active
UNITS_TO_CHECK=( 'sanoid.timer' )

# =============================================================================
#   BACKUP CONFIGURATION
# =============================================================================

#   Directory containing backup configuration files
BACKUP_CONFIGS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backup-configs"

#   ZFS backup targets for zbackup script
#   Set ZFS_BACKUP_TARGETS in env.sh as a space-delimited string of config names
#   e.g., export ZFS_BACKUP_TARGETS="poolA poolB"
#   zbackup --config <name> handles drive detection and pool import
_zfs_backup_targets_str="${ZFS_BACKUP_TARGETS:-}"
ZFS_BACKUP_TARGETS=()
if [ -n "$_zfs_backup_targets_str" ]; then
    IFS=' ' read -ra ZFS_BACKUP_TARGETS <<< "$_zfs_backup_targets_str"
fi

#   Syncoid remote replication settings
#   Host should match SSH config entry; leave empty to disable syncoid
SYNCOID_REMOTE_HOST="${SYNCOID_REMOTE_HOST:-}"
#   Destination pool on remote host
SYNCOID_REMOTE_POOL="${SYNCOID_REMOTE_POOL:-}"

#   Syncoid source datasets to replicate
#   Set SYNCOID_DATASETS in env.sh as space-delimited paths relative to ZFS_POOL
#   e.g., export SYNCOID_DATASETS="user/src user/cloud user/encrypted"
#   Each is prefixed with ${ZFS_POOL}/ to form the full dataset path
SYNCOID_TARGETS=()
if [ -n "${SYNCOID_DATASETS:-}" ]; then
    IFS=' ' read -ra _syncoid_parts <<< "$SYNCOID_DATASETS"
    for _part in "${_syncoid_parts[@]}"; do
        SYNCOID_TARGETS+=("${ZFS_POOL}/${_part}")
    done
    unset _syncoid_parts _part
fi

#   Root filesystem backup (leave empty to skip)
#   ROOT_BACKUP_POOL: pool to import for root backup
#   ROOT_BACKUP_CONFIG: config file name in backup-configs/ for drive ID lookup
#   ROOT_BACKUP_DATASET: full dataset path to mount at /mnt/root
ROOT_BACKUP_POOL="${ROOT_BACKUP_POOL:-}"
ROOT_BACKUP_CONFIG="${ROOT_BACKUP_CONFIG:-}"
ROOT_BACKUP_DATASET="${ROOT_BACKUP_DATASET:-}"

# =============================================================================
#   CLOUD SYNC CONFIGURATION
# =============================================================================

#   Cloud sync targets for rclone
#   Set CLOUD_SYNCS in env.sh as space-delimited entries
#   Format: "local_path:remote_name:remote_path[:mode]"
#   mode is optional: bisync (default), sync, or copy
#   For SFTP remotes, host reachability is checked before syncing
_cloud_syncs_str="${CLOUD_SYNCS:-}"
CLOUD_SYNCS=()
if [ -n "$_cloud_syncs_str" ]; then
    IFS=' ' read -ra CLOUD_SYNCS <<< "$_cloud_syncs_str"
fi
unset _cloud_syncs_str

# =============================================================================
#   SYNCTHING CONFIGURATION
# =============================================================================

#   Syncthing sync folders to monitor for conflicts
#   Set SYNCTHING_FOLDERS in env.sh as space-delimited absolute paths
#   e.g., export SYNCTHING_FOLDERS="/home/user/cloud /home/user/local"
_syncthing_folders_str="${SYNCTHING_FOLDERS:-}"
SYNCTHING_FOLDERS=()
if [ -n "$_syncthing_folders_str" ]; then
    IFS=' ' read -ra SYNCTHING_FOLDERS <<< "$_syncthing_folders_str"
fi
unset _syncthing_folders_str

# =============================================================================
#   SECURITY SETTINGS
# =============================================================================

#   Automatically ensure that these folders and files
#   are not copied to remote backups or cloud storage
SECRET_FOLDERS=( '.ssh' '.gnupg' '.cert' '.pki' '.password-store' )
SECRET_FILES=( "*.asc" "*.key" "*.pem" "id_rsa*" "id_dsa*" "id_ed25519*" ".env" )

#   Syncthing working files (excluded from rclone sync)
SYNCTHING_FILES=( ".stignore" ".syncthing.*.tmp" )

#   Syncthing config file (used to pause/unpause folders during rclone sync)
SYNCTHING_CONFIG="${HOME}/.local/state/syncthing/config.xml"

#   Also keep these from being sent to cloud storage
SENSITIVE_FOLDERS=( '.git' '.stfolder' '.stversions' '.local'
                    '*venv*' 'node_modules' '__pycache__' '.cache' )

# =============================================================================
#   OUTPUT FORMATTING
# =============================================================================

#   Symbols to separate output sections
RULE="***"
