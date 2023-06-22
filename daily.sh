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

# A path to a remote backup should
# be in $REMOTE_BACKUP, and a second in
# $REMOTE_BACKUP_EXTRA.

MISSING_INPUT=60
MISSING_FILE=61
MISSING_FOLDER=62
MISSING_DISK=63

BAD_CONFIGURATION=70
UNSAFE=71

SYSTEM_UNIT_FAILURE=80
SECURITY_FAILURE=81
NETWORK_ERROR=83

TRAPPED_SIGNAL=113

MAX_SUBPROCESSES=16

WAIT=5.0

UNITS_TO_CHECK=( 'syncthing@gusgw.service' 'sshd.service' )

SECRET_FOLDERS=( '.ssh' '.gnupg' '.cert' '.pki' '.password-store' )
SECRET_FILES=( "*.asc" "*.key" "*.pem" "id_rsa*" "id_dsa*" "id_ed25519*" )

SENSITIVE_FOLDERS=( '.git' '.stfolder' '.stversions' '.local' )

function set_stamp {
    # Store a stamp used to label files
    # and messages created in this script.
    export STAMP="$(date '+%Y%m%d'-$(hostnamectl hostname))"
    return 0
}

function set_month {
    # Set a global variable containing the year and month
    # for use in naming folders to offload
    export MONTH="$(date '+%Y%m')"
    return 0
}

function not_empty {
    # Ensure that an expression is not empty
    # then cleanup and quit if it is
    local description=$1
    local check=$2
    if [ -z "$check" ]; then
        >&2 echo "${STAMP}: cannot run without ${description}"
        cleanup "${MISSING_INPUT}"
    fi
    return 0
}

function log_setting {
    # Make sure a setting is provided
    # and report it
    local description=$1
    local setting=$2
    not_empty "date stamp" "${STAMP}"
    not_empty "$description" "$setting"
    >&2 echo "${STAMP}: ${description} is ${setting}"
}

function check_exists {
    # Make sure a file or folder or link exists
    # then cleanup and quit if not
    local file_name=$1
    log_setting "file or directory name that must exist" "$file_name"
    if ! [ -e "$file_name" ]; then
        >&2 echo "${STAMP}: cannot find $file_name"
        cleanup "$MISSING_FILE"
    fi
    return 0
}

function check_contains {
    # Make sure a file exists and contains
    # the given string.
    local file_name=$1
    local string=$2
    log_setting "file name to check" "$file_name"
    log_setting "string to check for" "$string"
    not_empty "date stamp" "$STAMP"
    if [ -e "$file_name" ]; then
        if ! grep -qs "${string}" "${file_name}"; then
            >&2 echo "${STAMP}: ${file_name} does not contain ${string}"
            cleanup "$BAD_CONFIGURATION"
        fi
    else
        >&2 echo "${STAMP}: cannot find ${file_name}"
        cleanup "$MISSING_FILE"
    fi
    return 0
}

function path_as_name {
    local path=$1
    not_empty "path to convert to a name" "$path"
    echo "$path" |\
        sed 's:^/::' |\
        sed 's:/:-:g' |\
        sed 's/[[:space:]]/_/g'
    return 0
}

function make_active {
    # Make sure a systemd unit is active
    local unit=$1
    log_setting "unit to activate" "$unit"

    if ! sudo systemctl is-active --quiet "$unit"; then
        sudo systemctl start "$unit" ||\
            report $? "starting $unit"
        if sudo systemctl is-failed --quiet "$unit"; then
            sudo systemctl status --no-pager --lines=10 "$unit" ||\
                report $? "get status of $unit"
            cleanup "$SYSTEM_UNIT_FAILURE"
        fi
    fi
    sudo systemctl status --no-pager --lines=0 "$unit" ||\
        report $? "get status of $unit"
    return 0
}

function report {
    # Inform the user of a non-zero return
    # code, cleanup, and if an exit
    # message is provided as a third argument
    # also exit
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
    # Wait for all processes with given name to disappear
    # rsync in particular seems to hang around
    local pname=$1
    log_setting "program name to wait for" "$pname"
    for pid in $(pgrep $pname); do
        while kill -0 "$pid" 2> /dev/null; do
            >&2 echo "${STAMP}: ${pname} ${pid} is still running"
            sleep ${WAIT}
        done
    done
}

