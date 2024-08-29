#! /bin/bash

# Daily maintenance tasks

# Set return codes as used in general
. return_codes.sh

echo "TRAPPED_SIGNAL = "$TRAPPED_SIGNAL

# Limits for parallel work
MAX_SUBPROCESSES=16
SIMULTANEOUS_TRANSFERS=32

# Set a wait time in seconds
# for any task that is attempted
# repeatedly
WAIT=5.0

# Number of attempts for checks
# that repeat on fail
ATTEMPTS=10

# Make sure these units are active
UNITS_TO_CHECK=( "syncthing@${USER}.service" 'sshd.service' 'apparmor.service' 'updatedb.timer' )

# Automatically ensure that these folders and files
# are not copied to remote backups etc.
SECRET_FOLDERS=( '.ssh' '.gnupg' '.cert' '.pki' '.password-store' )
SECRET_FILES=( "*.asc" "*.key" "*.pem" "id_rsa*" "id_dsa*" "id_ed25519*" )

# Also keep these from being sent to cloud storage
SENSITIVE_FOLDERS=( '.git' '.stfolder' '.stversions' '.local' )

# Symbols to separate output sections
RULE="***"

#################################
# Utility functions

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
    # then cleanup and quit if it is.
    # Generally this is used to check that parameters
    # have been provided so the return code when the
    # expression is empty is ${MISSING_INPUT}.
    local ne_description=$1
    local ne_check=$2
    if [ -z "$ne_check" ]; then
        >&2 echo "${STAMP}: cannot run without ${ne_description}"
        cleanup "${MISSING_INPUT}"
    fi
    return 0
}

function log_setting {
    # Make sure a setting is provided
    # and report it
    local ls_description=$1
    local ls_setting=$2
    not_empty "date stamp" "${STAMP}"
    not_empty "$ls_description" "$ls_setting"
    >&2 echo "${STAMP}: ${ls_description} is ${ls_setting}"
    return 0
}

function check_exists {
    # Make sure a file or folder or link exists
    # then cleanup and quit if not
    local ce_file_name=$1
    log_setting "file or directory name that must exist" "$ce_file_name"
    if ! [ -e "$ce_file_name" ]; then
        >&2 echo "${STAMP}: cannot find $ce_file_name"
        cleanup "$MISSING_FILE"
    fi
    return 0
}

function check_contains {
    # Make sure a file exists and contains
    # the given string.
    local cc_file_name=$1
    local cc_string=$2
    log_setting "file name to check" "$cc_file_name"
    log_setting "string to check for" "$cc_string"
    not_empty "date stamp" "$STAMP"
    if [ -e "$cc_file_name" ]; then
        if ! grep -qs "${cc_string}" "${cc_file_name}"; then
            >&2 echo "${STAMP}: ${cc_file_name} does not contain ${cc_string}"
            cleanup "$BAD_CONFIGURATION"
        fi
    else
        >&2 echo "${STAMP}: cannot find ${cc_file_name}"
        cleanup "$MISSING_FILE"
    fi
    return 0
}

function path_as_name {
    # Convert a path to a string that
    # can be used as a name. This is sometimes
    # useful for naming archives and so on.
    local pan_path=$1
    not_empty "path to convert to a name" "$pan_path"
    echo "$pan_path" |\
        sed 's:^/::' |\
        sed 's:/:-:g' |\
        sed 's/[[:space:]]/_/g'
    return 0
}

function report {
    # Inform the user of a non-zero return
    # code, and if an exit
    # message is provided as a third argument
    # also exit cleanly
    local r_rc=$1
    local r_description=$2
    local r_exit_message=$3
    >&2 echo "${STAMP}: ${r_description} exited with code $r_rc"
    if [ -z "$r_exit_message" ]; then
        >&2 echo "${STAMP}: continuing . . ."
    else
        >&2 echo "${STAMP}: $r_exit_message"
        cleanup $r_rc
    fi
    return $r_rc
}

function slow {
    # Wait for all processes with given name to disappear
    # rsync in particular seems to hang around

    ##########################################################
    # The number of seconds to wait is globally set as $WAIT #
    ##########################################################

    local s_pname=$1
    log_setting "program name to wait for" "$s_pname"
    for pid in $(pgrep $s_pname); do
        while kill -0 "$pid" 2> /dev/null; do
            >&2 echo "${STAMP}: ${s_pname} ${pid} is still running"
            sleep ${WAIT}
        done
    done
}

function print_rule {
    echo
    echo "$RULE"
    echo
}

function print_error_rule {
    >&2 echo
    >&2 echo "$RULE"
    >&2 echo
}

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

function magpie {
    not_empty "mail server" "$MAIL_SERVER"
    not_empty "conda script to source" "$CONDASH"
    server=$(pgrep "${MAIL_SERVER}")
    rc=$?
    if [ "$rc" -eq 0 ]; then
        eval "$(conda shell.bash hook)"
        source "$CONDASH"
        conda activate magpie
        ${HOME}/magpie sync 2>&1
        conda deactivate
    else
        report "$rc" "setup conda for magpie"
    fi
    return $rc
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

    ##########################################################
    # The number of seconds to wait is globally set as $WAIT #
    ##########################################################

    local pr_intfc=$1
    log_setting "interface for router ping" "$pr_intfc"
    local pr_rc=1
    local pr_count=0
    while  [ "$pr_rc" -gt 0 ] && [ "$pr_count" -lt "$ATTEMPTS" ]; do
        sleep ${WAIT}
        ping -q -w 1 -c 1 `ip route |\
                           grep default |\
                           grep "$pr_intfc" |\
                           cut -d ' ' -f 3`
        pr_rc=$?
        pr_count=$((pr_count+1))
    done
    if [ "$pr_rc" -gt 0 ]; then
        report "$pr_rc" "ping to local router via $pr_intfc" "no network so stop"
    fi
    return 0
}

