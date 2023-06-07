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
# be in $REMOTE_BACKUP

MISSING_INPUT=60
MISSING_FILE=61

BAD_CONFIGURATION=70

SYSTEM_UNIT_FAILURE=80
SECURITY_FAILURE=81
NETWORK_ERROR=83

TRAPPED_SIGNAL=113

secret=( '.ssh' '.gnupg' '.cert' '.pki' '.password-store' )

essential=( 'syncthing@gusgw.service' 'sshd.service' )

wireless='wlan0'
wired='eth1'
tunnel='tun0'

default_ovpn="${HOME}/opt/vpn/au.gusgwnet.udp.ovpn"

function set_stamp {
    # Store a stamp used to label files
    # and messages created in this script.
    export STAMP="$(date '+%Y%m%d'-$(hostnamectl hostname))"
    return 0
}

function not_empty {
    local description=$1
    local check=$2
    if [ -z "$check" ]; then
        >&2 echo "${STAMP}: cannot run without ${description}"
        cleanup "${MISSING_INPUT}"
    fi
    return 0
}

function log_setting {
    local description=$1
    local setting=$2
    not_empty "date stamp" "${STAMP}"
    not_empty "$description" "$setting"
    >&2 echo "${STAMP}: ${description} is ${setting}"
}

function check_exists {
    local file_name=$1
    log_setting "file name that must exist" "$file_name"
    if ! [ -e "$file_name" ]; then
        >&2 echo "${STAMP}: cannot find $file_name"
        cleanup "$MISSING_FILE"
    fi
    return 0
}

function check_contains {
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
    log_setting "program name to wait for" "$pname"
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
    >&2 echo "${STAMP}: exiting cleanly with code ${rc}. . ."
    cleanup_package_maintenance
    cleanup_remote_backup
    cleanup_local_backup
    >&2 echo "${STAMP}: . . . all done with code ${rc}"
    exit $rc
}

function run_package_maintenance {
    not_empty "date stamp" "$STAMP"

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
            sudo pacman -Rsu --print - 1> ${STAMP}-possible_orphan_list.txt ||\
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
    # This function may be used to handle trapped signals
    # Get rid of lists of packages
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
    local home_folder_name=$(basename $HOME)
    local backup_destination="/mnt/${BACKUP_NAME}/${home_folder_name}"
    not_empty "date stamp" "$STAMP"
    log_setting "name of the file with encryption key for local backup" "$KEY_FILE"
    log_setting "device path for local encrypted backup" "$BACKUP_DISK"
    log_setting "name of the backup" "$BACKUP_NAME"
    check_exists "${HOME}/.exclude_local"

    if [ -e "$BACKUP_DISK" ]; then
        sudo cryptsetup open --key-file="$KEY_FILE" "$BACKUP_DISK" "$BACKUP_NAME" ||\
            report $? "unlock backup disk"
        sudo fsck -a "/dev/mapper/$BACKUP_NAME" ||\
            report $? "running file system check on /dev/mapper/$BACKUP_NAME"
        sudo mount "/dev/mapper/$BACKUP_NAME" "/mnt/$BACKUP_NAME" ||\
            report $? "mount backup disk"
        if [ -d "$backup_destination" ]; then
            echo $LOCAL_EXCLUDES
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
            >&2 echo "${STAMP}: local backup destination not found - continuing . . ."
        fi
    else
        >&2 echo "${STAMP}:  local backup device not found - continuing . . ."
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
    if grep -qs "/mnt/${BACKUP_NAME}" /proc/mounts; then
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
    local tgt=$1
    local tgt_folder_name=$(basename $tgt)
    local backup_destination="$REMOTE_BACKUP/${tgt_folder_name}"

    log_setting "directory to backup" "$tgt"
    log_setting "address and path of remote backup" "$REMOTE_BACKUP"
    check_exists "${tgt}/.exclude_remote"

    sudo rsync  -avz \
                --links \
                --progress \
                --delete \
                --delete-excluded \
                --exclude-from="${tgt}/.exclude_remote" \
                "${tgt}/" \
                "${backup_destination}/" ||\
            report "$?" "remote backup via rsync"

    return 0
}

function cleanup_remote_backup {
    # Clean up after remove backup
    # This function may be used to handle trapped signals
    # Make sure rsync is done
    killall rsync || report "$?" "kill the rsync processes"
    slow rsync
    return 0
}

function firewall_active {
    # Check the firewall is up
    not_empty "date stamp" "$STAMP"
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
    local intf=$1
    ping -q -w 1 -c 1 `ip route | grep default | grep "$intfc" | cut -d ' ' -f 3`
    rc=$?
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
    not_empty "interface to check" "$intfc"
    not_empty "url for ping" "$tgt"

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
            >&2 echo "${STAMP}: $packets_lost packets lost from ${tgt} via ${intfc}"
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
    not_empty "interface to check" "$intfc"
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
    local ovpn=$1
    log_setting "OpenVPN configuration to start" "$ovpn"
    killall openvpn || report $? "stopping any tunnel"
    slow openvpn
    sudo openvpn --daemon --config "$ovpn"
    while ! check_single_tunnel; do
        sleep 5.0
    done
    return 0
}

function network_check {
    # Make source network connection is as expected
    log_setting "usual wired interface" "$wired"
    log_setting "usual wireless interface" "$wireless"
    log_setting "tunnel interface" "$tunnel"
    log_setting "default OpenVPN configuration" "$default_ovpn"
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
    for svc in "${essential[@]}"; do
        make_active "${svc}"
    done
    return 0
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

# Make sure we're excluding sensitive files
for f in ${secret[@]}; do
    check_contains "${HOME}/.exclude_remote" "$f"
done

# Check the network
network_check

# System checks
system_check

# Run package related maintenance tasks
run_package_maintenance

# Run the backups
run_local_backup
run_remote_backup "${HOME}"
run_remote_backup '/mnt/data'

# Cleanup and exit with code 0
cleanup 0