function cleanup {

    ######################################
    # If using the report function here, #
    # make sure it has NO THIRD ARGUMENT #
    # or there will be an infinite loop! #
    # This function may be used to       #
    # handle trapped signals             #
    ######################################

    local rc=$1
    >&2 echo "***"
    >&2 echo "${STAMP}: exiting cleanly with code ${rc}. . ."
    cleanup_package_maintenance
    cleanup_run_archive
    cleanup_remote_backup
    cleanup_local_backup
    cleanup_shared_preparation
    >&2 echo "${STAMP}: . . . all done with code ${rc}"
    exit $rc
}

function run_package_maintenance {
    not_empty "date stamp" "$STAMP"

    >&2 echo "${STAMP}: run_package_maintenance"

    # Check for missing files
    sudo pacman -Qk 2> /dev/null 1>\
            "${STAMP}-missing_system_file_list.txt" ||\
        report $? "checking for missing files"

    # Checking for package changes
    sudo pacman -Qkk 2> /dev/null 1>\
            "${STAMP}-altered_system_file_list.txt" ||\
        report $? "checking for altered files"

    # Run regular package related tasks
    sudo pacman -Scc --noconfirm || report "$?" "cleaning package cache"
    sudo pacman -Syu --noconfirm || report "$?" "updating system"

    # Some pacman work taken from the Arch wiki:
    # https://wiki.archlinux.org/title/Pacman/Tips_and_tricks
    if [ "$(sudo pacman -Qtdq | wc -l)" -gt 0 ]; then
        sudo pacman -Qtdq | sudo pacman -Rns - ||\
            report "$?" "remove orphan packages"
    fi
    if [ "$(sudo pacman -Qqd | wc -l)" -gt 0 ]; then
        sudo pacman -Qqd |\
            sudo pacman -Rsu --print - 1>\
                        ${STAMP}-possible_orphan_list.txt ||\
                report "$?" "finding packages that might not be needed"
    fi

    # Try a method of listing explicitly installed packages.
    # Note recent update in the comments.
    # https://unix.stackexchange.com/questions/409895/
    #         pacman-get-list-of-packages-installed-by-user
    sudo pacman -Qqett 1> ${STAMP}-package_list.txt ||\
        report "$?" "create list of explicitly installed package"

    # Get optional dependencies
    # https://wiki.archlinux.org/title/Pacman/Tips_and_tricks
    comm -13 <(pacman -Qqdt | sort) <(pacman -Qqdtt | sort) >\
        ${STAMP}-optional_list.txt

    # Get a list of AUR and other foreign packages
    # https://wiki.archlinux.org/title/Pacman/Tips_and_tricks
    pacman -Qqem > ${STAMP}-foreign_list.txt

    # Check for unowned files
    sudo pacreport --unowned-files 1>\
        ${STAMP}-unowned_list.txt ||\
        report "$?" "finding unowned files"

    # Archive the pacman database
    wd=$(pwd)
    cd /var/lib/pacman/local &&\
        sudo tar -cjf "${wd}/${STAMP}-pacman_database.tar.bz2" . ||\
        report "$?" "saving pacman database"
    cd ${wd} || report $? "return to working directory"
    sudo chown "${USER}:${USER}" "${STAMP}-pacman_database.tar.bz2" ||\
        report "$?" "changing owner and group of pacman database archive"

    return 0
}

function cleanup_package_maintenance {
    # Clean up after package maintenance
    # Get rid of lists of packages

    ######################################
    # If using the report function here, #
    # make sure it has NO THIRD ARGUMENT #
    # or there will be an infinite loop! #
    # This function may be used to       #
    # handle trapped signals             #
    ######################################

    rm -f ${STAMP}-missing_system_file_list.txt
    rm -f ${STAMP}-altered_system_file_list.txt
    rm -f ${STAMP}-package_list.txt
    rm -f ${STAMP}-possible_orphan_list.txt
    rm -f ${STAMP}-optional_list.txt
    rm -f ${STAMP}-foreign_list.txt
    rm -f ${STAMP}-unowned_list.txt
    rm -f ${STAMP}-pacman_database.tar.bz2
    return 0
}