function ping_check {
    # Check ping via given interface to given url
    local pc_intfc=$1
    local pc_tgt=$2
    not_empty "date stamp" "$STAMP"
    log_setting "interface to check" "$pc_intfc"
    log_setting "url for ping" "$pc_tgt"

    # Max lost packet percentage
    local pc_max_loss=50
    local pc_packet_count=10
    local pc_timeout=20
    local pc_packets_lost=$(ping -W $pc_timeout -c $pc_packet_count -I $pc_intfc $pc_tgt |\
                            grep % |\
                            awk '{print $6}')
    if ! [ -n "$pc_packets_lost" ] || [ "$pc_packets_lost" == "100%" ]; then
        cleanup $NETWORK_ERROR
        >&2 echo "${STAMP}: all packets lost from ${pc_tgt} via ${pc_intfc}"
    else
        if [ "${pc_packets_lost}" == "0%" ]; then
            return 0
        else
            # Packet loss rate between 0 and 100%
            >&2 echo "${STAMP}: $pc_packets_lost packets \
                      lost from ${pc_tgt} via ${pc_intfc}"
            local pc_real_loss=$(echo $pc_packets_lost | sed 's/.$//')
            if [[ ${pc_real_loss} -gt ${pc_max_loss} ]]; then
                cleanup $NETWORK_ERROR
            else
                return 0
            fi
        fi
    fi
}

function check_intfc {
    # Check an interface is available
    local ci_intfc=$1
    log_setting "interface to check" "$ci_intfc"
    local ci_intfc_list=$(ip link |\
                          sed -n  '/^[0-9]*:/p' | grep UP | grep -v DOWN |\
                          sed 's/^[0-9]*: \([0-9a-z]*\):.*/\1/')
    for i in $ci_intfc_list; do
        if [ "$i" == "$ci_intfc" ]; then
            return 0
        fi
    done
    return 1
}

function check_single_tunnel {
    # Make sure there is only a single tunnel set up

    >&2 echo "${STAMP}: check_single_tunnel"

    local cst_count=$(ip link |\
                      sed -n  '/^[0-9]*:/p' |\
                      sed 's/^[0-9]*: \([0-9a-z]*\):.*/\1/' |\
                      grep tun |\
                      wc -l)
    if [ "$cst_count" -eq 0 ]; then
        >&2 echo "${STAMP}: tunnel not found"
        return 1
    else
        if [ "$cst_count" -gt 1 ]; then
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

    local st_ovpn=$1
    log_setting "OpenVPN configuration to start" "$st_ovpn"
    killall openvpn || report $? "stopping any tunnel"
    slow openvpn
    sudo openvpn --daemon --config "$st_ovpn"
    while ! check_single_tunnel; do
        sleep "$WAIT"
    done
    return 0
}

function network_check {

    >&2 echo "${STAMP}: network_check"

    local nc_wired=$1
    local nc_wireless=$2
    local nc_tunnel=$3
    local nc_default_ovpn=$4

    # Make source network connection is as expected
    log_setting "usual wired interface" "$nc_wired"
    log_setting "usual wireless interface" "$nc_wireless"
    log_setting "tunnel interface" "$nc_tunnel"
    log_setting "default VPN configuration" "$nc_default_ovpn"

    firewall_active
    if check_intfc "$nc_wired"; then
        sudo rfkill block wlan
        ping_router "$nc_wired"
    else
        sudo rfkill unblock wlan
        ping_router "$nc_wireless"
    fi
    if ! (check_intfc "$nc_tunnel" &&\
          ping_check "$nc_tunnel" wiki.archlinux.org); then
        start_tunnel $nc_default_ovpn
    fi
    return 0
}

function system_check {
    # Check services are running

    ##################################################################
    # System units to check are set globally in ${UNITS_TO_CHECK[@]} #
    ##################################################################

    >&2 echo "${STAMP}: system_check"

    print_rule
    for svc in "${UNITS_TO_CHECK[@]}"; do
        make_active "${svc}"
        print_rule
    done
    return 0
}

function make_active {
    # Make sure a systemd unit is active
    local ma_unit=$1
    log_setting "unit to activate" "$ma_unit"

    if ! sudo systemctl is-active --quiet "$ma_unit"; then
        sudo systemctl start "$ma_unit" ||\
            report $? "starting $ma_unit"
        if sudo systemctl is-failed --quiet "$ma_unit"; then
            sudo systemctl status --no-pager --lines=10 "$ma_unit" ||\
                report $? "get status of $ma_unit"
            cleanup "$SYSTEM_UNIT_FAILURE"
        fi
    fi
    sudo systemctl status --no-pager --lines=0 "$ma_unit" ||\
        report $? "get status of $ma_unit"
    return 0
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

    # Record disk space used by packages
    sudo expac -H M '%m\t%n' 1> ${STAMP}-package_sizes.txt ||\
        report "$?" "finding disk space used by each package"

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
    rm -f ${STAMP}-possible_orphan_list.txt
    rm -f ${STAMP}-package_sizes.txt
    rm -f ${STAMP}-package_list.txt
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

# Set the month for use in the encrypted folder to offload,
# and other occasional maintenance.
set_month

# Check the network
# network_check   "$MAIN_WIRED" \
#                 "$MAIN_WIRELESS" \
#                 "$MAIN_TUNNEL" \
#                 "$DEFAULT_VPN"

# System checks
# system_check

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
