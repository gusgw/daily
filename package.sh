##  Run system update and package maintenance

##  Settings
#   STAMP should be set by a call to set_stamp in useful.sh.

##  Default
#   USER

##  Dependencies
#   return_codes.sh
#   useful.sh

##  Notes
#   Several update and maintenance tasks mostly
#   taken from the Arch Wiki.
#   Output files are created in the user's home folder
#   but deleted on clean up. It's assumed that they are
#   usually saved somewhere before that cleanup.
#   Running system updates without confirmation is also
#   something that should be done with caution, though I
#   find it is not a problem perhaps because I do check the
#   Arch website for news and advice fairly often.

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

cleanup_functions+=('cleanup_package_maintenance')

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

    >&2 echo "${STAMP}: DBG cleanup_package_maintenance"

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