function run_local_backup {
    # Local backup

    ##########################################################################
    # USES GLOBAL VARIABLES THAT SHOULD BE SET IN .bashrc OR .zshrc OR . . . #
    ##########################################################################

    >&2 echo "${STAMP}: run_local_backup"
    
    local home_folder_name=$(basename $HOME)
    local backup_destination="/mnt/${BACKUP_NAME}/${home_folder_name}"
    not_empty "date stamp" "$STAMP"
    log_setting "name of the file with encryption key for local backup" \
                "$KEY_FILE"
    log_setting "device path for local encrypted backup" "$BACKUP_DISK"
    log_setting "name of the backup" "$BACKUP_NAME"
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

    return 0
}

function run_remote_backup {
    # Remote backup skipping sensitive data

    >&2 echo "${STAMP}: run_remote_backup"

    local src=$1
    local dst=$2
    local src_folder_name="$(basename $src)"
    local backup_destination="${dst}/${src_folder_name}"

    log_setting "directory to backup" "$src"
    log_setting "address and path of remote backups" "$dst"
    check_exists "${src}/.exclude_remote"

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

    log_setting "path for staging files to share" "$staging"
    log_setting "path to home folder" "$real_home"

    log_setting "first in list of secret folders" "${SECRET_FOLDERS[0]}"
    log_setting "first in list of secret files" "${SECRET_FILES[0]}"
    log_setting "first in list of sensitive folders" "${SENSITIVE_FOLDERS[0]}"

    if [ "$staging" == "$real_home" ]; then
        # Do not use the cleanup function here because it calls this function
        >&2 echo "${STAMP}: unsafe to remove sensitive data from home"
        return "$UNSAFE"
    fi

    if [ "$staging" == "$real_data" ]; then
        # Do not use the cleanup function here because it calls this function
        >&2 echo "${STAMP}: unsafe to remove sensitive data from all of /mnt/data"
        return "$UNSAFE"
    fi

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
        find "${staging}/" -type l -name "$f" -exec rm -f {} \; 2> /dev/null ||\
            report "$?" "removing secret folders"
        find "${staging}/" -type d -name "$f" -exec rm -rf {} \; 2> /dev/null ||\
            report "$?" "removing secret folders"
    done
    for f in ${SENSITIVE_FOLDERS[@]}; do
        log_setting "sensitive folder to remove" "$f"
        find "${staging}/" -type l -name "$f"  -exec rm -f {} \; 2> /dev/null ||\
            report "$?" "removing sensitive folders"
        find "${staging}/" -type d -name "$f"  -exec rm -rf {} \; 2> /dev/null ||\
            report "$?" "removing sensitive folders"
    done
    for f in ${SECRET_FILES[@]}; do
        log_setting "secret file to remove" "$f"
        find "${staging}/" -type l -name "$f"  -exec rm -f {} \; 2> /dev/null ||\
            report "$?" "removing secret files"
        find "${staging}/" -type f -name "$f"  -exec rm -f {} \; 2> /dev/null ||\
            report "$?" "removing secret files"
    done

    return 0
}

function run_shared_preparation {
    # Prepare some files for sharing via SHARED_STAGING

    ##########################################################################
    # USES GLOBAL VARIABLES THAT SHOULD BE SET IN .bashrc OR .zshrc OR . . . #
    ##########################################################################

    >&2 echo "${STAMP}: run_shared_preparation"

    local src=$1
    local src_folder_name=$(basename $src)
    local staging_area="${SHARED_STAGING}/${src_folder_name}"

    log_setting "directory to backup" "$src"
    log_setting "address and path of staging areas" "$SHARED_STAGING"
    check_exists "${src}/.include_shared"

    while read f; do
        check_exists "${src}/${f}"
        mkdir -p "${staging_area}/${f}"
        rsync  -av \
               --links \
               --progress \
               --delete \
               "${src}/${f}/" \
               "${staging_area}/${f}/" ||\
            report "$?" "staging files via rsync"
    done < .include_shared

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

function run_archive {
    # Run an encrypted archive to S3

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
                        --transfers 16 \
                        --delete-excluded \
                        --exclude cryfs.config \
                        "${src}/" \
                        "${remote}:" ||\
                report $? "sync archive to remote"
        fi
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

function firewall_active {
    # Check the firewall is up
    not_empty "date stamp" "$STAMP"

    >&2 echo "${STAMP}: firewall_active"

    if sudo ufw status | grep -qs "Status: inactive"; then
        sudo ufw enable || report $? "enable firewall"
        if sudo ufw status | grep -qs "Status: inactive"; then
            >&2 echo "${STAMP}: failed to activate firewall"
            return "$SECURITY_FAILURE"
        fi
    fi
    sudo ufw status numbered || report $? "state firewall rules"
    return 0
}

function ping_router {
    # Make sure we can ping the local router
    local intfc=$1
    log_setting "ping router via interface" "$intfc"
    rc=1
    while  [ "$rc" -gt 0 ]; do
        sleep ${WAIT}
        ping -q -w 1 -c 1 `ip route |\
                           grep default |\
                           grep "$intfc" |\
                           cut -d ' ' -f 3`
        rc=$?
    done
    if [ "$rc" -gt 0 ]; then
        report "$rc" "ping to local router via $intfc" "no network so stop"
    fi
    return 0
}

function ping_check {
    # Check ping via given interface to given url
    local intfc=$1
    local tgt=$2
    not_empty "date stamp" "$STAMP"
    log_setting "interface to check" "$intfc"
    log_setting "url for ping" "$tgt"

    # Max lost packet percentage
    max_loss=50
    packet_count=10
    timeout=20
    packets_lost=$(ping -W $timeout -c $packet_count -I $intfc $tgt |\
                   grep % |\
                   awk '{print $6}')
    if ! [ -n "$packets_lost" ] || [ "$packets_lost" == "100%" ]; then
        cleanup $NETWORK_ERROR
        >&2 echo "${STAMP}: all packets lost from ${tgt} via ${intfc}"
    else
        if [ "${packets_lost}" == "0%" ]; then
            return 0
        else
            # Packet loss rate between 0 and 100%
            >&2 echo "${STAMP}: $packets_lost packets \
                      lost from ${tgt} via ${intfc}"
            real_loss=$(echo $packets_lost | sed 's/.$//')
            if [[ ${real_loss} -gt ${max_loss} ]]; then
                cleanup $NETWORK_ERROR
            else
                return 0
            fi
        fi
    fi
}

function check_intfc {
    # Check an interface is available
    local intfc=$1
    log_setting "interface to check" "$intfc"
    intfc_list=$(ip link |\
                 sed -n  '/^[0-9]*:/p' | grep UP | grep -v DOWN |\
                 sed 's/^[0-9]*: \([0-9a-z]*\):.*/\1/')
    for i in $intfc_list; do
        if [ "$i" == "$intfc" ]; then
            return 0
        fi
    done
    return 1
}

function check_single_tunnel {
    # Make sure there is only a single tunnel set up

    >&2 echo "${STAMP}: check_single_tunnel"

    count=$(ip link |\
            sed -n  '/^[0-9]*:/p' |\
            sed 's/^[0-9]*: \([0-9a-z]*\):.*/\1/' |\
            grep tun |\
            wc -l)
    if [ "$count" -eq 0 ]; then
        >&2 echo "${STAMP}: tunnel not found"
        return 1
    else
        if [ "$count" -gt 1 ]; then
            >&2 echo "${STAMP}: too many tunnels found"
            cleanup "$NETWORK_ERROR"
        else
            return 0
        fi
    fi
}

function start_tunnel {
    # Start the OpenVPN encrypted tunnel

    >&2 echo "${STAMP}: start_tunnel"

    local ovpn=$1
    log_setting "OpenVPN configuration to start" "$ovpn"
    killall openvpn || report $? "stopping any tunnel"
    slow openvpn
    sudo openvpn --daemon --config "$ovpn"
    while ! check_single_tunnel; do
        sleep "$WAIT"
    done
    return 0
}

function network_check {

    >&2 echo "${STAMP}: network_check"

    local wired=$1
    local wireless=$2
    local tunnel=$3
    local default_ovpn=$4

    # Make source network connection is as expected
    log_setting "usual wired interface" "$wired"
    log_setting "usual wireless interface" "$wireless"
    log_setting "tunnel interface" "$tunnel"
    log_setting "default VPN configuration" "$default_ovpn"

    firewall_active
    if check_intfc "$wired"; then
        sudo rfkill block wlan
        ping_router "$wired"
    else
        sudo rfkill unblock wlan
        ping_router "$wireless"
    fi
    if ! (check_intfc "$tunnel" &&\
          ping_check "$tunnel" wiki.archlinux.org); then
        start_tunnel $default_ovpn
    fi
    return 0
}

function system_check {
    # Check services are running

    ##########################################################################
    # USES GLOBAL VARIABLES THAT SHOULD BE SET IN .bashrc OR .zshrc OR . . . #
    ##########################################################################

    >&2 echo "${STAMP}: system_check"

    for svc in "${UNITS_TO_CHECK[@]}"; do
        make_active "${svc}"
    done
    return 0
}

# Thanks to Stack Overflow for this
# https://stackoverflow.com/questions/8808415/
# using-bash-to-tell-whether-or-not-a-drive-with-a-given-uuid-is-mounted
function is_mounted_by_uuid {
    local input_path=$(readlink -f "$1")
    local input_major_minor=$(stat -c '%T %t' "$input_path")

    log_setting "path to disk" "$input_path"

    cat /proc/mounts | cut -f-1 -d' ' | while read block_device; do
        if [ -b "$block_device" ]; then
            block_device_real=$(readlink -f "$block_device")
            blkdev_major_minor=$(stat -c '%T %t' "$block_device_real")

            if [ "$input_major_minor" == "$blkdev_major_minor" ]; then
                return 255
            fi
        fi
    done

    if [ $? -eq 255 ]; then
        return 0
    else
        return 1
    fi
}

function sync_music_mp3 {

    ##########################################################################
    # USES GLOBAL VARIABLES THAT SHOULD BE SET IN .bashrc OR .zshrc OR . . . #
    ##########################################################################

    >&2 echo "${STAMP}: sync_music_mp3"

    local music=$1
    local player_disk=$2
    local player=$3

    log_setting "music folder" "$music"
    log_setting "music player disk" "$player_disk"
    log_setting "music player mounted folder" "$player"
    log_setting "maximum number of subprocesses" "${MAX_SUBPROCESSES}"

    check_exists "$music"
    check_exists "$player_disk"
    check_exists "$player"

    shopt -s globstar
    count=0
    for f in ${music}/**/*.m4a; do
        short=$(basename "$f")
        echo $short
        if [ ! -e "${f/m4a/mp3}" ]; then
            ffmpeg  -v 5 -y -i "$f" \
                    -acodec libmp3lame \
                    -ac 2 \
                    -ab 192k \
                    "${f/m4a/mp3}" ||\
                report "$?" "converting $short" &
        fi
        count=$((count+1))
        if [ "$count" -gt "${MAX_SUBPROCESSES}" ]; then
            wait
            count=0
        fi
    done

    if is_mounted_by_uuid "$player_disk"; then

        if [ -e "$player" ]; then

            sudo rsync  -av --no-perms --no-owner --no-group \
                        --links \
                        --progress \
                        --delete \
                        --include="*/" \
                        --include="*.mp3" \
                        --exclude="*" \
                        "${music}/" \
                        "${player}/" ||\
                    report "$?" "sync music to player"

        else
            return "$MISSING_FOLDER"
        fi

    else
        return "$MISSING_DISK"
    fi

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

function handle_signal {
    # cleanup and use error code if we trap a signal
    >&2 echo "${STAMP}: trapped signal during maintenance"
    cleanup "${TRAPPED_SIGNAL}"
}

# Start by setting a handler for signals that stop work
trap handle_signal 1 2 3 6

# Set a stamp for use in messages and file names
set_stamp

# Set the month for use in the encrypted folder to offload,
# and other occasional maintenance.
set_month
# Check the network
network_check "$MAIN_WIRED" "$MAIN_WIRELESS" "$MAIN_TUNNEL" "$DEFAULT_VPN"

# System checks
system_check

# # Run package related maintenance tasks
# run_package_maintenance

# # Run the backups
# run_local_backup

# # Unmount and send encrypted archive via rclone
# run_archive '/mnt/data/clear' \
#             '/mnt/data/archive' \
#             'clovis-mnt-data-archive-1ia'

# # # If available prepare to offload files
# # if [ -n "${MONTH}" ]; then
# #     if [ -d "/mnt/data/${MONTH}" ]; then
# #         run_archive "/mnt/data/${MONTH}/clear" \
# #                     "/mnt/data/${MONTH}/offload" \
# #                     "clovis-mnt-data-${MONTH}-offload-1ia"
# #     fi
# # fi

# # Set up folders for sharing via commercial cloud
# run_shared_preparation "${HOME}"

# # Run at least one remote backup
# all_remote_backups "${REMOTE_BACKUP}"

# Only run if music player is available and if so mount first
sync_music_mp3  "${HOME}/cloud/music" \
                "${MUSIC_PLAYER}" \
                "${HOME}/mnt/lucy/Music files"

# Cleanup and exit with code 0
cleanup 0
